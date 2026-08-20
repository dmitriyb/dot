---
name: implement
description: Implement a beads task — write code, tests, and the PR body
---

Implement the bead in `$FABER_BUNDLE_DIR/CONTEXT.md`. Use @~/.claude/skills/go-expert/SKILL.md for Go-specific guidance.

**Read CONTEXT.md, then every file in `$FABER_BUNDLE_DIR/spec-files.txt`** (`arch_*` is the contract, `test_*` the scenarios). That is your spec — do not re-derive it. If `spec-files.txt` is empty, follow the spec references in the bead.

Your deliverables — everything else (commit, push, PR, bead linking, PR description) is finished deterministically by the box after you. The git history you see contains such commits and `portitor` calls from previous cycles: those were made by the box, never by the agent — do not imitate them. Your two deliverables:

1. **The edited working tree**: implementation + tests, left uncommitted.
2. **`$FABER_RESULT_DIR/pr-body.md`**: the PR description, from `.github/pull_request_template.md` — bead id, spec references, changes summary. Non-empty; body text only.

## Workflow (TDD)

1. Fix deferred breakage first: search for `TODO(bead:<this-bead-id>)` markers and resolve them.
2. Write integration tests from the `test_*.md` leaves; they must compile and fail for the right reasons. **Scope guard**: your bundle's `test_files` are your ownership boundary — write only their scenarios; a shared `*_test.go` may host other beads' cases.
3. Write unit tests for internal functions and edge cases; they also fail initially.
4. **Write the implementation** — only the single component this bead covers, tracing to the spec. Follow existing patterns; no unrelated changes. If your change breaks a file owned by another component, comment the breakage out with `// TODO(bead:<other-bead-id>): fix after <your-bead-id> changed <what>` — never rewrite the other component.
5. `go build ./... && go vet ./... && go test ./...` must pass. Fix the code, never weaken a test.

## Completion gate (mandatory before you finish)

1. Every stated requirement points to concrete code implementing it.
2. No deferred work: no `TODO`/`FIXME`/`HACK`/shims for this bead's OWN scope.
3. Verbs are literal: "replaces" → old gone; "adds" → new works; "removes" → absent.
4. Each requirement has a test that would fail if it were unimplemented.

## Special paths

- **Spec defect** (`spec/` is read-only; the gate rejects spec edits): file a drift report `drifts/drift-<bead-id>.json` per `schema/drift.schema.json`. Non-blocking (defect in a neighbor): keep your code, the report rides along. Blocking (your own contract is ambiguous/unimplementable): discard your code changes, keep ONLY the report, return the bead with `br update <bead-id> --status open`, and put the rationale in `pr-body.md`.
- **Already satisfied** (doc-only spec delta, code already on main): verify the delta is non-behavioral and the gate passes unchanged; change nothing; write a `pr-body.md` explaining the delivering commit and the verification run.
