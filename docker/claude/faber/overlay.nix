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
  claudeVersion = "2.1.207";                       # TODO: pin to your chosen release
  claudeSha256 = {
    "linux-x64"   = final.lib.fakeSha256;          # TODO: from manifest.json
    "linux-arm64" = final.lib.fakeSha256;          # TODO: from manifest.json
  };
in
{
  # --- claude-code: Anthropic native release binary (no npm) ---
  claude-code = final.stdenv.mkDerivation {
    pname = "claude-code";
    version = claudeVersion;
    src = final.fetchurl {
      url = "https://downloads.claude.ai/claude-code-releases/${claudeVersion}/${platform}/claude";
      sha256 = claudeSha256.${platform};
    };
    dontUnpack = true;
    nativeBuildInputs = [ final.autoPatchelfHook ];
    buildInputs = [ final.stdenv.cc.cc.lib ];       # libstdc++/libgcc for the prebuilt ELF
    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/claude"
      runHook postInstall
    '';
    meta.description = "Claude Code native CLI (pinned Anthropic release)";
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
