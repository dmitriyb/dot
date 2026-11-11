# The gate image's extra tools: br, for the bead-closed check and the semantic
# content rule. portitor deploy applies it over portitor's own nixpkgs pin.
#
# Independent of ../../base/overlay.nix (the boxes'): each carries its own br
# version, so a box toolchain bump never rebuilds or swaps the gate. portitor
# deploy stages this file alone, so it imports nothing.

final: prev:

let
  brArch = if prev.stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64";
  brVersion = "0.2.16";
  brSha256 = {
    "arm64"  = "0lfch2p45cky01fakcrx2kwg6wl1lf1kwiqpwq0grsl3slqdrdc4";
    "x86_64" = "19mirqrbcl2zzm3sm65rijms9glkjygnqk9kqzknd4gc9k2gn7j6";
  };
in
{
  br = final.stdenv.mkDerivation {
    pname = "br";
    version = brVersion;
    src = final.fetchurl {
      url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-linux_${brArch}.tar.gz";
      sha256 = brSha256.${brArch};
    };
    sourceRoot = ".";
    nativeBuildInputs = [ final.autoPatchelfHook ];
    # The prebuilt Rust binary needs libgcc_s.so.1 for stack unwinding.
    buildInputs = [ final.stdenv.cc.cc.lib ];
    installPhase = ''install -Dm755 br "$out/bin/br"'';
    meta.description = "beads_rust issue tracker CLI";
  };
}
