---
name: fix
description: Fix review comments on a pull request
---

Fix the feedback on the PR described in `$FABER_BUNDLE_DIR/CONTEXT.md`. Use @~/.claude/skills/go-expert/SKILL.md for Go-specific guidance.

CONTEXT.md names the bead, its spec leaves and the unresolved threads; `threads.json` and `pr.json` hold the full detail, and you are already on the PR branch. Your two deliverables — the box commits, pushes and posts everything after you, so the commits and `portitor` calls in git history are its work, not a pattern to imitate:

1. **The edited working tree**: the fixes, left uncommitted.
2. **`$FABER_RESULT_DIR/answers.json`**: one reply per thread, plus an optional PR-level comment for review-body items that have no thread.
   ```json
   {"replies": [{"thread": "<id from threads.json>", "body": "Addressed — <what changed>"}],
    "comment": "<optional markdown, for feedback with no thread to answer into>"}
   ```
   Every thread gets exactly one reply, and each is one of:
   - **`Addressed — <what changed>`** — 1–2 sentences.
   - **`Declined — <why>`** — up to one paragraph. The reviewer re-judges it; use this when you believe the review is wrong, never to defer work.

   Nothing else, and never one bulk summary. Every `thread` id must come from `threads.json`.

## Which job is this? CONTEXT.md tells you

**Review feedback** (the usual case) — unresolved threads are listed.

**A failed land attempt** — CONTEXT.md carries a section headed *"CI failure from the last land attempt"*. The merge step already read the failing job's logs; trust its diagnosis as your starting point rather than re-deriving it. There may be no threads at all, which is legal: write `answers.json` with `"replies": []`. The bead has already been reopened for you — do not touch its status; a reviewer must approve again before this can land.

**A merge conflict** — CONTEXT.md carries a section headed *"Merge conflict with `<base>`"* and lists the unmerged paths. The base branch has already been merged in for you and it conflicted; resolving it is yours. Say plainly in your `comment` what you chose and why: resolving a conflict means writing code that existed in neither branch, and the reviewer who follows is seeing it for the first time. Leave nothing unmerged — the box refuses to commit a tree that still has conflict markers.

## Sources of feedback — read ALL THREE

1. **Unresolved threads** (`threads.json`) — the primary work list; every entry gets a fix AND a reply.
2. **Review bodies** — `pr.json` `.reviews[]` with state `COMMENTED`/`CHANGES_REQUESTED` and a non-empty body: items that may have no thread.
3. **Loose comments** — `pr.json` `.comments[]`.

## How to fix

Fix only what the feedback calls for. **Verify each fix against the bead's spec leaves, not only against the reviewer's wording**: the leaf is the arbiter. Never "fix" CI by weakening what checks it: deleting or loosening a test, or touching the spec gate's own tooling, is a defect, not a fix.

- **Data-flow bead** (CONTEXT.md gives a `flow_*` leaf as the contract and no `test_*` leaves): the feedback may reach into any participant, and that is in scope. Its `TODO(bead:<component-bead-id>)` markers are the handoff those beads consume: feedback about them concerns their accuracy, never their existence.
- **Cleanup bead** (CONTEXT.md says the node was REMOVED): the work is deletion, so feedback resolves to more removal, not new code.

## When the spec is what is wrong

If the review asks you to justify a decision the spec does not license — or you find the defect yourself — the answer is a drift report, not a better-argued guess. The protocol is in @~/.claude/skills/implement/SKILL.md and applies here unchanged, with one difference: a blocking report updates the SAME PR you were fixing, so there is no new PR to open. Put the rationale in your `comment`.
