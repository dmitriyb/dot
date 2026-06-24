---
name: implement
description: Implement a beads task — write code, tests, and create a PR
disable-model-invocation: true
---

Implement the bead described in your bundle. Use @~/.claude/skills/go-expert/SKILL.md for Go-specific guidance.

## Preconditions (already done for you)

The deterministic prelude (`start-implement <bead-id>`) has run before this skill — the dca entrypoint runs it automatically; in an interactive session, run it yourself first. It has already:

- synced from `origin` and created your feature branch off `origin/<default>`,
- guarded the bead (status `open`/`ready`, not a `spex:cleanup` bead, signing key present),
- claimed the bead (`status in_progress`) with a **signed** commit on the branch,
- resolved the spec context and written a bundle to `$HARNESS_DIR` (default `${XDG_RUNTIME_DIR:-/tmp}/harness`):
  - `CONTEXT.md` — bead summary, branch, and the spec file list (this is your prompt),
  - `spec-files.txt` — the spec file paths to read,
  - `bundle.env` — `BEAD_ID`, `BRANCH`, `RECORD_ID`, … for tooling.

**Start by reading every file in `spec-files.txt`** (`arch_*`, `impl_*`, `test_*`, `flow_*`, `module.json`). That is your spec — do not go re-derive it. If `spec-files.txt` is empty, fall back to the spec references in the bead description.

If no bundle exists, the prelude has not been run — stop and run `start-implement <bead-id>` first.

## Already-satisfied replacement path

A doc-only edit to a component's `arch_*`/`impl_*` leaf still changes its hash, so the pipeline emits a replacement bead with zero code work. If the implementation and tests already exist on `origin/main` and satisfy the current spec, take this path instead of the TDD workflow. Verify first: the spec delta is non-behavioral (`git show <spec-commit> -- <arch_file>`) and `go build/vet/test` pass unchanged. Do not fabricate a diff; do not `br close` (review closes).

Then open a PR whose body explains why it should be closed: delivering commit, the non-behavioral spec delta, and verification run. Review re-checks and closes.

## Workflow (TDD)

1. Read the bead and spec fully. Understand acceptance criteria before writing code.
2. **Fix deferred breakage.** Search the codebase for `TODO(bead:<this-bead-id>)` markers left by other beads. Fix these first — they represent compilation breakage from upstream changes that was deferred to this bead.
3. **Write integration tests first.** Read the `test_*.md` spec files from your bundle. Write tests that cover every scenario defined there. These tests should compile but fail — they exercise behavior that does not exist yet. Run `go test ./...` to confirm they fail for the right reasons (missing functions, wrong output, etc. — not compilation errors).

   **Test-section scope guard**: the `test_files` in your bundle ARE the bead's test-section ownership boundary. Write test cases ONLY for scenarios described in those files. The same source test file in the codebase (regardless of language: `*_test.go`, `*_spec.rb`, `*.test.ts`, `test_*.py`, etc.) may legitimately host test cases owned by multiple beads — only write the ones whose scenarios trace to YOUR bead's `test_files`. If a test would cover a scenario from any other `test_*.md` (one not in your bundle), STOP — that test belongs to that test_section's bead. This is a separate axis from the file-ownership rule below: file-ownership says "don't edit files owned by another component"; test-section-ownership says "don't write tests for scenarios owned by another bead, even if they would naturally live in your component's test file."
4. **Write unit tests.** Based on the impl spec and architecture, write unit tests for internal functions and edge cases. These also fail initially.
5. **Write the implementation.** Write code that traces to requirements described in the bead. Only implement the single component this bead covers. Follow patterns in existing codebase. No unrelated changes.

   **Scope boundary**: Only modify logic and tests for the component this bead covers. If your changes cause compilation errors in files owned by a different component, comment out the broken code with `// TODO(bead:<other-bead-id>): fix after <your-bead-id> changed <what>`. Look up the correct bead ID from `.bead-map.json` for that component. Do NOT rewrite the other component's logic or tests — that work belongs to their bead.
6. **Run tests.** Run `go test ./...` and `go vet ./...`. All tests from steps 3-4 must now pass. If any test still fails, fix the implementation — do not weaken or delete the test.
7. **Completion gate** (see below). Do NOT proceed until every item passes.
8. Commit and push your feature branch. Commits must be signed; do NOT bypass signing with `--no-gpg-sign` or `-c commit.gpgsign=false`. Do NOT close the bead (review closes it) and do NOT push to the default branch.
9. Create a PR using `.github/pull_request_template.md`. Fill in the bead ID (`BEAD_ID` from `bundle.env`), spec references from the bead metadata, and changes summary.
10. Link the bead to the PR: `br update <bead-id> --external-ref "PR#<number>"`, then commit `.beads/issues.jsonl` and push so the bead state is tracked in git. Then check the box in the PR body: `gh pr edit <number> --body "$(gh pr view <number> --json body --jq '.body' | sed 's/- \[ \] Bead linked to PR/- [x] Bead linked to PR/')"`

## Completion Gate

Before committing, re-read the bead description and verify **every** claim is met. This is mandatory — do not skip it.

1. **Requirements satisfied**: Re-read the bead title and description line by line. For each stated requirement or behavior, identify the code that implements it. If you cannot point to concrete code for a requirement, it is not done.
2. **No deferred work**: Search your changes for `TODO`, `FIXME`, `HACK`, `WORKAROUND`, shim functions, and compatibility wrappers. If any of these exist for work that the bead is supposed to deliver, the implementation is incomplete. Either finish the work or stop and tell the user you cannot complete the bead as scoped.
3. **Verbs are true**: If the bead says "replaces", the old thing must be gone. If it says "adds", the new thing must exist and work. If it says "removes", the thing must not be present. Do not reinterpret the bead's language — take it literally.
4. **Tests cover requirements**: Each requirement from the bead must have at least one test that would fail if the requirement were not implemented. Tests that only assert happy-path output are insufficient if the bead specifies error behavior or edge cases.
