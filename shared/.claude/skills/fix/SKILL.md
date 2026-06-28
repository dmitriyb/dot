---
name: fix
description: Fix review comments on a pull request
disable-model-invocation: true
---

Fix the review feedback on the PR in your bundle, fix each item, commit and push, and reply to each item concisely ("Fixed"/"Addressed", or a fuller answer if it's a question). Reply to EACH item individually — do NOT post a single bulk summary.

## Preconditions (already done for you)

`start-fix <pr-number>` has run before this skill — the dca entrypoint runs it automatically; in an interactive session, run it yourself first. It has:

- fetched the PR's review feedback (`pr fetch` → portitor in dca, gh in dcp) into `$HARNESS_DIR/pr.json`,
- checked out the PR branch (`BRANCH` in `$HARNESS_DIR/bundle.env`).

If no bundle exists, run `start-fix <pr-number>` first.

## Sources of feedback — read BOTH from `pr.json`

1. **Review bodies**: `.reviews[]` with `state` `COMMENTED`/`CHANGES_REQUESTED` and a non-empty `body` — top-level items that may not have inline comments.
2. **Inline comments**: `.comments[]` — line-level comments on specific code (each has `path`, `line`, `body`, `id`).

## Workflow

1. Read every actionable item from both sources.
2. Fix each in the code. Only touch what the feedback calls for. Commits must be signed (do NOT bypass signing); do NOT push to the default branch.
3. Commit and push the PR branch — re-pushing updates the same PR through portitor (the gate re-checks; the PR is updated, not duplicated).
4. Reply to each item with the backend-agnostic wrapper (`pr` → portitor in dca, gh in dcp):
   ```bash
   printf '%s' "Fixed — <what changed>" | pr comment --pr <number>
   ```
   Reply per item, referencing the file/line it addresses. Do NOT post a single bulk comment.

> Note: replying *inside* a specific inline thread is not yet a portitor action — post per-item top-level comments referencing `path:line` until `pr review` gains inline payloads.
