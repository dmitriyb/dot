# faber configs & tooling

Everything for running repos through the faber → portitor gate stack. This directory (stowed to `~/.config/faber`) holds one subdirectory per faber **project**; the driver scripts live in `shared/.local/bin` (stowed to `~/.local/bin`).

## Layout

```
SETUP.md                 host runbook — binaries, role keys, PAT, faber-stack up
base/                    the shared component library (images, skills, hooks)
spexmachina/             spexmachina development through the gate
old/                     retired projects and faber-e2e, kept for reference (not maintained)
<project>/stack.json     host-local instance manifest (gitignored; copy from stack.example.json)
```

Each project dir is a complete faber assembly (`orchestrator.yaml` + the component libraries); see its `README.md`. `stack.json` names the instance, the repo, the PAT **by reference** (a secret-store service and account, never the token), the egress allow-list and the committer emails.

## The scripts

- **`faber-stack`** (alias `fbs`) — the environment one project's boxes run against: `faber-stack up|down|status|prune <project>`. `up` checks every input (and refuses while boxes are running), writes the gate config from `policy.json`, `stack.json` and the role registry, runs `faber build`, starts the egress proxy, and runs `portitor deploy` for the gate. `down --volumes` also removes the gate's volumes and pin.
- **`secret-get`** — prints one secret from the host's backend; `portitor deploy`'s `token_command`.
- **`portitor-branch`** (alias `pbr`) — mirror-branch cleanup on a gate: `list | delete <branch> | clear`. Pre-rerun hygiene — portitor never deletes mirror branches itself.

## Related build contexts

The egress proxy builds from `~/.local/share/egress` (stowed from dot); the gate image is built by `portitor deploy`. No source checkout is needed.

## First-time host setup

The ordered runbook is [`SETUP.md`](SETUP.md).
