# faber — two orthogonal evaluation suites (workflow correctness vs. benchmark)

**Repos:** `dot` (workflow: skills, hooks, templates, policy) · a new eval repo, minted ·
**Status:** plan only, nothing built.

## Why

The four box skills and their hooks were rewritten across one session (`61cdb40`…`8b439bb`).
Every defect found in that work was caught by a hand-run fixture in `/tmp` or by a dead e2e
run — nothing durable. Four of them were statically visible and still took a failed run or a
manual diff to notice:

| defect | how it was found |
|---|---|
| `faber-stack-service-li` fix template had no prelude at all | reading the file by hand |
| `faber-stack-service-li` merge template lacked `blocked_by` output | `faber validate`, only after a workflow referenced it |
| fss gate policy missing `checks`/`logs`/`rerun` verbs | a real run died in the merge prelude |
| fss gate policy missing the `.github/**` freeze both skills assert | diffing the two policies by hand |

## The split

Two suites, orthogonal, and they conflict if merged:

- **A — workflow correctness.** Does the machinery interact correctly, and how do agents behave
  under uncertainty and deliberate spec mismatch? **Model held fixed and strong**, so the
  workflow is the only variable.
- **B — benchmark.** Compare harnesses / local models / effort levels. **Workflow frozen**, so
  the configuration is the only variable.

Consequences of the split, all load-bearing:

- They cannot share a seed. A needs deliberate spec defects; B needs a clean spec or the defect
  dominates the measurement.
- Separate repos, one mint with variant flags. A benchmark baseline must be frozen while the
  workflow repo churns; sharing a repo means every A edit voids B's history.
- Running A with a weak model conflates "workflow broken" with "model failed".

## Tiers

| tier | needs an agent | cost | run when |
|---|---|---|---|
| **A0** static checks over the config tree | no | free | every commit to `dot` |
| **A1** hook fixture tests | no | free | every commit to `dot` |
| **A2** workflow behaviour, fixed strong model | yes | real | skill or hook changes |
| **B** benchmark sweep | yes | high | workflow frozen; rarely |

### A0 — static checks (highest value per effort)

Would have caught all four defects in the table above. Candidates:

- every template that uses `fetch-pr` declares a prelude; every declared hook/skill name
  resolves to a file that **exists and is executable** — `faber validate` checks names only,
  never file existence (verified: deleting a wired hook still validates clean)
- every `policy.json` grants the action verbs the base hooks actually call
  (`grep -o 'portitor pr [a-z]*'` over `base/hooks/` and the merge skill)
- policy parity across projects for the rules the skills assert (`spec/**`, `.github/**`,
  `.beads/**` freezes)
- `checks.budgets[].name` entries correspond to real CI job names — portitor matches exactly
  and falls back to `default_budget` silently (`internal/action/checks.go:83`, name from
  `internal/action/action.go:586`)
- no per-project copy has drifted from `base/` where the file is supposed to be shared

### A1 — hook fixture tests (already written once, then discarded)

- `fetch-pr` mode truth table: REVIEW / FOLLOWUP / WAIT, 14 cases incl. the CI-report comment
  exclusion and a negative control
- `post-review`: bead-status branches (in_progress / open / closed), comment-format checks
- `post-answers`: reply verdicts, unresolved-tree refusal, absent/malformed answers
- `post-merge`: diagnosis-only `merge.json`, stale keys ignored, gate refusal routing
- `next-bead-context` → `finish-implement` sentinel seam
- `prepare-fix`: behind-clean / dirty-conflict / ci_red-also-behind / review-cycle no-op

### A2 — agent behaviour under uncertainty

Seeded-defect variants, one per drift class the schema distinguishes: a contradiction between
an arch leaf and a dependency's promise, an enumerated test scenario no arch statement covers,
a `uses` seam claim the dependency never makes. Blocking and non-blocking of each.

Assertions are binary and machine-checkable:
- blocking defect → the only passing outcome is a drift-only PR (report + bead returned to
  `open`, no code). A working implementation is a **fail**.
- non-blocking → code plus a report riding along.
- report validates against `schema/drift.schema.json`; `blocking` classified correctly.

Cheapest first step, no implement run needed: a hand-written PR that silently resolves a
seeded ambiguity, fed straight to the review step. Tests the licence check — the only net for
a papered-over spec defect — as a static fixture.

## B — the eval repo

**Invent the format.** A real codec (H.264, GIF) has priors: a model filling a spec gap from
memory usually fills it *correctly*, so the papering-over leaves no trace, and variance between
configurations collapses toward retrieval. With an invented container + RLE/delta codec, every
byte must come from the leaves and a guess produces wrong bytes immediately. Cost: the
reference encoder must be written in the mint (~100 lines) instead of generated with ffmpeg.

Shape, chosen to exercise the paths that have never run:
- a shared bitstream header used by encoder and decoder → a real `data_flow` node
- 4–5 components with `uses` seams (bitstream writer/reader, frame codec, muxer, CLI)
- `test_*` leaves with enumerated scenarios
- a removal in a later proposal, so cleanup beads get exercised
- stdlib only (keeps the egress allow-list empty)

~6–10 beads: enough to discriminate, small enough to sweep.

### Metrics

- **first-pass approval rate** — the quality proxy; what a cheaper configuration degrades on
- fix cycles per bead; whether the land loop was entered at all
- output tokens per bead (thinking vs. not, where the harness exposes it)
- the byte-exact assert: did the artifact actually work
- wall-clock — the weakest signal; 3× faster at 1.5 fix cycles per bead is not faster

### Provenance (required from day one)

Every result records the **workflow commit SHA** (`dot`) alongside spec version, model and
effort. The workflow and the spec live in different repos; a number carrying neither is
uncomparable within weeks.

## Open

- whether A0/A1 run as a Go test suite in `dot`, a shell harness, or CI on the dot repo
- whether the eval repo's spec is authored by hand or minted from a proposal like spexmachina's
- B is worth building only once the workflow stops moving — benchmarking a moving target
  produces numbers that get thrown away
