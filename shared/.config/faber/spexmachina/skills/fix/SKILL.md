---
name: fix
description: Fix review comments on a pull request
---

Fix the review feedback on the PR in your bundle: fix each item, commit and push, and reply to each item concisely ("Fixed"/"Addressed", or a fuller answer if it's a question). Reply to EACH item individually — do NOT post a single bulk summary. Use @~/.claude/skills/go-expert/SKILL.md for Go-specific guidance.

## Preconditions (already done for you)

The **context** hook (`fetch-pr`) has run: it fetched the PR's review feedback via the portitor-mediated client (no `gh`) into `$FABER_BUNDLE_DIR/pr.json` and **checked you out onto the PR branch**.

## Sources of feedback — read BOTH from `pr.json`

1. **Review bodies**: `.reviews[]` with `state` `COMMENTED`/`CHANGES_REQUESTED` and a non-empty `body` — top-level items that may have no inline comment.
2. **Inline comments**: `.comments[]` — line-level comments (each has `path`, `line`, `body`, `id`).

## Workflow

1. Read every actionable item from both sources.
2. Fix each in the code. Only touch what the feedback calls for. Commits must be signed (do NOT bypass signing); do NOT push to the default branch.
3. Commit and push the PR branch — re-pushing updates the same PR through portitor (the gate re-checks; the PR is updated, not duplicated).
4. Reply to each item via `portitor pr comment` (no `gh`), referencing the file/line it addresses:
   ```bash
   printf '%s' "Fixed — <what changed>" | portitor pr comment --pr <number>
   ```
   Reply per item. Do NOT post a single bulk comment.

## Emit your result (required)

Last step — faber records the fix outcome and re-enters review:

```bash
printf '{"status":"%s"}\n' "<short summary, e.g. 'addressed 3 review items'>" > "$FABER_RESULT_DIR/output.json"
```
