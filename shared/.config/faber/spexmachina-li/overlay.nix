# faber build overlay for the goose-spex-box (spexmachina-li local implementer).
#
# DUPLICATION, SURFACED: spex / br / portitor-client / box-etc are copied
# verbatim from ../spexmachina/overlay.nix. A composing import
# (`import ../spexmachina/overlay.nix final prev // {...}`) would break because
# faber STAGES the declared overlay file next to its rendered image expression,
# where the relative import no longer resolves. So the pins below are a THIRD
# copy (after the two base faber overlays and versions.json) — keep all of them
# in sync when bumping spex/br. The one genuinely new derivation is goose-agent.

final: prev:

let
  # beads_rust release arch token (its assets use arm64 / x86_64).
  brArch = if prev.stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64";

  # spex release arch token (its assets use arm64 / amd64 — goreleaser naming).
  spexArch = if prev.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";

  spexVersion = "0.1.0";
  spexSha256 = {
    "arm64" = "f087a817e10f8612bf1b6daf207b6f9d327aad62fcee1427ce248004c3e5a9c5";
    "amd64" = "2bf0ed718ebe6d04eba2b4e5677f561c05f733b991be37e1e2996a5de5d7c173";
  };

  brVersion = "0.2.16";
  brSha256 = {
    "arm64"  = "0lfch2p45cky01fakcrx2kwg6wl1lf1kwiqpwq0grsl3slqdrdc4";
    "x86_64" = "19mirqrbcl2zzm3sm65rijms9glkjygnqk9kqzknd4gc9k2gn7j6";
  };
in
{
  # --- goose-agent: goose-cli behind a config-pinning wrapper ------------------
  # faber invokes the bare name `goose` (FABER_AGENT_CLI); this wrapper writes
  # the goose config BEFORE the real CLI reads it. Two proven constraints force
  # the wrapper shape (see goose-local scratch, dot/docker/goose-local):
  #   * faber-box creates the box home FRESH at start — image-baked config
  #     files under /home/box never reach the agent;
  #   * with no config goose enables its dynamic_task subagent builtin, which
  #     local models delegate to and then wedge against the slow endpoint.
  # The prelude-hook route the scratch used is closed here: the base project's
  # preludes (claim-bead etc.) are single-file mounts that cannot be extended
  # without forking them. A wrapper on the agent binary is the remaining seam
  # that runs with the agent's HOME, after the home exists, before goose reads
  # config. Overwrite unconditionally: the box may pre-create a stub config.
  # Provider/model/endpoint stay in the template env (GOOSE_* / OPENAI_*).
  goose-agent = final.symlinkJoin {
    name = "goose-agent";
    paths = [
      (final.writeShellScriptBin "goose" ''
        mkdir -p "$HOME/.config/goose"
        cat > "$HOME/.config/goose/config.yaml" <<'EOF'
        extensions:
          developer:
            enabled: true
            type: builtin
            name: developer
            timeout: 300
          dynamic_task:
            enabled: false
            type: builtin
            name: dynamic_task
        EOF
        exec ${final.goose-cli}/bin/goose "$@"
      '')
    ];
    meta.description = "goose-cli behind a config-pinning wrapper (developer ext only, no subagent delegation)";
  };

  # --- spex: prebuilt signed release (copy of ../spexmachina/overlay.nix) ------
  spex = final.stdenv.mkDerivation {
    pname = "spex";
    version = spexVersion;
    src = final.fetchurl {
      url = "https://github.com/dmitriyb/spexmachina/releases/download/v${spexVersion}/spex_${spexVersion}_linux_${spexArch}.tar.gz";
      sha256 = spexSha256.${spexArch};
    };
    sourceRoot = ".";
    installPhase = ''install -Dm755 spex "$out/bin/spex"'';
    meta.description = "Spex Machina structural spec CLI (pinned signed release)";
  };

  # --- br (beads_rust): prebuilt glibc release (copy) --------------------------
  br = final.stdenv.mkDerivation {
    pname = "br";
    version = brVersion;
    src = final.fetchurl {
      url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-linux_${brArch}.tar.gz";
      sha256 = brSha256.${brArch};
    };
    sourceRoot = ".";
    nativeBuildInputs = [ final.autoPatchelfHook ];
    buildInputs = [ final.stdenv.cc.cc.lib ];
    installPhase = ''install -Dm755 br "$out/bin/br"'';
    meta.description = "beads_rust issue tracker CLI";
  };

  # --- portitor-client: SSH-forwarded gate client (copy) -----------------------
  portitor-client = final.symlinkJoin {
    name = "portitor-client";
    paths = [
      (final.writeShellScriptBin "portitor" ''
        set -euo pipefail
        [ -n "''${PORTITOR_HOST:-}" ] || { echo "portitor: PORTITOR_HOST is not set — the template env must name the gate container" >&2; exit 1; }
        args=("$@")
        if [ "''${1:-}" = pr ] && [ -n "''${FABER_INPUT_REPO:-}" ] && [[ " $* " != *" --repo "* ]]; then
          args=("$@" --repo "$FABER_INPUT_REPO")
        fi
        # GIT_SSH_COMMAND is a command LINE (ssh + -o flags); word-split it on purpose.
        exec ''${GIT_SSH_COMMAND:-ssh} "git@$PORTITOR_HOST" portitor "''${args[@]}"
      '')
    ];
    meta.description = "in-box portitor client (SSH-forwarded, credential-less)";
  };

  # --- box-etc: minimal /etc identity database (copy) --------------------------
  box-etc = final.symlinkJoin {
    name = "box-etc";
    paths = [
      (final.writeTextDir "etc/passwd" ''
        root:x:0:0:root:/root:/bin/sh
        box:x:1000:1000:faber box (linux host):/home/box:/bin/sh
        boxm:x:502:20:faber box (mac host):/home/box:/bin/sh
      '')
      (final.writeTextDir "etc/group" ''
        root:x:0:
        box:x:1000:
        staff:x:20:
      '')
    ];
    meta.description = "minimal /etc passwd+group so in-box getpwuid resolves";
  };
}
