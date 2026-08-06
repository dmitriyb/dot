---
name: pr-workflow
description: "Manual invocation only — the user's PR workflow for spec-carrying repos (faber, portitor, …). Never load on your own; the user invokes /pr-workflow when a session follows this workflow."
---

# PR Workflow — spec-carrying repos

The user's regular workflow for repos that carry a `spec/` directory and develop
via GitHub PRs (faber, portitor, and similar). Not for dot: dot is a non-PR repo
with no spec — these instructions don't apply there.

## The sequence

1. **Spec first.** Change the relevant `spec/` documents before touching code; the
   code follows the spec, never the other way around.
2. **Code + tests** implementing the spec.
3. **Independent review — before committing** (so no YubiKey touch is ever spent on
   unreviewed work). Hand the whole diff to a **fresh-context subagent** with no stake
   in it — any capable model; if the usual reviewer is rate-limited, substitute, don't
   block. It must:
   - read the **entire** diff, **including the test files**, not just production code;
   - check correctness + edge cases, **spec alignment** (the leaf matches the code and
     sits in the right module), and **test quality** — assertions strong and
     non-tautological, and crucially *would the tests fail if the change were reverted*
     (a test that still passes with the change removed proves nothing);
   - return findings ranked blocker / should-fix / nit, each with file:line + a concrete
     failure scenario, and a clear "safe to commit / needs fixes" verdict.
   Its independence is the point — never a self-check by the author context.
4. **Fix** what the review surfaced, folding it into the same change.
5. **PAUSE → commit.** Every commit is a YubiKey touch and the user may be away: say the
   commit is ready and wait for an explicit go — never `git commit` without it. Then
   **push** the branch. (A second review→fix→commit round is fine if fixes were large.)
6. **Hand over a PR description**, interactively: a short precise title, and one short
   paragraph — *why* the change is needed and *how* it's done. The user opens the PR
   themselves — never open a PR, never call `gh pr create`.

## Ground rules

- The touch is the point: commit = hardware touch. Batch work so pauses are few and
  predictable — review-before-commit means the common case is a single commit.
- The review is a fresh-context subagent with no stake in the diff, scrutinizing the
  tests as hard as the code — not a self-check, and not tied to any one model.
- If the repo's own conventions (CLAUDE.md, spec structure, release process) conflict
  with anything here, the repo wins; flag the conflict to the user.
