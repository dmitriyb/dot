# faber build overlay for spexmachina development boxes.
# Merged into the PINNED nixpkgs set (see images.yaml: pin -> nixos-25.11, which
# ships Go 1.25.10 — the spexmachina checkout the box COMPILES needs go >= 1.25.0;
# spex itself is no longer built here) as an overlay:
#   final: prev: { <name> = ...; }
# Provides the three tools NOT in nixpkgs — proven via `faber validate`:
#   claude-code, br, spex   (git/openssh/go/gopls/coreutils/bash resolve natively).
#
# All three hashes below are REAL (spex is the v0.1.0 signed release, both arch
# hashes off its manifest.json; claude-code round-trips a smoke; br is the v0.2.16
# glibc release). The only stub is br's linux_x86_64 hash — this box targets arm64
# (the macOS Docker VM); fill the x86_64 hash from the release if you ever build
# the image on an x86_64 host.

final: prev:

let
  # claude-code release arch token (Anthropic naming: arm64 / x64).
  arch = if prev.stdenv.hostPlatform.isAarch64 then "arm64" else "x64";
  platform = "linux-${arch}";   # dockerTools images are glibc, so no "-musl".

  # beads_rust release arch token (its assets use arm64 / x86_64).
  brArch = if prev.stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64";

  # spex release arch token (its assets use arm64 / amd64 — goreleaser naming).
  spexArch = if prev.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";

  # --- claude-code pin ---------------------------------------------------------
  # Version from https://downloads.claude.ai/claude-code-releases/latest ; the
  # per-platform sha256 is manifest.json .platforms[<platform>].checksum (a real
  # sha256, no npm involved).
  claudeVersion = "2.1.220";
  claudeSha256 = {
    "linux-x64"   = "674f61f20ff306f3100cf9200e4c36c4b70278b5bef2884549819b942a89c863";
    "linux-arm64" = "159e4a51d796f3bf14677577100f7efb845611b1ceaf0c30cbd8d4650d942185";
  };

  # --- spex pin ----------------------------------------------------------------
  # spexmachina's first tagged release. Version + per-arch sha256 come from the
  # release's manifest.json (the .sha256 sidecar assets carry the same values).
  spexVersion = "0.1.0";
  spexSha256 = {
    "arm64" = "f087a817e10f8612bf1b6daf207b6f9d327aad62fcee1427ce248004c3e5a9c5";
    "amd64" = "2bf0ed718ebe6d04eba2b4e5677f561c05f733b991be37e1e2996a5de5d7c173";
  };

  # --- br (beads_rust) pin -----------------------------------------------------
  brVersion = "0.2.16";
  brSha256 = {
    "arm64"  = "0lfch2p45cky01fakcrx2kwg6wl1lf1kwiqpwq0grsl3slqdrdc4";   # verified
    "x86_64" = "19mirqrbcl2zzm3sm65rijms9glkjygnqk9kqzknd4gc9k2gn7j6";   # verified (nix-prefetch-url, arch host)
  };
