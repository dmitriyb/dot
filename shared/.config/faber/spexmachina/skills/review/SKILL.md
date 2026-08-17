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
3. The spec for the bead: `spex map context <bead-id>` → read `arch_*.md`, `test_*.md`, `flow_*.md`, `module.json`. There are no `impl_*.md` leaves — the arch leaf IS the contract. The bead id IS the key: `map context` folds the journal to the node itself. Do NOT pass the bead's `spex:` label — that is the create op's idempotency label, not a lookup key, and the journal is the sole source of linkage truth. A **cleanup** bead resolves to `{"removed": true, ...}` — a biography, not spec files; its contract is the retired leaf at `before_head` (`git show <before_head>:<path>`), and the work under review is deletion.

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
2. **Spec hygiene** (blocker): the bead's spec leaves must match the shipped implementation. Stale prose (`test_*` with retired preconditions; output-shape mismatches; `arch_*` describing a contract the code doesn't honor) is a blocker. `spex validate` passing is NOT sufficient — read each leaf against the diff.
3. **Bead completion** (most important): re-read the bead line by line; every requirement must have code. Verbs literal (replaces/adds/removes). `TODO`/`FIXME`/`HACK`/shim/compat wrappers deferring the bead's own work are automatic rejections.
4. **Correctness**: error paths, edge cases, no leaks.
5. **Patterns**: idiomatic, follows conventions.
6. **Tests**: verify requirements (not implementation), failure cases covered.
7. **Integration tests**: if `test_*.md` defines scenarios, matching tests must exist; missing ones are a blocker.
8. **Cross-bead test scope** (blocker): tests in the diff must trace ONLY to this bead's `test_files`. A test covering another bead's test_section is a blocker — default to requiring removal.

**If `mode = FOLLOWUP`:** verify each prior feedback item against the **current files** (not the diff, not the reply). Replies/commit messages are not evidence. For each: read the original request, read the current file, confirm the fix is present AND correct AND introduces no new issues. CLEAN iff every item is fixed.

### Step 3: Act — one of four, no other paths

You do NOT post the review yourself: write it to `$FABER_RESULT_DIR/review.json` and the **postlude** (`post-review`) submits it as a **comment-type** GitHub review — feedback only, never a GitHub approve/request-changes (a single PAT account can't cast those on its own PR). Approval is **not** an internal verdict: it is your **signed bead close** below (portitor gates the close to the reviewer role), which the merge gate's `bead-closed` predicate reads off the PR head. On an `approve` verdict the postlude also resolves the threads your prior comment-reviews raised.

```json
{"event": "approve" | "request-changes" | "comment",
 "body": "<markdown summary>",
 "comments": [{"path": "<file>", "line": <n>, "body": "<blocker, as an inline thread>"}, ...]}
```

**Keep `body` terse — a few lines, not an audit.** Its only readers are the fix agent (which needs the blockers) and a human glancing at the PR; neither wants a section-by-section pass. The substance of any blocker lives in `comments[]` (one inline thread per blocker at its `path:line`), NOT in the body. Never restate the spec, the diff, or every check you ran.

- **CLEAN + REVIEW** → `event: approve`, `body` = one line (verdict + a one-clause reason, e.g. "LGTM — Mul is `a*b`, traces to its arch/test leaves, tests pass"), no comments; then close the bead.
- **CLEAN + FOLLOWUP** → `event: approve`, one-line body; close the bead.
- **ISSUES + REVIEW** → `event: request-changes`, `body` = one line naming the blockers at a high level, one `comments[]` entry per blocker at its `path:line` (real threads the fix step answers); do not close.
- **ISSUES + FOLLOWUP** → `event: request-changes`, one line per still-unfixed item; do not close.

The STOP case (author never responded) writes `event: comment` with a one-line body naming the wait.

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

`approved` iff you reached CLEAN, wrote `event: approve` into review.json, and closed the bead; `changes` in every other case (issues written, or the STOP case where the author hasn't responded).

## Spec freeze and drift reports

- **Any diff touching `spec/` is an unconditional REQUEST_CHANGES**, whatever else the PR contains. Spec truth moves only in the authoring loop; the gate denies such pushes structurally, so a spec-touching diff reaching you means something slipped — reject and say why.
- **A PR carrying `drifts/drift-*.json` gets the report itself reviewed**: validate the shape against `schema/drift.schema.json`, then judge the substance — does the cited contradiction/hole actually exist in the named files? A drift-only PR (report + the bead's return to `open`, no code) is APPROVED when the claim is real and well-formed — and this is the one sanctioned exception to the approve⇔close contract: emit `event: approve` **without closing the bead**, since returning it to `open` is the PR's entire point (the merge gate sanctions this explicitly — its `bead-closed` predicate admits a PR that closed no bead when the PR is drift-only, meaning it touches nothing outside `drifts/` and `.beads/`); a report whose claim you can refute gets REQUEST_CHANGES with the refutation, exactly like wrong code.
- **A blocking-drift PR that still carries code is malformed** — REQUEST_CHANGES. The protocol requires the work be discarded, because the code encodes one side of a dispute nobody has adjudicated yet. Nothing strips it automatically — the box is trusted to follow the protocol — so catching it is your job, and the gate is the backstop: a PR that closes no bead *and* touches code satisfies neither branch of the predicate and cannot land.
