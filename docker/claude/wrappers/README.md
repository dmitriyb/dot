# Execution-skill preludes (`prelude`)

Deterministic, non-LLM preludes for the execution skills, run **outside** the
agent. Each lifts a skill's scriptable prelude (sync from origin, guard the bead,
resolve spec context, branch off the default, claim the bead, write a bundle) out
of the LLM. This saves the ~8–10 deterministic tool-calls per task and makes the
guards correct-by-construction.

These wrappers are **convenience, not trust**: the proxy ([portitor]) re-derives
every invariant from the pushed result and is the only thing that enforces. A
bypassed or buggy wrapper just means the proxy rejects later.

## Usage

```
prelude implement <bead-id> [--dry-run] [--repo DIR]
prelude cleanup   <bead-id> [--dry-run] [--repo DIR]
```

`--dry-run` performs all read-only steps (fetch, guards, spec resolution) and
prints the plan without creating a branch, claiming, or committing.

## What each prelude does

1. **Preflight** — clean working tree, a signing key is loaded (`ssh-add -l`),
   `git fetch origin`, and an idempotent beads rebuild (`br sync --import-only`).
2. **Guard** the bead via `br show <id> --json`:
   - `implement` rejects a `spex:cleanup` bead (dispatch to `cleanup`) and
     requires status `open`/`ready`.
   - `cleanup` requires the `spex:cleanup` label, status `open`/`ready`, and a
     `blocks:` predecessor that is already `closed`.
3. **Resolve spec context** from the `spex:<n>` label via `spex map context <n>`.
4. **Branch** off `origin/<default>`:
   - implement: `<bead-id>-<title-slug>`
   - cleanup: `cleanup/<predecessor-title-slug>`
5. **Claim** the bead (`br update <id> --status in_progress`) and commit the
   JSONL change as a **signed** commit (the role's key) on the feature branch.
6. **Bundle** — write `.harness/bundle.json` + `.harness/CONTEXT.md` (bead, spec
   file list, branch) for the agent, and git-exclude `.harness/`.

The agent then does only the LLM work: implementation/removal, tests, the
completion gate, and the PR body. It must not close the bead (review-only) or
push to the default branch — both re-checked by the proxy.

## Scope

`implement` and `cleanup` only — they need just `git`/`br`/`spex`, so they run
fully inside the autonomous agent container (which has no `gh` and no GitHub
credential). `review` and `fix` preludes are mostly GitHub reads, which are
fetched **proxy-side into the bundle**; they land with the proxy read-side in the
dca runner phase.

## Build / test

```
go build -o bin/prelude .   # baked onto PATH in the agent image
go test ./...
```

Tests use stubbed `br`/`spex` on PATH and an ephemeral SSH signing key, so they
need no real beads state or hardware key.

[portitor]: https://github.com/dmitriyb/portitor
