#!/usr/bin/env bash
# Build, load, and run the goose-local scratch container.
# No args -> interactive `goose session`; args are passed through verbatim
# (e.g. ./run.sh goose run -t "task", or ./run.sh bash for a shell).
# Requires: nix (aarch64-linux builder), docker, and an OpenAI-compatible
# server on host port 1234 (see README.md).
set -euo pipefail
cd "$(dirname "$0")"

nix-build goose-image.nix
docker load -i result

mkdir -p workspace

# Default bridge network deliberately (NOT a faber internal net): the agent must
# reach the inference server on the host. --add-host makes host.docker.internal
# explicit beyond Docker Desktop/OrbStack's automatic mapping.
run=(docker run --rm -it
  --add-host host.docker.internal:host-gateway
  -v "$PWD/config:/root/.config/goose"
  -v "$PWD/workspace:/workspace"
  -e OPENAI_API_KEY=lm-studio
  -e GOOSE_DISABLE_KEYRING=1
  goose-local:nix)

if [ $# -gt 0 ]; then
  exec "${run[@]}" "$@"
else
  exec "${run[@]}" goose session
fi
