# Scratch/test image: Block's goose CLI against an OpenAI-compatible server on
# the container host (LM Studio). NOT the faber box image — this is the phase-A
# harness check for local-model agents; the faber-native variant lives in the
# goose-local faber project config. Same nixpkgs pin as the spex-box / gate /
# egress images, read from the shared manifest.
#
#   nix-build goose-image.nix && docker load -i result   # -> goose-local:nix

let
  # Single source of truth for the externally-sourced tool versions/hashes.
  versions = builtins.fromJSON
    (builtins.readFile ./../../shared/.local/share/versions.json);

  # Pinned nixpkgs (from versions.json). system is set INSIDE the import so a
  # plain `nix-build` routes the derivation to the configured aarch64-linux
  # linux-builder automatically (a --system CLI flag would be ignored for
  # non-trusted users).
  pkgs = import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${versions.nixpkgs.rev}.tar.gz";
    sha256 = versions.nixpkgs.sha256;
  }) { system = "aarch64-linux"; };

  # Everything goose's developer extension shells out to, merged onto one PATH.
  runtime = pkgs.buildEnv {
    name = "goose-local-runtime";
    ignoreCollisions = true;
    pathsToLink = [ "/bin" ];
    paths = [
      pkgs.goose-cli
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.gitMinimal
      pkgs.gnused
      pkgs.gnugrep
      pkgs.gawk
      pkgs.findutils
      pkgs.diffutils
      pkgs.ripgrep
      pkgs.jq
      pkgs.python3
    ];
  };

  # Minimal /etc identity (box-etc pattern from the spexmachina overlay): git and
  # getpwuid need the running uid to resolve. Scratch runs as root; the 1000/502
  # rows keep the image usable under a dropped uid too.
  passwd = pkgs.writeText "passwd" ''
    root:x:0:0:root:/root:/bin/sh
    goose:x:1000:1000:goose (linux host):/home/goose:/bin/sh
    goosem:x:502:20:goose (mac host):/home/goose:/bin/sh
  '';
  group = pkgs.writeText "group" ''
    root:x:0:
    goose:x:1000:
    staff:x:20:
  '';

in
pkgs.dockerTools.buildLayeredImage {
  name = "goose-local";
  tag = "nix";
  contents = [ runtime pkgs.dockerTools.binSh pkgs.cacert ];

  extraCommands = ''
    mkdir -p etc root home/goose workspace tmp
    cp ${passwd} etc/passwd
    cp ${group}  etc/group
    chmod 0644 etc/passwd etc/group
    chmod 1777 tmp

    # OpenSSL and Go clients look for ca-certificates.crt; cacert installs
    # ca-bundle.crt. Relative link, resolved at runtime (gate-image precedent).
    mkdir -p etc/ssl/certs
    ln -s ca-bundle.crt etc/ssl/certs/ca-certificates.crt
  '';

  config = {
    Env = [
      "PATH=/bin"
      "HOME=/root"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ];
    WorkingDir = "/workspace";
    Cmd = [ "goose" "session" ];
  };
}
