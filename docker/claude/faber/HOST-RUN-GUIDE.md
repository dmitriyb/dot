# Faber host-run guide (spexmachina)

Prepared from dcp (read-only where docker was needed). These artifacts go in a
**dot branch off `agent-harness`** (faber = engine, dot = config). Fill the
TODOs on the host where you have the real values.

## Verified from dcp (facts you can rely on)
- **faber + faber-box build clean** (go 1.26, linux/arm64). `faber` has `validate/build/run/resume`; `faber-box` starts its 9-phase sequencer and correctly enforces its env contract.
- **Agent-invoke contract is correct** — `claude` 2.1.207 accepts `-p --permission-mode --effort --max-budget-usd`, exactly what `agent/box/invoke.go` emits. No faber patch needed. (Was flagged as a risk; cleared.)
- **`faber validate` runs the nix-eval package proof.** In nixpkgs 24.05: `git, openssh, go, gopls, coreutils` resolve; **`claude-code` does NOT** → overlay derivation required (`br`, `spex` likewise — niche/local). No `DefaultNixpkgsPin` bump needed; the overlay owns claude-code as the Anthropic release (no npm).
- **claude-code release is fully pinnable**: `https://downloads.claude.ai/claude-code-releases/<version>/linux-<x64|arm64>/claude`, with the sha256 in `…/<version>/manifest.json` (`.platforms[<platform>].checksum`). The `overlay.nix` uses exactly this.

## Gotchas (bit me during validate)
1. **Overlay paths are CWD-relative**, not config-relative. Run faber **from the config dir**, or use absolute `build.overlay` paths. (Validate from `/workspace/faber` couldn't find `./nix/overlay.nix`; from the config dir it did.)
2. **Both nix AND docker must be on whatever runs `faber build`** (nix builds the image, `docker load` installs it). dcp has nix but no docker → build/run need the host (or DinD-in-dcp).
3. **Filling nix hashes**: leave `lib.fakeSha256`; `faber build`/`nix build` prints the real hash on mismatch — paste it back. Standard workflow.
4. If you ever run faber **inside** dcp via a mounted host docker socket, faber's `-v <host-path>` mounts won't resolve (paths are dcp-local) → "box vanished". Use DinD (nested daemon) instead; then `faber build` produces the image into that daemon and paths stay consistent.

## Order of operations on the host

### A. Prove the spine (gateless — zero security surface)
```sh
cd <dot>/faber-config            # wherever these files live; overlay path is CWD-relative
# 1. fill overlay.nix hashes for claude-code (+ spex, br) — see below
faber validate --config orchestrator-smoke.yaml     # nix-eval proof passes once hashes/derivations resolve
faber build    --config orchestrator-smoke.yaml     # nix -> image -> docker load
faber run smoke --config orchestrator-smoke.yaml --param topic="hello"
#   -> expect a schema-valid result.json under .faber/runs/<id>/ ; this proves
#      image build + docker run + headless agent + result extraction end to end.
```

### B. Onboard spexmachina to portitor (server-side; once)
```sh
# place spexmachina.json at /etc/portitor/repos.d/spexmachina.json (built with jq, NOT heredoc)
# fill role fingerprints (ssh-keygen -lf <key.pub>), allowed_signers, PAT
docker exec -u git portitor portitor add-repo --repo spexmachina \
  --upstream https://github.com/dmitriyb/spexmachina.git
# verify: signed feature push accepted + auto-PR; unsigned/main rejected;
#         implementer-signed "status":"closed" on issues.jsonl rejected, reviewer accepted.
```

### C. Secured single-bead run (Gate B) — trial on a Batch-B bug
```sh
cd <dot>/faber-config
faber validate --config orchestrator-spexmachina.yaml
faber build    --config orchestrator-spexmachina.yaml
faber run bead --config orchestrator-spexmachina.yaml --param bead=<batch-b-bead-id>
```

## TODO checklist (host-specific values I can't supply)
- [ ] `overlay.nix`: claude-code `claudeVersion` + per-arch `sha256` (from manifest.json); `spex` rev + vendorHash + src sha256; `br` release asset URL + sha256 (or the from-source variant).
- [ ] `orchestrator-spexmachina.yaml`: `keys/portitor_host_key.pub`; `identities` key paths (dot `~/.dca-keys/<role>` or FIDO2 sk refs); `hooks/*` scripts wrapping dot's `start-implement`/`prelude-common.sh`/`fetch-pr`; credentials resolver.
- [ ] `spexmachina.json`: role key fingerprints; `allowed_signers` path; portitor PAT (Contents+PR on the repo).
- [ ] Hooks: the faber hook names (`gather-context`, `claim-bead`, `fetch-pr`) should wrap dot's existing `start-*` preludes so the bundle/CONTEXT.md/`spex map context` grounding is reused verbatim.

## Files in this directory
- `overlay.nix` — claude-code (Anthropic release) + spex (buildGoModule) + br derivations.
- `orchestrator-smoke.yaml` — gateless spine proof (run first).
- `orchestrator-spexmachina.yaml` — Gate B (single-bead → review loop → auto-merge).
- `spexmachina.json` — portitor gate config with the R6 bead-close-reviewer-only rule.
