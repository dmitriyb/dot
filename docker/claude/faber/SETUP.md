# Faber + portitor local setup (spexmachina)

Ordered runbook to exercise the dot faber/portitor pieces on the host, before
opening the PR. Host needs: **docker, nix, git, and a YubiKey** (for the role
keys). Steps 0–3 stand up faber; 4 stands up the gate; 5 is the secured run.

## 0. Install this branch (stow)
```sh
cd <dot> && git checkout faber-spexmachina-config && ./setup.sh
```
Puts `docker-claude`, the new `portitor-add-repo` helper, and the skills on PATH.
Verify: `docker-claude --help | grep add-repo`.

## 1. Build the faber binaries
```sh
cd <faber-repo>
go build -o ~/.local/bin/faber ./cmd/faber
CGO_ENABLED=0 GOOS=linux go build -o ~/.local/bin/faber-box ./cmd/faber-box   # static; runs INSIDE the box
faber --help
```

## 2. Pin claude-code in the overlay (no npm — Anthropic native release)
```sh
ver=$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest)
curl -fsSL "https://downloads.claude.ai/claude-code-releases/$ver/manifest.json" | jq '.platforms'
```
Edit `docker/claude/faber/overlay.nix`: set `claudeVersion=$ver` and the per-arch
`sha256` from the manifest checksums. (Or leave `lib.fakeSha256` and let
`faber build` print the real hash to paste back.)

## 3. Faber gateless smoke — the make-or-break test
Run **from the config dir** (the overlay path is CWD-relative):
```sh
cd docker/claude/faber
faber validate --config orchestrator-smoke.yaml
faber build    --config orchestrator-smoke.yaml     # nix -> image -> docker load
faber run smoke --config orchestrator-smoke.yaml --param topic=hello
```
Success = a schema-valid `result.json` under `.faber/runs/<id>/`. This proves the
whole never-run spine: nix build → docker run → headless agent → result extraction.

## 4. Portitor: keys + gate config
```sh
docker-claude --portitor init --repo <portitor-repo-path>          # persists host paths
docker-claude --portitor add-repo spexmachina --slug dmitriyb/spexmachina
#   -> creates YubiKey resident role keys if missing (implementer/reviewer/merger),
#      writes repos.d/spexmachina.json + allowed_signers into PORTITOR_CONFIG_DIR
#      (default ~/.dca-keys/portitor-config), checks the PAT, pins the host key.
# store the GitHub PAT (Contents+PR) under keychain service=portitor account=default
docker-claude --portitor up                                        # portitor + egress
docker-claude --portitor add-repo spexmachina --slug dmitriyb/spexmachina --provision
#   (or: docker exec -u git portitor portitor add-repo --repo spexmachina \
#          --upstream https://github.com/dmitriyb/spexmachina.git)
```
Verify the gate: a signed feature push is accepted + auto-opens a PR; an unsigned
or `main`-targeted push is rejected; an implementer-signed `"status":"closed"` on
`.beads/issues.jsonl` is rejected, a reviewer-signed one accepted.

## 5. Faber secured run (only after 3 + 4 pass) — Gate B
Fill `orchestrator-spexmachina.yaml`: `keys/portitor_host_key.pub` (from step 4's
pin), `identities` key paths, `hooks/*` (wrap dot's `start-implement`/`fetch-pr`),
credentials resolver. Author the `spex` + `br` overlay derivations (templated in
`overlay.nix`). Then:
```sh
faber run bead --config orchestrator-spexmachina.yaml --param bead=<bead-id>
```

## Iterating
`overlay.nix` and `orchestrator-*.yaml` are read from the repo, so edits take
effect immediately. The helper is stowed to libexec — re-run `./setup.sh` after
editing it, or run it directly from
`shared/.local/libexec/docker-claude/portitor-add-repo`.
```
