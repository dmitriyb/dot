---
name: implement
description: Implement a beads task — write code, tests, and the PR body
---

Implement the bead in `$FABER_BUNDLE_DIR/CONTEXT.md`. Use @~/.claude/skills/go-expert/SKILL.md for Go-specific guidance.

**Read CONTEXT.md, then every spec leaf it lists** (`arch_*` the contract, `test_*` the scenarios, `flow_*` the cross-component data shapes, `module.json` the module envelope). That is your spec — do not re-derive it. Beads carry empty descriptions by design: the spec leaves are the source of truth.

Your deliverables — everything else (commit, push, PR, bead linking, PR description) is finished deterministically by the box after you. The git history you see contains such commits and `portitor` calls from previous cycles: those were made by the box, never by the agent — do not imitate them. Your two deliverables:

1. **The edited working tree**: implementation + tests, left uncommitted.
2. **`$FABER_RESULT_DIR/pr-body.md`**: the PR description, from `.github/pull_request_template.md` — bead id, spec references, changes summary. Non-empty; body text only.

## Workflow (TDD)

1. Fix deferred breakage first: search for `TODO(bead:<this-bead-id>)` markers and resolve them.
2. Write integration tests from the `test_*.md` leaves; they must compile and fail for the right reasons. **Scope guard**: the `test_*` leaves CONTEXT.md lists are your ownership boundary — write only their scenarios; a shared `*_test.go` may host other beads' cases.
3. Write unit tests for internal functions and edge cases; they also fail initially.
4. **Write the implementation** — only the single component this bead covers, tracing to the spec. Follow existing patterns; no unrelated changes. If your change breaks a file owned by another component, comment the breakage out with `// TODO(bead:<other-bead-id>): fix after <your-bead-id> changed <what>` — never rewrite the other component. (Its owning bead: find the component in `module.json`, then `spex map get <hash>`.)
5. `go build ./... && go vet ./... && go test ./...` must pass. Fix the code, never weaken a test.

## Completion gate (mandatory before you finish)

1. Every stated requirement points to concrete code implementing it.
2. No deferred work: no `TODO`/`FIXME`/`HACK`/shims for this bead's OWN scope.
3. Verbs are literal: "replaces" → old gone; "adds" → new works; "removes" → absent.
4. Each requirement has a test that would fail if it were unimplemented.

## Special paths

- **Cleanup cycle** (CONTEXT.md says the bead's node was REMOVED): the work is deletion, not construction — follow CONTEXT.md, not the TDD workflow above. Remove the code and its tests, drop dead references, leave the build green. If something live still depends on it, that dependency contradicts the spec: file a drift report rather than forcing the removal.
- **Data-flow bead** (CONTEXT.md lists a `flow_*` leaf as the contract and no `test_*`): the scope guard inverts — updating the shared types and interfaces across every participant IS the job. Leave the tree compiling, mark per-component follow-up `TODO(bead:<component-bead-id>)` — the handoff those beads consume, not deferred work of your own — and take your gate as build + existing tests, since you have no test leaves.
- **Spec defect** (`spec/` is read-only to you): file a drift report `drifts/drift-<bead-id>.json` per `schema/drift.schema.json`. Non-blocking (the defect is in a neighbor and does not gate your task): keep your code, the report rides along. Blocking (your own contract is ambiguous or unimplementable): **discard your code changes** — they encode one side of a dispute nobody has adjudicated yet — keep ONLY the report, return the bead with `br update <bead-id> --status open`, and put the rationale in `pr-body.md`.
- **Already satisfied** (doc-only spec delta, the code is already on main): verify the delta is non-behavioral and that the gate passes unchanged; change nothing; write a `pr-body.md` naming the delivering commit and the verification run. Do not fabricate a diff.
