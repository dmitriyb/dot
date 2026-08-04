---
name: fix
description: Fix review comments on a pull request
---

Fix the review feedback on the PR in your bundle: fix each item, commit and push, and write your per-thread answers into `answers.json` (the postlude posts them deterministically — you never post replies yourself). Answer EACH thread individually — do NOT write a single bulk summary. Use @~/.claude/skills/go-expert/SKILL.md for Go-specific guidance.

## Preconditions (already done for you)

The **context** hook (`fetch-pr`) has run: it fetched the PR's review feedback via the portitor-mediated client (no `gh`) into `$FABER_BUNDLE_DIR/pr.json`, wrote the **unresolved review threads** to `$FABER_BUNDLE_DIR/threads.json` (each with `id`, `path`, `line`, and its comment chain — also rendered in CONTEXT.md), and **checked you out onto the PR branch**. After you finish, the **postlude** hook (`post-answers`) posts your answers through the gate — and fails the step loudly if you addressed threads without writing them.

## Sources of feedback — read ALL THREE

1. **Unresolved threads**: `threads.json` — the primary work list; every entry must be fixed AND answered.
2. **Review bodies**: `pr.json` `.reviews[]` with `state` `COMMENTED`/`CHANGES_REQUESTED` and a non-empty `body` — top-level items that may have no thread.
3. **Loose comments**: `pr.json` `.comments[]`.

## Workflow

1. Read every actionable item from all sources.
2. Fix each in the code. Only touch what the feedback calls for. Commits must be signed (do NOT bypass signing); do NOT push to the default branch.
3. Commit and push the PR branch — re-pushing updates the same PR through portitor (the gate re-checks; the PR is updated, not duplicated).
4. Write your answers — one per thread from `threads.json`, referencing what changed (or a fuller answer if the thread is a question) — to:
   ```bash
   $FABER_RESULT_DIR/answers.json
   {"replies": [{"thread": "<id from threads.json>", "body": "Fixed — <what changed>"}, ...]}
   ```
   Every `thread` id MUST come from `threads.json`; every thread there SHOULD get a reply. Do NOT call `portitor pr reply`/`comment` for these — the postlude posts them and verifies the contract. For top-level (non-thread) review-body items, a `portitor pr comment` is still yours to post.

## Emit your result (required)

Last step — faber records the fix outcome and re-enters review:

```bash
printf '{"status":"%s"}\n' "<short summary, e.g. 'addressed 3 review items'>" > "$FABER_RESULT_DIR/output.json"
```
