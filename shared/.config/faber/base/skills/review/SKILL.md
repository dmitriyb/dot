---
name: review
description: Review a pull request for correctness, spec traceability, and test quality
---

Review the PR described in `$FABER_BUNDLE_DIR/CONTEXT.md`. Use @~/.claude/skills/go-expert/SKILL.md for Go-specific review guidance.

CONTEXT.md gives you the bead, its spec leaves and the **mode**; `pr.json` holds the full PR state, and you are already on the PR branch. Your one deliverable is `$FABER_RESULT_DIR/review.json`. The box posts it, closes the bead on an approval, and emits the step's verdict — the closes and pushes you see in git history came from the box on previous cycles, never from an agent, so do not imitate them.

```json
{"event": "approve" | "request-changes" | "comment",
 "body": "<markdown summary>",
 "comments": [{"path": "<file>", "line": <n>, "body": "<blocker, as an inline thread>"}, ...],
 "threads": {"<open thread id>": "settled" | "open", ...}}
```

`threads` is one verdict for **every** thread in `CONTEXT.md`'s unresolved list:

- **`settled`** — the objection now holds, whether the fixer changed the code or
  convinced you it never needed changing. The box resolves it.
- **`open`** — you still stand behind it. It stays live.

An id you omit defaults to `open`, so silence is not neutral — it is a decision,
and the box logs that you left it to the default. An unresolved thread is
re-served to the next fixer as live work that it is required to answer, so a
thread you are satisfied with but left open becomes a reply you read again next
round, and again after that. That is how a review loop spends five iterations
restating itself.

## Comment format

`Approved.` — one line, nothing else. Not a summary of what you checked, and never a restatement of the spec or the diff.

Everything else you write is a blocker that must be fixed before this PR can be approved. **There is no advisory tier**: no nits, no "minor", no asides you would not block on. If it is not worth a fix cycle, do not write it — which is also what keeps the bar high for writing anything at all.

- **Inline** (`comments[]`) is the default: 1–2 sentences at the exact `path:line`, saying what is wrong *there*.
- **Body** only when a blocker has no line in the diff to attach to: one paragraph, and say why it could not be inline.

**Severity is not the size of the fix** — a one-character edit can be a blocker. In particular, anything the code *claims* that is not true is always one: a fabricated requirement or bead id, a name or comment describing behaviour the code does not have, a test named for a scenario it does not exercise. Identifiers and comments are read as fact by everyone who comes after, and this project's traceability runs on them. Untrue is never cosmetic.

## Mode

- **REVIEW** — no prior feedback. Judge the diff against the criteria below.
- **FOLLOWUP** — verify every prior feedback item against the **current files**. Replies and commit messages are not evidence: read the original request, read the file, confirm the fix is present, correct, and introduced nothing new. Approve only if every item holds.
- **WAIT** — there is prior feedback and nothing has moved since. Do not re-review: write `event: comment` with a one-line body naming what is being waited on.

If you find yourself writing the same objection a second time against code that has not changed, the disagreement is real and neither side is going to move: say so plainly in `body`. The box halts a third round on an unchanged head rather than letting the loop exhaust, and your body text is what a human reads to settle it.

## What must hold to approve

1. **Bead completion**, the one that matters most: re-read the bead line by line; every requirement has concrete code. Verbs are literal — "replaces" means the old thing is gone.
2. **Spec traceability**: the code maps to the bead's requirements, and nothing unrelated rides along.
3. **Licence**: every behavioural decision in the diff is licensed by a statement in the spec. Code that settles a question the leaves leave open — or contradict each other on — is drift, not the implementer's call. Request a drift report instead of accepting the guess.
4. **Spec hygiene** (blocker): the bead's leaves match what shipped. Stale prose — `test_*` carrying retired preconditions, output-shape mismatches, an `arch_*` describing a contract the code does not honour — is a blocker. `spex validate` passing is not sufficient; read each leaf against the diff.
5. **No deferred work**: `TODO`/`FIXME`/`HACK`/shims/compat wrappers deferring this bead's OWN work are automatic rejections.
6. **Tests**: every scenario in the `test_*` leaves has a matching test, tests verify requirements rather than implementation, and failure cases are covered. A missing scenario is a blocker.
7. **Cross-bead test scope** (blocker): the tests in the diff trace ONLY to this bead's test leaves. A test covering another bead's `test_section` belongs to that bead — default to requiring its removal.
8. **Correctness and patterns**: error paths, edge cases, leaks; idiomatic Go, consistent with the surrounding code.

## Beads that are not ordinary components

- **Data-flow bead** (CONTEXT.md gives a `flow_*` leaf as the contract and no `test_*` leaves): touching every participant is the job, and its `TODO(bead:<component-bead-id>)` markers are the handoff those beads consume. Judge it on these instead of 2 and 7: shared types and interfaces updated across all participants, the tree builds, existing tests pass, every marker names a real participant bead.
- **Cleanup bead** (CONTEXT.md says the node was REMOVED): the contract is the retired leaf at `before_head`, and the work is deletion. Judge: the node's code and its tests are gone, no dead references or imports remain, the build is green, and nothing was reimplemented or preserved behind a flag.
- **Already satisfied** (the diff is bead-state-only, plus optional docs): verify against `origin/main` instead — the delivering commit is an ancestor and satisfies the requirement, the spec delta is non-behavioral, `go build/vet/test` pass, and the cross-bead scope guard holds.

## Spec freeze and drift reports

- **Any diff touching `spec/` is an unconditional request-changes**, whatever else the PR contains. 
- **A PR carrying `drifts/drift-*.json` gets the report itself reviewed**: validate the shape against `schema/drift.schema.json`, then judge the substance — does the cited contradiction or hole actually exist in the named files? A drift-only PR (report plus the bead's return to `open`, no code) is approved when the claim is real and well formed. A claim you can refute gets request-changes with the refutation, exactly like wrong code.
- **A blocking-drift PR that still carries code is malformed** — request-changes. The protocol requires the work be discarded, and nothing strips it automatically — catching it is your job.
