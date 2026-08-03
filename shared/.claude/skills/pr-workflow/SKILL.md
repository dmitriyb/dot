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
2. **Code changes** implementing the spec, plus tests.
3. **PAUSE before committing.** Every commit is signed with a YubiKey touch, and
   the user may not be at the keyboard. Say the commit is ready and wait for an
   explicit go — never run `git commit` without it. This applies to *every* commit
   in the session.
4. **Commit**, then run an **independent review** of the change with a subagent
   (fresh context, adversarial — correctness, spec alignment, tests).
5. **Fix** anything the review surfaced.
6. **PAUSE → commit** the fixes (same YubiKey rule), then **push** the branch.
7. **Hand over a PR description**, interactively in the conversation:
   - a short, precise title;
   - one short paragraph: *why* the change is needed and *how* it is done in
     general.
   The user opens the PR themselves — never open a PR, never call `gh pr create`.

## Ground rules

- The pauses are the point: commit = hardware touch. Batch work so pauses are few
  and predictable (typically two: main change, review fixes).
- Review is by a subagent with no stake in the diff — not a self-check.
- If the repo's own conventions (CLAUDE.md, spec structure, release process)
  conflict with anything here, the repo wins; flag the conflict to the user.
