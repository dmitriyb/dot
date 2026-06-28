---
name: fix-epic
description: Address the reviewer's per-bead flags on a whole-epic PR — fix each flagged bead and the ripple into its dependents, on the same branch
disable-model-invocation: true
---

Fix the flagged beads on the epic PR in your bundle, **plus the ripple** into their dependents, on the same branch. Use `@~/.claude/skills/fix/SKILL.md` for the per-item fix methodology and `@~/.claude/skills/go-expert/SKILL.md` for Go.

## Preconditions (already done for you)

`start-epic <epic-id> --pr <n>` has run (the dca entrypoint runs it automatically). It has fetched `$HARNESS_DIR/pr.json`, checked out the epic PR branch, and rebuilt the per-bead spec contexts + `epic.json`. The previous review wrote `$HARNESS_DIR/result.json` (the flagged beads + blockers); flagged beads also carry the `review:changes` label. Beads are still **`open`** (you do not close them — review does, at the end).

## Workflow

1. Read `${DCA_RESULT_DIR:-$HARNESS_DIR}/result.json` → the flagged beads and their blockers. (Fallback: `br list --json | jq '.[]|select((.labels//[])|index("review:changes"))'`.)
2. For **each flagged bead**, in `epic.json` order:
   - read its blockers, its `beads/<NN-id>/spec-files.txt`, and `br show <bead-id>`;
   - fix the issues in **that bead's component** following the fix methodology (`@~/.claude/skills/fix/SKILL.md`) — address every blocker concretely, not superficially;
   - **handle the ripple**: if the fix changes an interface that later beads consumed, update those dependents too (their code is on the branch). Resolve any `TODO(bead:<id>)` markers that now apply.
   - commit with subject `"<bead-id>: fix review feedback"` (signed). Then clear the flag: `br label remove <bead-id> review:changes`.
3. Re-run the relevant tests (`go test ./... && go vet ./...`) so the whole branch builds + passes.
4. **Push once** — `git push`. portitor gates each commit (signed + role). Do **not** push to the default branch, do **not** close beads, keep commits signed.

The review phase re-runs against the updated branch. Report which beads you fixed and any ripple you touched.
