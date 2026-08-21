---
name: review
description: Review a pull request for correctness, spec traceability, and test quality
---

Review the PR described in `$FABER_BUNDLE_DIR/CONTEXT.md`. Use @~/.claude/skills/go-expert/SKILL.md for Go-specific review guidance.

CONTEXT.md gives you the bead, its spec leaves and the **mode**; `pr.json` holds the full PR state, and you are already on the PR branch. Your one deliverable is `$FABER_RESULT_DIR/review.json`. The box posts it, closes the bead on an approval, and emits the step's verdict — the closes and pushes you see in git history came from the box on previous cycles, never from an agent, so do not imitate them.

```json
{"event": "approve" | "request-changes" | "comment",
 "body": "<markdown summary>",
 "comments": [{"path": "<file>", "line": <n>, "body": "<blocker, as an inline thread>"}, ...]}
```

**Keep `body` terse — a few lines, not an audit.** Its only readers are the fix agent, which needs the blockers, and a human glancing at the PR. Each blocker's substance belongs in `comments[]` as one inline thread at its `path:line`, not in the body. Never restate the spec, the diff, or the checks you ran.

## Mode

- **REVIEW** — no prior feedback. Judge the diff against the criteria below.
- **FOLLOWUP** — verify every prior feedback item against the **current files**. Replies and commit messages are not evidence: read the original request, read the file, confirm the fix is present, correct, and introduced nothing new. Approve only if every item holds.
- **WAIT** — there is prior feedback and nothing has moved since. Do not re-review: write `event: comment` with a one-line body naming what is being waited on.

## What must hold to approve

1. **Bead completion**, the one that matters most: re-read the bead line by line; every requirement has concrete code. Verbs are literal — "replaces" means the old thing is gone.
2. **Spec traceability**: the code maps to the bead's requirements, and nothing unrelated rides along.
3. **Licence**: every behavioural decision in the diff is licensed by a statement in the spec. Code that settles a question the leaves leave open — or contradict each other on — is drift, not the implementer's call. Request a drift report instead of accepting the guess. This is the only place a silently-papered-over spec defect gets caught.
4. **Spec hygiene** (blocker): the bead's leaves match what shipped. Stale prose — `test_*` carrying retired preconditions, output-shape mismatches, an `arch_*` describing a contract the code does not honour — is a blocker. `spex validate` passing is not sufficient; read each leaf against the diff.
5. **No deferred work**: `TODO`/`FIXME`/`HACK`/shims/compat wrappers deferring this bead's OWN work are automatic rejections.
6. **Tests**: every scenario in the `test_*` leaves has a matching test, tests verify requirements rather than implementation, and failure cases are covered. A missing scenario is a blocker.
7. **Cross-bead test scope** (blocker): the tests in the diff trace ONLY to this bead's test leaves. A test covering another bead's `test_section` belongs to that bead — default to requiring its removal.
8. **Correctness and patterns**: error paths, edge cases, leaks; idiomatic Go, consistent with the surrounding code.

## Beads that are not ordinary components

- **Data-flow bead** (CONTEXT.md gives a `flow_*` leaf as the contract and no `test_*` leaves): it is SUPPOSED to touch every participant, so 2 and 7 do not apply as written and its `TODO(bead:<component-bead-id>)` markers are the designed handoff, not deferred work. Judge instead: the shared types and interfaces are updated across all participants, the tree builds, existing tests pass, and every marker names a real participant bead.
- **Cleanup bead** (CONTEXT.md says the node was REMOVED): the contract is the retired leaf at `before_head`, and the work is deletion. Judge: the node's code and its tests are gone, no dead references or imports remain, the build is green, and nothing was reimplemented or preserved behind a flag.
- **Already satisfied** (the diff is bead-state-only, plus optional docs): verify against `origin/main` instead — the delivering commit is an ancestor and satisfies the requirement, the spec delta is non-behavioral, `go build/vet/test` pass, and the cross-bead scope guard holds.

## Spec freeze and drift reports

- **Any diff touching `spec/` is an unconditional request-changes**, whatever else the PR contains. Spec truth moves only in the authoring loop, and the gate denies such pushes structurally — one reaching you means something slipped.
- **A PR carrying `drifts/drift-*.json` gets the report itself reviewed**: validate the shape against `schema/drift.schema.json`, then judge the substance — does the cited contradiction or hole actually exist in the named files? A drift-only PR (report plus the bead's return to `open`, no code) is approved when the claim is real and well formed; the box knows not to close a bead on one, because returning it to `open` is the PR's whole point. A claim you can refute gets request-changes with the refutation, exactly like wrong code.
- **A blocking-drift PR that still carries code is malformed** — request-changes. The protocol requires the work be discarded, because the code encodes one side of a dispute nobody has adjudicated. Nothing strips it automatically, so catching it is your job; the gate is only the backstop.
