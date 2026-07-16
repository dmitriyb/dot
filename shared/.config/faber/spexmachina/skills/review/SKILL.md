---
name: review
description: Review a pull request for correctness, spec traceability, and test quality
---

Review the PR in your bundle. Use @~/.claude/skills/go-expert/SKILL.md for Go-specific review guidance.

## Preconditions (already done for you)

The **context** hook (`fetch-pr`) has run: it fetched the PR's review state via the portitor-mediated client (you have no `gh`) into `$FABER_BUNDLE_DIR/pr.json`, **checked you out onto the PR branch** so you review the PR's code, and recorded a coarse `MODE` (REVIEW / FOLLOWUP) in `$FABER_BUNDLE_DIR/bundle.env`.

## Context loading

1. The PR diff (you are on its branch) and `pr.json` (`.title`, `.body`, `.reviews[]`, `.comments[]`, `.commits[]`).
2. The linked bead: extract the bead ID from the PR body/commits (the claim commit subject is `<bead-id>: start implement …`), then `br show <bead-id>`.
3. The spec for the bead: `spex map context <record-id>` (from the bead's `spex:<n>` label) → read `arch_*.md`, `impl_*.md`, `test_*.md`, `flow_*.md`, `module.json`. No spec label → fall back to spec references in the bead/PR.

## Review flow

Iterative cycle `implement → [review → fix → review] → close`. The action depends on the `(mode, result)` pair.

### Step 1: Refine mode (from pr.json)

The bundle's `MODE` is coarse. Refine it:

- **No prior feedback** (no review-body with text, no inline comments) → `mode = REVIEW`.
- **Prior feedback exists and the author responded** → `mode = FOLLOWUP`.
- **Prior feedback exists but the author did NOT respond** → **STOP. Do nothing** (emit `changes`; see the result step).

"Responded" (NOT "fixed" — Step 2 verifies fixes): an inline comment is responded-to if a reply references its id; a review-body if a commit exists with `committedDate` after the review's `submittedAt`.

### Step 2: Evaluate → `CLEAN` or `ISSUES`

**If `mode = REVIEW`:** examine the diff against the bead + spec; every check must pass for CLEAN.

**Already-satisfied replacement:** if the diff is bead-state-only (+ optional skill/doc), verify against `origin/main` instead (delivering commit is an ancestor and satisfies the requirement, the spec delta is non-behavioral, `go build/vet/test` pass, the cross-bead scope guard holds). All → CLEAN.

1. **Spec traceability**: code maps to bead requirements; no unrelated changes.
2. **Spec hygiene** (blocker): the bead's spec leaves must match the shipped implementation. Stale prose (`impl_*` referencing removed methods; `test_*` with retired preconditions; output-shape mismatches; `arch_*` describing a contract the code doesn't honor) is a blocker. `spex validate` passing is NOT sufficient — read each leaf against the diff.
3. **Bead completion** (most important): re-read the bead line by line; every requirement must have code. Verbs literal (replaces/adds/removes). `TODO`/`FIXME`/`HACK`/shim/compat wrappers deferring the bead's own work are automatic rejections.
4. **Correctness**: error paths, edge cases, no leaks.
5. **Patterns**: idiomatic, follows conventions.
6. **Tests**: verify requirements (not implementation), failure cases covered.
7. **Integration tests**: if `test_*.md` defines scenarios, matching tests must exist; missing ones are a blocker.
8. **Cross-bead test scope** (blocker): tests in the diff must trace ONLY to this bead's `test_files`. A test covering another bead's test_section is a blocker — default to requiring removal.

**If `mode = FOLLOWUP`:** verify each prior feedback item against the **current files** (not the diff, not the reply). Replies/commit messages are not evidence. For each: read the original request, read the current file, confirm the fix is present AND correct AND introduces no new issues. CLEAN iff every item is fixed.

### Step 3: Act — one of four, no other paths

GitHub actions go through `portitor pr <action>` (no `gh`); bodies are read from stdin:

- **CLEAN + REVIEW** → post an LGTM summary, then close the bead. PR is ready to merge.
  `printf '%s' "LGTM — <summary>" | portitor pr review --pr <n> --event comment`
- **CLEAN + FOLLOWUP** → close the bead; do NOT post another review.
- **ISSUES + REVIEW** → post the review describing each blocker (reference `path:line`); do not close.
  `printf '%s' "<blockers>" | portitor pr review --pr <n> --event request-changes`
- **ISSUES + FOLLOWUP** → post what's still wrong per unfixed item; do not close.

> Use `--event comment` for own-account PRs (GitHub disallows approve/request-changes on your own PR); the **closed bead is the approval signal**.

#### Closing the bead (reviewer-signed)

```bash
br close <bead-id> --reason "Reviewed and approved in PR#<number>. All review feedback addressed."
br epic close-eligible
git add .beads/issues.jsonl
git commit -S -m "Close <bead-id>: <short title>"
git push        # portitor gates: the bead-close jsonl change must be reviewer-signed
```

Only `review` closes beads — the close commit MUST be signed by the **reviewer** key (portitor's role rule enforces it). Do NOT push to the default branch.

## Emit your result (required)

Last step — faber loops or merges on this verdict:

```bash
printf '{"verdict":"%s"}\n' "<approved|changes>" > "$FABER_RESULT_DIR/output.json"
```

`approved` iff you reached CLEAN and closed the bead; `changes` in every other case (issues posted, or the STOP case where the author hasn't responded).