in
{
  # --- claude-code: Anthropic native release binary (no npm) -------------------
  # The release is a Bun single-file executable: the Bun runtime with the app
  # appended after the ELF, located at runtime from an on-disk offset. ANY edit
  # that shifts the file layout breaks it, and there are two independent traps
  # (both verified empirically against 2.1.207):
  #   * `strip` (nix's default fixup) rewrites sections -> the offset is stale
  #     -> claude silently degrades to the bare Bun runtime. Hence dontStrip.
  #   * `patchelf --set-rpath` shoves the ELF version tables past EOF -> the
  #     loader segfaults before main(). So NO rpath may be added. autoPatchelfHook
  #     is safe ONLY because glibc is claude's sole NEEDED library: it sets the
  #     interpreter and adds no rpath. Keep buildInputs empty — a NEEDED lib
  #     beyond glibc would reintroduce the segfault.
  # Patching only the interpreter lets the kernel load the binary directly, so
  # /proc/self/exe stays claude (multi-call dispatch + CLAUDE_CODE_EXECPATH work).
  # Recipe cross-checked against github.com/sadjow/claude-code-nix.
  claude-code = final.stdenv.mkDerivation {
    pname = "claude-code";
    version = claudeVersion;
    src = final.fetchurl {
      url = "https://downloads.claude.ai/claude-code-releases/${claudeVersion}/${platform}/claude";
      sha256 = claudeSha256.${platform};
    };
    dontUnpack = true;
    dontStrip = true;                               # stripping corrupts the Bun trailer
    nativeBuildInputs = [ final.autoPatchelfHook final.makeBinaryWrapper ];
    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/.claude-unwrapped"
      # --inherit-argv0 preserves claude's argv[0]-based multi-call dispatch;
      # USE_BUILTIN_RIPGREP=0 + real rg on PATH avoids the embedded fast tool.
      makeBinaryWrapper "$out/bin/.claude-unwrapped" "$out/bin/claude" \
        --inherit-argv0 \
        --set DISABLE_AUTOUPDATER 1 \
        --set DISABLE_INSTALLATION_CHECKS 1 \
        --set USE_BUILTIN_RIPGREP 0 \
        --prefix PATH : ${final.lib.makeBinPath [ final.ripgrep final.procps final.bubblewrap final.socat ]}
      runHook postInstall
    '';
    meta.description = "Claude Code native CLI (pinned Anthropic release, Bun single-file executable)";
  };

  # --- spex: prebuilt signed release from the spexmachina repo ------------------
  # v0.1.0 is spexmachina's first tagged release, so the box installs the published
  # binary instead of building the repo at a rev. The asset is a STATICALLY linked
  # Go ELF (no interpreter, no NEEDED libs), so unlike br it needs no
  # autoPatchelfHook and no buildInputs — unpack and install.
  # To ship a newer spex: bump spexVersion + BOTH hashes above from the release's
  # manifest.json, and mirror the same values into ~/.local/share/versions.json
  # (the manifest of record — nothing reads it automatically; see its spex note).
  spex = final.stdenv.mkDerivation {
    pname = "spex";
    version = spexVersion;
    src = final.fetchurl {
      url = "https://github.com/dmitriyb/spexmachina/releases/download/v${spexVersion}/spex_${spexVersion}_linux_${spexArch}.tar.gz";
      sha256 = spexSha256.${spexArch};
    };
    sourceRoot = ".";                               # tarball holds LICENSE/README.md/spex at the root
    installPhase = ''install -Dm755 spex "$out/bin/spex"'';
    meta.description = "Spex Machina structural spec CLI (pinned signed release)";
  };

  # --- br (beads_rust): prebuilt glibc release, ELF autopatched ----------------
  # The v0.2.16 asset is a .tar.gz containing a single `br` binary at the root.
  br = final.stdenv.mkDerivation {
    pname = "br";
    version = brVersion;
    src = final.fetchurl {
      url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-linux_${brArch}.tar.gz";
      sha256 = brSha256.${brArch};
    };
    sourceRoot = ".";                               # tarball extracts `br` at the root
    nativeBuildInputs = [ final.autoPatchelfHook ];
    # The prebuilt (Rust) binary needs libgcc_s.so.1 for stack unwinding;
    # give autoPatchelfHook the gcc runtime lib to resolve it. (An rpath here is
    # fine — br is an ordinary ELF, not the fragile claude-code Bun executable.)
    buildInputs = [ final.stdenv.cc.cc.lib ];
    installPhase = ''install -Dm755 br "$out/bin/br"'';
    meta.description = "beads_rust issue tracker CLI";
  };

  # --- portitor-client: the box's ONLY GitHub channel ---------------------------
  # The box holds no GitHub credential; every PR action (fetch/comment/review/
  # merge) is `portitor pr …`, forwarded over SSH to the gate, whose forced
  # command dispatches it and calls GitHub with ITS token. Baked into the image
  # up front like spex/br — no post-hoc delivery, one `faber build` ships it all.
  #
  # ONE binary, `portitor`, deliberately no `pr` alias: GNU coreutils (also in
  # this toolset) ships a bin/pr (the paginator), and the image's link-farm is
  # first-wins over alphabetically-sorted packages — an alias named `pr` would be
  # silently shadowed. Hooks and skills call `portitor pr …` directly.
  #
  # Trust + identity reuse the exact channel git already has in the box:
  #   * $GIT_SSH_COMMAND — set by the box's host-key phase — carries the pinned
  #     known-hosts file + StrictHostKeyChecking=yes, so the client trusts only
  #     the pinned gate (plain `ssh` would fail closed on an unknown host);
  #   * the forwarded ssh-agent supplies the one role key (role = fingerprint).
  # $PORTITOR_HOST names the gate container and comes from the template env —
  # explicit, no baked default. --repo is injected from $FABER_INPUT_REPO (the
  # step's bound repo input) when the caller didn't pass one.
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

  # --- box-etc: minimal /etc identity database ---------------------------------
  # The nix image ships no /etc/passwd; after faber-box drops to the host uid,
  # ssh (invoked by git for the gate clone/push) hard-fails its getpwuid lookup
  # with "No user exists for uid N". Baking passwd/group into the image fixes it
  # with no bind mounts and no host paths: passwd is a lookup table, so one
  # machine-agnostic image lists every host uid the boxes run as — add a line
  # when a new host joins. Read-only image content, discarded with the container.
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
