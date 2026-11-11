---
name: merge
description: Triage a PR that could not be landed automatically, and decide between routing it to a fixer or halting the run
---

You run only when the PR could not land. **Read `CONTEXT.md`** — it names the blocker and the check states.

Do not judge whether the code is correct: a reviewer already approved it. Report what CI said; do not read the spec to form a second opinion.

## Your only decision

**Can something in this repository fix it?**

**Yes → write `merge.json`** with your diagnosis. Anything a change to the repo's own code resolves: a failing test, a compile or vet error, a spec-gate violation, a conflict with the base, a stale base.

**No → write `halt.json`.** Only when no commit to this repo could help:

- **Actions is degraded** — jobs stuck or queued indefinitely, the attempt cap spent, `rerun` refused.
- **The remedy is in a frozen path** — `.github/**`, `spec/**`, `.beads/**`; content rules deny those to boxes.
- **The remedy is not in the repo** — a missing secret, exhausted Actions minutes, an external service down.

A spec-gate violation is not a halt: the code contradicts the spec, which is a fixer's job.

## Investigating

**`ci_red`** — read the failing job's logs. The fixer uses your conclusion instead of re-reading them, so say what broke and where.

```bash
portitor pr logs --pr "$FABER_INPUT_PR"
```

**`stuck`** — a hung job never failed, so it has no logs. Judge from the check states in `CONTEXT.md`: elapsed against budget, and how many re-runs were spent.

## Emit exactly one

`$FABER_RESULT_DIR/merge.json` — the diagnosis is the only field; the box supplies the rest.

```json
{"diagnosis": "`test` fails at `internal/foo/bar_test.go:42` — TestParse expects the trailing newline stripped, but ParseHeader preserves it after this PR's change."}
```

`$FABER_RESULT_DIR/halt.json` — writing it ends the step:

```json
{"reason": "actions_degraded",
 "detail": "spec-gate queued 12m across 3 re-run attempts without starting. Nothing in this repo will change that."}
```

`reason` is a stable machine word (`actions_degraded`, `frozen_path`, `not_in_repo`); `detail` is for the person who has to look at it.

Write one file, never both, and never `output.json`.
