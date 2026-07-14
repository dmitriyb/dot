# faber build overlay for spexmachina development boxes.
# Merged into the pinned nixpkgs (24.05) set: `final: prev: { <name> = ...; }`.
# Provides the three tools NOT in nixpkgs 24.05 — proven via `faber validate`:
#   claude-code, br, spex   (git/openssh/go/gopls/coreutils resolve natively).
#
# Placement: referenced by each template's `build.overlay: ./nix/overlay.nix`
# in orchestrator.yaml. NOTE (verified gotcha): faber resolves overlay paths
# relative to the PROCESS CWD, not the config file — run faber from the config
# dir, or use an absolute overlay path.
#
# Filling hashes: put lib.fakeSha256 (or "") first; `faber build` / `nix build`
# prints the correct hash on mismatch — paste it back. Standard nix workflow.

final: prev:

let
  # Map the box's build platform to Anthropic's release arch token.
  arch =
    if prev.stdenv.hostPlatform.isAarch64 then "arm64"
    else "x64";
  # dockerTools images are glibc (not musl), so no "-musl" suffix.
  platform = "linux-${arch}";

  # Pin the claude-code release. Resolve the concrete version from
  #   https://downloads.claude.ai/claude-code-releases/latest
  # and the per-platform sha256 from
  #   https://downloads.claude.ai/claude-code-releases/<version>/manifest.json
  #   (.platforms["<platform>"].checksum — a real sha256, no npm involved).
  claudeVersion = "2.1.207";
  # sha256 (hex) from the release manifest.json .platforms[<platform>].checksum:
  #   https://downloads.claude.ai/claude-code-releases/<version>/manifest.json
  claudeSha256 = {
    "linux-x64"   = "85e7e988a392d859f90802ca21fb26e89d3c9ab527f5ed0b08df3955e34d5c83";
    "linux-arm64" = "8bc14a284065383460f37981d724b8f7aa7ca93c9849d2fe367e08f03383f454";
  };
in
{
  # --- claude-code: Anthropic native release binary (no npm) ---
  # The release is a Bun single-file executable: the Bun runtime with the app
  # appended after the ELF, located at runtime from an on-disk offset. ANY edit
  # that shifts the file layout breaks it, and there are two independent traps
  # (both verified empirically against 2.1.207):
  #   * `strip` (nix's default fixup) rewrites sections -> the offset is stale
  #     -> claude silently degrades to the bare Bun runtime (`claude --version`
  #     prints Bun's version, e.g. 1.4.0). Hence dontStrip.
  #   * `patchelf --set-rpath` rewrites the dynamic section -> shoves the ELF
  #     version tables past EOF -> the loader segfaults before main(). So no
  #     rpath may be added. autoPatchelfHook is safe here ONLY because glibc is
  #     claude's sole NEEDED library (found via the patched interpreter), so it
  #     sets the interpreter and adds NO rpath. Keep buildInputs empty: a NEEDED
  #     lib beyond glibc would make autoPatchelfHook add an rpath and bring the
  #     segfault back.
  # Patching only the interpreter lets the kernel load the binary directly, so
  # /proc/self/exe stays claude (its multi-call tool dispatch and
  # CLAUDE_CODE_EXECPATH keep working) — no ld.so wrapper, no nix-ld needed.
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

  # --- spex: built from the spexmachina repo (matches dot's Dockerfile.agent.base) ---
  spex = final.buildGoModule {
    pname = "spex";
    version = "0-unstable";                         # or a tag
    src = final.fetchFromGitHub {
      owner = "dmitriyb";
      repo = "spexmachina";
      rev = "main";                                 # TODO: pin to a commit sha for reproducibility
      sha256 = final.lib.fakeSha256;                # TODO
    };
    vendorHash = final.lib.fakeSha256;              # TODO (or null if the repo has no deps to vendor)
    subPackages = [ "cmd/spex" ];
    # spexmachina is stdlib-first; if vendorHash resolution is noisy, set
    # `proxyVendor = true` or vendor locally.
    meta.description = "Spex Machina structural spec CLI";
  };

  # --- br (beads_rust): prebuilt release binary (matches dot's installer) ---
  # Two options — pick one:
  # (A) fetch the prebuilt release asset (what dot does), autopatch the ELF:
  br = final.stdenv.mkDerivation {
    pname = "br";
    version = "unstable";                           # TODO: pin release tag
    src = final.fetchurl {
      # TODO: the beads_rust prebuilt linux-<arch> asset URL from
      # https://github.com/Dicklesworthstone/beads_rust/releases
      url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/<TAG>/br-${arch}-linux";
      sha256 = final.lib.fakeSha256;                # TODO
    };
    dontUnpack = true;
    nativeBuildInputs = [ final.autoPatchelfHook ];
    installPhase = ''install -Dm755 "$src" "$out/bin/br"'';
    meta.description = "beads_rust issue tracker CLI";
  };
  # (B) from source (fully reproducible, needs cargoHash):
  #   br = final.rustPlatform.buildRustPackage {
  #     pname = "br"; version = "unstable";
  #     src = final.fetchFromGitHub { owner = "Dicklesworthstone"; repo = "beads_rust";
  #       rev = "main"; sha256 = final.lib.fakeSha256; };
  #     cargoHash = final.lib.fakeSha256;
  #   };
}
