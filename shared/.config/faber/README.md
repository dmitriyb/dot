# faber configs & tooling

Everything for running repos through the faber → portitor gate stack. This directory (stowed to `~/.config/faber`) holds one subdirectory per faber **project**; the day-to-day driver scripts live in `shared/.local/bin` (stowed to `~/.local/bin`).

## Layout

```
SETUP.md                 generic host runbook — one-time provisioning (binaries, role keys, PAT)
spexmachina/             the real project: spexmachina development through the gate
faber-stack-service/     the acceptance playground — same chain on a disposable repo
<project>/stack.json     per-instance host-local manifest (gitignored; copy from stack.example.json)
```

Each project dir is a complete faber assembly (`orchestrator.yaml` + the five component libraries) — see the per-project `README.md` for what it runs and why. `stack.json` carries the instance identity and PAT **by reference** (a keychain service name, never the token), plus the converged `--allow`/`--commit-email` set.

## The scripts

- **`faber-stack`** — stands up one gate instance per repo: `role-keys --json | faber-stack up --instance <name> --slug <owner/repo> --pat <svc> --project <dir> [--build]`. One `--instance` knob derives every object name (network `<name>-net`, egress `<name>-egress`, gate `portitor-<name>`, volume `<name>-repos`). Idempotent; `--build` folds `faber validate` + `faber build` in. Verbs: `up | down | status | restart`.
- **`faber-epic`** — the one-command epic runner: `faber-epic <project> <epic-id>`. Reads `<project>/stack.json`, converges the gate via `faber-stack up`, then runs `faber run epic` with an absolute config path. Extra `faber-stack up` flags pass through after `--`.
- **`faber-e2e`** — the playground scenario driver against `faber-stack-service`: `reset | run | assert | full`. `run`/`full` cost real agent usage; `assert` checks merged PRs, closed beads, verified commits, and resolved threads.
- **`portitor-branch`** (alias `pbr`) — mirror-branch cleanup on a gate instance: `list | delete <branch> | clear`. Pre-rerun hygiene — portitor never deletes mirror branches itself.

## Related build contexts

The gate image and egress proxy build from dot's own contexts, stowed to `~/.local/share/portitor` and `~/.local/share/egress` — `faber-stack` builds them on demand; no source checkout is needed.

## First-time host setup

Provisioning a fresh host (verified release binaries, YubiKey role keys, role registry, scoped PAT, macOS quirks) is the ordered runbook in [`SETUP.md`](SETUP.md).
