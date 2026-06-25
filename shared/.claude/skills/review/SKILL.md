---
name: review
description: Review a pull request for correctness, spec traceability, and test quality
disable-model-invocation: true
---

Review the PR in your bundle. Use @~/.claude/skills/go-expert/SKILL.md for Go-specific review guidance.

## Preconditions (already done for you)

`start-review <pr-number>` has run before this skill — the dca entrypoint runs it automatically; in an interactive session, run it yourself first. It has:

- fetched the PR's review state **proxy-side** (`portitor pr fetch`) into `$HARNESS_DIR/pr.json` (the agent has no `gh`),
- checked out the PR branch (`BRANCH` in `$HARNESS_DIR/bundle.env`) so you review the PR's code,
- computed a coarse `MODE` (REVIEW / FOLLOWUP) in `bundle.env`.

If no bundle exists, run `start-review <pr-number>` first.

## Context loading

1. The PR diff (you are on its branch) and `pr.json` (`.title`, `.body`, `.reviews[]`, `.comments[]`, `.commits[]`).
2. The linked bead: extract the bead ID from the PR body/commits (the claim commit subject is `<bead-id>: start implement …`), then `br show <bead-id>`.
3. Spec for the bead: `spex map context <record-id>` (from the bead's `spex:<n>` label) → read `arch_*.md`, `impl_*.md`, `test_*.md`, `flow_*.md`, `module.json`. If no spec label, fall back to spec references in the bead/PR description.

## Review flow

Iterative cycle `implement → [review → fix → review] → close`. The action depends on the `(mode, result)` pair.

### Step 1: Refine mode (from pr.json)

The bundle's `MODE` is coarse. Refine it:

- **No prior feedback** (no review-body with text, no inline comments) → `mode = REVIEW`.
- **Prior feedback exists and the author responded** → `mode = FOLLOWUP`.
- **Prior feedback exists but the author did NOT respond** → **STOP. Do nothing.** Tell the user.

"Responded" (NOT the same as "fixed" — Step 2 verifies fixes):
- inline comment (no `inReplyToId`) → responded if a reply references its id.
- review-body → responded if a commit exists with `committedDate` after the review's `submittedAt`.

### Step 2: Evaluate → `CLEAN` or `ISSUES`

**If `mode = REVIEW`:** examine the diff against the bead + spec; every check must pass for CLEAN.

**Already-satisfied replacement:** if the diff is bead-state-only (+ optional skill/doc), the diff-anchored checks don't apply — verify against `origin/main` instead (the delivering commit is an ancestor and satisfies the requirement, the spec delta is non-behavioral, `go build/vet/test` pass, the cross-bead scope guard holds). All four → CLEAN.

1. **Spec traceability**: code maps to bead requirements; no unrelated changes.
2. **Spec hygiene** (blocker): the bead's spec leaves (`arch_*`/`impl_*`/`test_*` from `spex map context`) must match the shipped implementation. Stale prose is a blocker. Look for: `impl_*` referencing removed methods/types; `test_*` scenarios with retired preconditions; output-shape mismatches; `arch_*` describing a contract the code doesn't honor. `spex validate` passing is NOT sufficient — read each leaf against the diff.
3. **Bead completion** (most important): re-read the bead line by line; every requirement must have corresponding code. Take verbs literally (replaces/adds/removes). `TODO`/`FIXME`/`HACK`/shim/compat wrappers that defer the bead's own work are automatic rejections.
4. **Correctness**: error paths, edge cases, no leaks.
5. **Patterns**: idiomatic, follows conventions.
6. **Tests**: verify requirements (not implementation), failure cases covered.
7. **Integration tests**: if `test_*.md` defines scenarios, the PR must include matching tests; missing ones are a blocker.
8. **Cross-bead test scope** (blocker): tests in the diff must trace ONLY to this bead's `test_files` (from `spex map context`). A test covering a scenario from another bead's test_section is a blocker — default to requiring its removal (ask the user before allowing it). Per-test-case boundary, independent of file ownership.

**If `mode = FOLLOWUP`:** verify each prior feedback item against the **current files** (not the diff, not the reply). Replies/commit messages are not evidence. For each item: read the original request, read the current file, confirm the fix is present AND correct AND introduces no new issues. CLEAN iff every item is fixed.

### Step 3: Act — one of four, no other paths

GitHub actions go through portitor (you have **no gh**); bodies are read from stdin:

- **CLEAN + REVIEW** → post an LGTM summary, then close the bead. PR is ready to merge.
  `printf '%s' "LGTM — <summary>" | portitor pr review --pr <n> --event comment`
- **CLEAN + FOLLOWUP** → close the bead; do NOT post another review.
- **ISSUES + REVIEW** → post the review describing each blocker; do not close.
  `printf '%s' "<blockers, referencing path:line>" | portitor pr review --pr <n> --event request-changes`
- **ISSUES + FOLLOWUP** → post what's still wrong for each unfixed item; do not close.

> Use `--event comment` for your own-account PRs (GitHub disallows approve/request-changes on your own PR); the **closed bead is the approval signal**. Inline per-line comments aren't yet a portitor action — describe blockers in the review body referencing `path:line` until `portitor pr review` gains an inline payload.

#### Closing the bead (reviewer-signed)

```bash
br close <bead-id> --reason "Reviewed and approved in PR#<number>. All review feedback addressed."
br epic close-eligible
git add .beads/issues.jsonl
git commit -S -m "Close <bead-id>: <short title>

All PR #<number> review feedback addressed."
git push        # portitor gates: the bead-close jsonl change must be reviewer-signed
```

Only `review` closes beads — the close commit must be signed by the **reviewer** key (portitor's role rule enforces it). Do NOT push to the default branch.
