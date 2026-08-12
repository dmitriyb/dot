---
name: implement
description: Implement a beads task — write code, tests, and open a PR
---

Implement the bead described in your bundle. Use @~/.claude/skills/go-expert/SKILL.md for Go-specific guidance.

## Preconditions (already done for you)

The box's deterministic hooks have run before this skill — you never run them yourself:

- the **context** hook resolved the bead's spec and wrote your prompt to `$FABER_BUNDLE_DIR/CONTEXT.md` and the spec file list to `$FABER_BUNDLE_DIR/spec-files.txt`,
- the **prelude** hook created your feature branch off `origin/<default>`, guarded the bead (status `open`/`ready`, not `spex:cleanup`), and claimed it (`status in_progress`) with a **signed** commit on the branch,
- `$FABER_BUNDLE_DIR/bundle.env` carries `BEAD_ID`, `BRANCH`, `BASE`, `RECORD_ID`; these are also in your environment.

**Start by reading `$FABER_BUNDLE_DIR/CONTEXT.md`, then every file in `$FABER_BUNDLE_DIR/spec-files.txt`** (`arch_*`, `test_*`, `flow_*`, `module.json` — there are no `impl_*` leaves; the arch leaf is the contract). That is your spec — do not re-derive it. Beads carry empty descriptions by design; the spec leaves are the source of truth. If `spec-files.txt` is empty, fall back to the spec references in the bead.

## Spec defects: the drift protocol

`spec/` is read-only for you — the gate denies any push touching it, no exceptions. If you find a spec defect while working (a contradiction, an undecided case, a claim your dependency's leaf never promises), you file a **drift report**, never a spec edit:

- Write `drifts/drift-<bead-id>.json` per `schema/drift.schema.json`: `bead`, `node` (the defective node's identity hash), `files`, `claim` (the defective statement, located), `authoritative_source`, `evidence`, `blocking`, optional `proposed_fix`.
- **`blocking: false`** — the defect is in a neighbor and does not gate your own task: commit the report alongside your code in the same branch/PR and continue normally. It is triaged after the epic.
- **`blocking: true`** — the defect is in YOUR bead's own contract (its leaf, its `implements` chain, a `uses` seam) and makes the task ambiguous or unimplementable: **discard your code changes**, commit ONLY the drift report **plus the bead's return to `open`** (undo the claim: `br update <bead-id> --status open`, same signed commit), and push. Your code encodes one side of a dispute nobody has adjudicated yet, so it must not land: the merge gate **refuses** a PR that closes no bead and still touches code, so a PR you leave misshapen costs the whole cycle. The gate auto-opens the PR; put the report's rationale in `pr-body.md` so the postlude sets it as the PR description. Emit your normal output (`done:false` on an epic cycle) — the review chain validates your claim, the merge lands it on main, and the next cycle halts the epic on it. Nothing fails; the authoring loop takes over.

## Already-satisfied replacement path

A doc-only edit to a component's `arch_*` leaf still changes its hash, so the pipeline emits a replacement bead with zero code work. If the implementation and tests already exist on `origin/main` and satisfy the current spec, take this path instead of the TDD workflow. Verify first: the spec delta is non-behavioral (`git show <spec-commit> -- <arch_file>`) and `go build/vet/test` pass unchanged. Do not fabricate a diff; do not close the bead (review closes). Open a PR whose body explains why it should be closed: the delivering commit, the non-behavioral spec delta, and the verification run.

## Workflow (TDD)

1. Read the bead and spec fully. Understand acceptance criteria before writing code.
2. **Fix deferred breakage.** Search for `TODO(bead:<this-bead-id>)` markers left by other beads and fix them first — they are deferred compilation breakage from upstream changes.
3. **Write integration tests first** from the `test_*.md` leaves. They should compile but fail for the right reasons (missing behavior, not compile errors). Run `go test ./...` to confirm.
   - **Test-section scope guard**: the `test_files` in your bundle ARE your test-section ownership boundary. Write test cases ONLY for scenarios in those files. A shared `*_test.go` may host cases owned by several beads — write only yours. If a test would cover another `test_*.md`'s scenario, STOP: it belongs to that bead.
4. **Write unit tests** for internal functions and edge cases from the impl spec. They also fail initially.
5. **Write the implementation** — only the single component this bead covers, tracing to the spec. Follow existing patterns; no unrelated changes.
   - **Scope boundary**: only modify this component's logic/tests. If your change breaks compilation in a file owned by another component, comment it out with `// TODO(bead:<other-bead-id>): fix after <your-bead-id> changed <what>` (look up the owner via its `spex:<spec_node_id>` label: `spex map get <hash>`). Do NOT rewrite the other component.
6. **Run tests.** `go test ./...` and `go vet ./...` must pass. Fix the implementation, never weaken a test.
7. **Completion gate** (below). Do NOT proceed until every item passes.
8. Commit and push your feature branch. Commits must be signed; do NOT bypass signing (`--no-gpg-sign`, `-c commit.gpgsign=false`). Do NOT close the bead and do NOT push to the default branch. **The gate auto-opens the PR on an accepted push** — read the PR number from the push output (the `remote: portitor: PR #<n> <url>` line; a re-push reports the existing PR).
9. Build the PR body from `.github/pull_request_template.md` (fill in the bead ID `$BEAD_ID`, spec references, and a changes summary) and write it to `$FABER_RESULT_DIR/pr-body.md`. Do NOT post it yourself — the **post-implement** postlude sets it as the PR **description** via `portitor pr describe` (the box has no `gh`). The gate's auto-open already left a safe default description from your commit messages; this overwrites it with the real summary. Write a non-empty body (an empty file is refused).
10. Link the bead to the PR and commit it so the state is tracked in git:
    `br update <bead-id> --external-ref "PR#<number>"` then `git add .beads/issues.jsonl && git commit -S -m "<bead>: link PR#<number>" && git push`.

## Completion Gate

Before committing, re-read the bead and verify **every** claim is met. Mandatory.

1. **Requirements satisfied**: for each stated requirement, point to the code that implements it. No concrete code → not done.
2. **No deferred work**: search your changes for `TODO`/`FIXME`/`HACK`/`WORKAROUND`/shims/compat wrappers that defer the bead's OWN work. Any → incomplete: finish it or stop and say you cannot complete the bead as scoped.
3. **Verbs are true**: "replaces" → the old thing is gone; "adds" → the new thing exists and works; "removes" → it is not present. Take the bead literally.
4. **Tests cover requirements**: each requirement has at least one test that fails if it were unimplemented. Happy-path-only assertions are insufficient when the bead specifies error/edge behavior.

## Emit your result (required)

Last step, after the PR exists — faber scores the step from this file.

Single-bead run (your inputs carry a bead id):

```bash
printf '{"branch":"%s","pr":%s}\n' "$BRANCH" "<pr-number>" > "$FABER_RESULT_DIR/output.json"
```

Epic cycle (your inputs carry an epic id — CONTEXT.md says so):

```bash
printf '{"done":false,"branch":"%s","pr":%s}\n' "$BRANCH" "<pr-number>" > "$FABER_RESULT_DIR/output.json"
```

Done-cycle (CONTEXT.md says no ready bead remains, or dictates the blocking-drift halt sentinel — you did no work; emit exactly what CONTEXT.md shows):

```bash
printf '{"done":true}\n' > "$FABER_RESULT_DIR/output.json"
```

`branch` is `$BRANCH` from your environment; `pr` is the integer PR number the gate auto-opened for your push (step 8).
