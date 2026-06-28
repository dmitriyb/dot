---
name: review-epic
description: Review a whole-epic PR commit-by-commit; flag issues per bead; close ALL beads in one batch only when the whole epic is clean
disable-model-invocation: true
---

Review the epic PR in your bundle **bead by bead** (one commit per bead), with the whole epic's context available. Use `@~/.claude/skills/review/SKILL.md` for the per-bead review checks and `@~/.claude/skills/go-expert/SKILL.md` for Go.

## Preconditions (already done for you)

`start-epic <epic-id> --pr <n>` has run (the dca entrypoint runs it automatically). It has:

- fetched the epic PR's state into `$HARNESS_DIR/pr.json` (proxy-side; you have no `gh`),
- checked out the epic PR branch (`BRANCH` in `bundle.env`),
- rebuilt the per-bead spec contexts: `$HARNESS_DIR/beads/<NN-id>/` + `epic.json` (the bead↔ordinal map).

The beads are still **`open`**. If no bundle exists, run `start-epic <epic-id> --pr <n>` first.

## The critical rule: close only at full-clean, in a batch

A bead's correctness can depend on whether its **dependents** could be built on it, so you must **not** close beads incrementally. Review every bead for feedback, but **close nothing** until the **entire epic is clean**. This defeats the bad-early-bead/reopen problem — a late-found early flaw is just another fix iteration; nothing was locked in.

## Workflow

1. Read `epic.json` (the ordered beads) and `epic-map.md`. For each bead, its commit on the branch has subject `"<bead-id>: …"`; map bead → commit via `git log`.
2. **Review each bead in order.** For `beads/<NN-id>/`: read its `spec-files.txt` (the bead's spec slice) and `br show <bead-id>`, then evaluate that bead's commit diff with the standard review checks (`@~/.claude/skills/review/SKILL.md` Step 2: spec traceability, spec hygiene, bead completion, correctness, tests, cross-bead test scope). Result per bead: **CLEAN** or **ISSUES**.
3. **Record results — never via status.** Write `${DCA_RESULT_DIR:-$HARNESS_DIR}/result.json` (the orchestrator reads it on the host):
   ```json
   {"pr": <n>, "epic": "<id>", "verdict": "clean|changes",
    "flagged": [{"bead": "<id>", "blockers": ["path:line — …", …]}],
    "closed": []}
   ```
   For each ISSUES bead also add the label: `br label add <bead-id> review:changes`.
4. **Branch on the aggregate verdict:**

   - **Any bead has ISSUES → `verdict: "changes"`.** Post one PR review describing the blockers per bead (reference `path:line`); do **not** close anything. The fix phase will address them.
     ```bash
     printf '%s' "<per-bead blockers>" | pr review --pr <n> --event request-changes
     ```
   - **Every bead CLEAN → `verdict: "clean"`.** Now **batch-close all the epic's beads** (reviewer-signed — the gate's role rule requires it), flip the epic, and post LGTM:
     ```bash
     for b in $(jq -r '.order[].id' "$HARNESS_DIR/epic.json"); do
       br close "$b" --reason "Reviewed and approved in epic PR #<n>."
     done
     br epic close-eligible
     git add .beads/issues.jsonl
     git commit -S -m "Close epic <id> beads: reviewed in PR #<n>"
     git push                     # portitor gates: bead-close jsonl must be reviewer-signed
     printf '%s' "LGTM — epic reviewed, all beads closed." | pr review --pr <n> --event comment
     ```
     Record the closed ids in `result.json.closed`.

> Use `--event comment` (not approve/request-changes) on your own-account PRs; the **closed beads are the approval signal**. Per-line inline comments aren't a portitor action yet — put blockers in the review body referencing `path:line`. Do **not** push to the default branch.

The orchestrator reads `result.json`: `changes` → run the fix phase then re-review; `clean` → the epic PR is ready to merge.
