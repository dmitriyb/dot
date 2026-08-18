# goose-local overlay: only box-etc — everything else resolves in the pin.
final: prev: {
  # Minimal /etc identity database (same pattern as spexmachina/overlay.nix):
  # after faber-box drops to the host uid, git needs getpwuid to resolve.
  # Read-only image content, machine-agnostic; one row per host uid.
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
  # NOTE: do not bake goose config into the image — faber-box creates /home/box
  # fresh at box start, so image-baked home content never reaches the agent.
  # The setup-goose PRELUDE hook writes ~/.config/goose/config.yaml instead.
}
