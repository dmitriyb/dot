# portitor gate image, built with Nix dockerTools instead of the Alpine
# Dockerfile in this directory. Produces an aarch64-linux OCI image that runs the
# VERIFIED portitor release binary as a git-over-SSH gate, plus `br` for the
# content_rules bead-close check. The runtime contract (sshd + forced-command
# wiring) is supplied by gate-entrypoint.sh, copied in unchanged — so no portitor
# source checkout is needed to build or run the gate.
#
#   nix-build gate-image.nix && docker load -i result   # -> portitor-gate:nixtest
#
# Everything glibc: the image is a normal glibc userland, so the glibc `br`
# release runs directly (no gcompat/musl shims the Alpine build needed).

let
  # Single source of truth for the externally-sourced tool versions/hashes.
  versions = builtins.fromJSON (builtins.readFile ./../versions.json);

  # Pinned nixpkgs (from versions.json). system is set INSIDE the import so a plain
  # `nix-build` routes the derivation to the configured aarch64-linux linux-builder
  # automatically (a --system CLI flag would be ignored for non-trusted users).
  pkgs = import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${versions.nixpkgs.rev}.tar.gz";
    sha256 = versions.nixpkgs.sha256;
  }) { system = "aarch64-linux"; };

  brVersion = versions.br.version;
  portitorVersion = versions.portitor.version;

  name = "portitor-gate";
  tag = "nixtest";

  # --- br (beads_rust): prebuilt glibc release, ELF autopatched ----------------
  # Mirrors the `br` attr in faber/spexmachina/overlay.nix: glibc tarball with `br`
  # at the root, autoPatchelfHook + stdenv.cc.cc.lib for libgcc_s.so.1 (Rust stack
  # unwinding). versions.json ships the sha256 as hex; fetchurl accepts it directly.
  br = pkgs.stdenv.mkDerivation {
    pname = "br";
    version = brVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-linux_arm64.tar.gz";
      sha256 = versions.br.sha256.linux_arm64;
    };
    sourceRoot = ".";                              # tarball extracts `br` at the root
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    installPhase = ''install -Dm755 br "$out/bin/br"'';
    meta.description = "beads_rust issue tracker CLI";
  };

  # --- portitor: verified goreleaser release binary ----------------------------
  # Tarball layout is `portitor`, LICENSE, README.md at the root. The binary is a
  # statically-linked (CGO-off) Go executable, so it needs no patching — install
  # it as-is. Pinned by sha256 (a Nix build can't fetch-latest + SSHSIG-verify the
  # way the Alpine install.sh did; versions.json carries the pinned hash instead).
  portitor = pkgs.stdenv.mkDerivation {
    pname = "portitor";
    version = portitorVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/dmitriyb/portitor/releases/download/v${portitorVersion}/portitor_${portitorVersion}_linux_arm64.tar.gz";
      sha256 = versions.portitor.sha256.linux_arm64;
    };
    sourceRoot = ".";
    dontBuild = true;
    installPhase = ''install -Dm755 portitor "$out/bin/portitor"'';
    meta.description = "portitor git-over-SSH PR gate";
  };

  # --- su shim -----------------------------------------------------------------
  # gate-entrypoint.sh (and the smoke test) call `su git -c '...'`. This nixpkgs
  # ships NO usable su: shadow and util-linux build with su disabled, and busybox/
  # toybox have the applet compiled out. The original Alpine image used busybox su.
  # Reproduce the needed su(1) subset with setpriv (util-linux) — a pure
  # privilege-drop tool with NO PAM dependency, so it works with no /etc/pam.d.
  # PATH is preserved (not reset) so `gh`/`whoami` still resolve for the callee;
  # HOME/USER are set to the target so `gh auth login` writes to the git user.
  suShim = pkgs.writeShellScriptBin "su" ''
    set -eu
    user=$1; shift
    cmd=
    [ "''${1:-}" = "-c" ] && cmd=''${2:-}
    row=$(${pkgs.gawk}/bin/awk -F: -v u="$user" '$1==u{print $3":"$4":"$6}' /etc/passwd)
    [ -n "$row" ] || { echo "su: unknown user $user" >&2; exit 1; }
    uid=''${row%%:*}; rest=''${row#*:}; gid=''${rest%%:*}; home=''${rest#*:}
    export HOME="$home" USER="$user" LOGNAME="$user"
    if [ -n "$cmd" ]; then
      exec ${pkgs.util-linux}/bin/setpriv --reuid "$uid" --regid "$gid" --init-groups /bin/sh -c "$cmd"
    else
      exec ${pkgs.util-linux}/bin/setpriv --reuid "$uid" --regid "$gid" --init-groups /bin/sh
    fi
  '';

  # --- runtime toolset ---------------------------------------------------------
  # Everything the entrypoint and forced command shell out to, merged onto one
  # PATH. ignoreCollisions because a few coreutils/git/openssh names overlap
  # harmlessly (e.g. link-farm duplicates); first-wins is fine here.
  runtime = pkgs.buildEnv {
    name = "portitor-gate-runtime";
    ignoreCollisions = true;
    # Link ONLY /bin: keep /etc out of the image so extraCommands can build a
    # real, writable /etc/ssh (ssh-keygen -A writes host keys there at runtime).
    # Each binary still references its own libexec/lib by absolute store path.
    pathsToLink = [ "/bin" ];
    paths = [
      pkgs.bashInteractive        # /bin/sh is bash (dockerTools.binSh), keep bash on PATH too
      pkgs.coreutils              # cat, install, printf, env, whoami, false, ...
      pkgs.gawk                   # awk (fingerprint parsing in the entrypoint)
      pkgs.openssh                # ssh-keygen, sshd, ssh
      pkgs.gitMinimal             # git pack for the gated push/fetch
      pkgs.gh                     # `portitor pr` shells out to gh
      pkgs.tini                   # PID 1
      suShim                      # su (setpriv-backed)
      br
      portitor
    ];
  };

  # --- /etc identity + sshd config ---------------------------------------------
  # Built by hand (NOT fakeNss, which lacks the git + sshd users). git's shadow
  # entry is `*` (unlocked-but-passwordless) so sshd pubkey login and `su git`
  # work; sshd is a locked nologin privsep account, required by modern openssh.
  passwd = pkgs.writeText "passwd" ''
    root:x:0:0:root:/root:/bin/sh
    git:x:1000:1000:git:/home/git:/bin/sh
    sshd:x:74:74:sshd privsep:/var/empty:/sbin/nologin
  '';
  group = pkgs.writeText "group" ''
    root:x:0:
    git:x:1000:
    sshd:x:74:
    nogroup:x:65534:
  '';
  shadow = pkgs.writeText "shadow" ''
    root:*:19700:0:99999:7:::
    git:*:19700:0:99999:7:::
    sshd:!:19700:0:99999:7:::
  '';
  sshdConfig = pkgs.writeText "sshd_config" ''
    PasswordAuthentication no
    PubkeyAuthentication yes
    PermitRootLogin no
    UsePAM no
    AuthorizedKeysFile /home/git/.ssh/authorized_keys
    PidFile /run/sshd.pid
  '';

in
pkgs.dockerTools.buildLayeredImage {
  inherit name tag;
  # cacert lands /etc/ssl/certs/ca-bundle.crt as real files (not a buildEnv
  # symlink farm), so it coexists with the writable /etc/ssh built below. Without
  # it the image has no trust store at all and every TLS client fails closed:
  # `gh auth login` in the entrypoint dies on x509, and `set -e` kills the boot.
  contents = [ runtime pkgs.dockerTools.binSh pkgs.cacert ];

  # Filesystem the entrypoint hardcodes: FHS symlinks, the copied entrypoint, /etc
  # identity, sshd config, and the writable dirs (/etc/ssh for `ssh-keygen -A`,
  # /run/sshd + /var/empty for privsep, /srv/git volume, /home/git).
  extraCommands = ''
    mkdir -p usr/local/bin usr/sbin sbin bin etc/ssh run/sshd var/empty srv/git home/git root tmp

    ln -s ${portitor}/bin/portitor  usr/local/bin/portitor
    ln -s ${pkgs.openssh}/bin/sshd  usr/sbin/sshd
    ln -s ${pkgs.tini}/bin/tini     usr/sbin/tini
    ln -s ${pkgs.coreutils}/bin/false sbin/nologin

    cp ${./gate-entrypoint.sh} usr/local/bin/portitor-entrypoint
    chmod 0755 usr/local/bin/portitor-entrypoint

    cp ${passwd} etc/passwd
    cp ${group}  etc/group
    cp ${shadow} etc/shadow
    cp ${sshdConfig} etc/ssh/sshd_config
    chmod 0644 etc/passwd etc/group etc/ssh/sshd_config
    chmod 0640 etc/shadow

    chmod 1777 tmp

    # cacert (in contents) installs the bundle as ca-bundle.crt, but OpenSSL's
    # compiled-in default CAfile — and Go's crypto/x509 search list — look for
    # ca-certificates.crt. Alias it so trust needs NO env var: sshd builds a
    # fresh environment per session (UsePAM no, no PermitUserEnvironment/
    # AcceptEnv), so SSL_CERT_FILE never reaches the forced command, and the
    # gate's serve-time `git fetch upstream` would fail x509 without this.
    # Relative link: the target lives in the cacert layer, resolved at runtime.
    mkdir -p etc/ssl/certs
    ln -s ca-bundle.crt etc/ssl/certs/ca-certificates.crt
  '';

  # chown under fakeroot so the ownership lands in the image tar. git owns its home
  # and the volume; privsep dirs are root-owned 0755 (sshd StrictModes/privsep).
  fakeRootCommands = ''
    chown -R 1000:1000 home/git srv/git
    chown 0:0 run/sshd var/empty
    chmod 0755 run/sshd var/empty
  '';

  config = {
    Entrypoint = [ "/usr/sbin/tini" "--" "/usr/local/bin/portitor-entrypoint" ];
    # SSL_CERT_FILE is honoured by both OpenSSL (git) and Go's crypto/x509
    # (gh, portitor), so one variable covers every TLS client in the image.
    Env = [
      "PATH=/usr/local/bin:/usr/sbin:/bin"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ];
    Volumes = { "/srv/git" = { }; };
    ExposedPorts = { "22/tcp" = { }; };
  };
}
