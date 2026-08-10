# egress-proxy image, built with Nix dockerTools instead of the Alpine Dockerfile
# that used to live in this directory. A tiny allow-listing forward proxy
# (tinyproxy) that ALSO ships ssh-keyscan (openssh): faber-stack runs
# `docker run --network <net> egress-proxy ssh-keyscan -t ed25519 <gate>` on the
# internal net to pin the gate's host key, so the image must expose ssh-keyscan
# and must NOT set an Entrypoint (that run overrides the default Cmd).
#
# The baked `filter` is a safe DEFAULT (api.anthropic.com only); per-instance
# stacks REPLACE it by bind-mounting $CONFIG_DIR/egress-filter over
# /etc/tinyproxy/filter (see portitor-stack.yml + the egress README).
#
#   nix-build egress-image.nix && docker load -i result   # -> egress-proxy:nix

let
  # Pinned nixpkgs from the shared manifest (same pin as the gate + boxes).
  versions = builtins.fromJSON (builtins.readFile ./../versions.json);
  pkgs = import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${versions.nixpkgs.rev}.tar.gz";
    sha256 = versions.nixpkgs.sha256;
  }) { system = "aarch64-linux"; };

  # /bin only: keep the store's /etc out so our /etc/tinyproxy is the real one.
  runtime = pkgs.buildEnv {
    name = "egress-runtime";
    ignoreCollisions = true;
    pathsToLink = [ "/bin" ];
    paths = [
      pkgs.tinyproxy            # the proxy
      pkgs.openssh              # ssh-keyscan — faber-stack pins the gate host key with it
      pkgs.coreutils            # /sbin/nologin target, general shell utils
      pkgs.bashInteractive      # /bin/sh (dockerTools.binSh)
    ];
  };

  # tinyproxy.conf sets `User tinyproxy`/`Group tinyproxy`, so that account must
  # exist (tinyproxy binds :8888 as root then drops to it).
  passwd = pkgs.writeText "passwd" ''
    root:x:0:0:root:/root:/bin/sh
    tinyproxy:x:998:998:tinyproxy:/var/empty:/sbin/nologin
  '';
  group = pkgs.writeText "group" ''
    root:x:0:
    tinyproxy:x:998:
  '';

in
pkgs.dockerTools.buildLayeredImage {
  name = "egress-proxy";
  tag = "nix";
  contents = [ runtime pkgs.dockerTools.binSh ];

  extraCommands = ''
    mkdir -p etc/tinyproxy sbin var/empty
    ln -s ${pkgs.coreutils}/bin/false sbin/nologin
    cp ${./tinyproxy.conf} etc/tinyproxy/tinyproxy.conf
    cp ${./filter}         etc/tinyproxy/filter
    cp ${passwd} etc/passwd
    cp ${group}  etc/group
    chmod 0644 etc/tinyproxy/tinyproxy.conf etc/tinyproxy/filter etc/passwd etc/group
  '';

  config = {
    # NO Entrypoint: `docker run egress-proxy ssh-keyscan ...` (the host-key pin)
    # must be able to override this default. Default = tinyproxy in the foreground.
    Cmd = [ "tinyproxy" "-d" "-c" "/etc/tinyproxy/tinyproxy.conf" ];
    Env = [ "PATH=/bin" ];
    ExposedPorts = { "8888/tcp" = { }; };
  };
}
