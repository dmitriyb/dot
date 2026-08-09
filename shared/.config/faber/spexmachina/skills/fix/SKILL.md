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

## Spec defects: the drift protocol

Applies here exactly as in the implement skill:

`spec/` is read-only for you — the gate denies any push touching it, no exceptions. If you find a spec defect while working (a contradiction, an undecided case, a claim your dependency's leaf never promises), you file a **drift report**, never a spec edit:

- Write `drifts/drift-<bead-id>.json` per `schema/drift.schema.json`: `bead`, `node` (the defective node's identity hash), `files`, `claim` (the defective statement, located), `authoritative_source`, `evidence`, `blocking`, optional `proposed_fix`.
- **`blocking: false`** — the defect is in a neighbor and does not gate your own task: commit the report alongside your code in the same branch/PR and continue normally. It is triaged after the epic.
- **`blocking: true`** — the defect is in YOUR bead's own contract (its leaf, its `implements` chain, a `uses` seam) and makes the task ambiguous or unimplementable: discard your fix changes, commit ONLY the drift report **plus the bead's return to `open`** (undo the claim: `br update <bead-id> --status open`, same signed commit), and push — this updates the SAME PR you were fixing; there is no new PR to open. Emit your normal `status` output. The review chain re-examines the PR, now carrying your claim; the merge lands it on main, and the next cycle halts the epic. Nothing fails; the authoring loop takes over.
