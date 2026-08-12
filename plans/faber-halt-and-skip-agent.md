# faber — first-class halt, and prelude-driven agent skip

**Repo:** `github:dmitriyb/faber` · **Process:** `/pr-workflow`

Two independent features. Both are prerequisites for making the epic loop's merge step
deterministic; neither depends on the portitor work, so they can land in parallel.

## Feature 1 — halt as a terminal status

### Why

faber has **no halt concept**. A grep for `halt` across the Go tree returns a single comment
about fail-stop and nothing else. What looks like halting today is a convention layered on top
of loop conditions: a project template declares a `halt_reason` output, a context hook writes
`{"done":true,"halt_reason":"blocking_drift",…}`, and the *actual* stopping is done by
`done:true` satisfying the cycle loop's `until steps.implement.done == true`. `halt_reason` is
decoration; `done` does the work. A wrapper script then prints an advisory epilogue.

That works only because the halting step happens to be the one whose output the loop's `until`
reads. It does not generalise. A merge-time halt — CI stuck past its retry budget, findings
posted, operator must triage — cannot ride that mechanism: merge is the last step in a cycle
and the loop condition reads the *implement* step. Encoding it would mean threading a sentinel
backwards into the next cycle's implement step to stop the loop, which is unreadable and
fragile.

There is also a semantic gap. Today the only way for a step to stop the run is to **fail**, and
a failure fail-stops the dependency chain: one hook exiting 1 produces hundreds of
`skipped-dependency` rows and a nonzero exit. "Operator must triage" and "something broke" are
different outcomes and should be machine-distinguishable.

### Shape

- A step may settle as **halted**: a terminal status distinct from `ok` and `failed`.
- A halted step carries a `halt_reason` (and optionally structured detail) surfaced in the run
  report and the journal.
- Downstream steps settle with a skip reason that names the halt, distinct from
  `skipped-dependency`.
- The run's exit code distinguishes halted from failed, so a supervising script can branch
  without scraping text.
- `faber resume` treats a halted run as resumable from the halted step, the same way it
  re-enters a failed one.

### Design notes

- Keep the existing `blocking_drift` behaviour working. Either migrate it onto the new
  mechanism or leave the convention intact and additive — but do not end up with two ways to
  halt that behave differently.
- A halt is not an error: it should not be reported through the failure-policy path that
  drives fail-stop.

### Acceptance criteria

- [ ] A step can settle halted with a reason, from a hook and from an agent result.
- [ ] Halted runs exit with a code distinct from both success and failure.
- [ ] Downstream skips are attributed to the halt, not to a dependency failure.
- [ ] The run report names the halting step and its reason without the reader parsing JSON.
- [ ] `faber resume` re-enters a halted run at the halted step.

## Feature 2 — prelude may skip the agent

### Why

Box phase order is `clone → signing → context hook → prelude hook → agent`. The agent always
runs. For steps whose decision is already made before the agent starts, that is a pure waste:
the merge template's own postlude says it outright — *"No judgement lives here: the merge
DECISION was made upstream … a script's job, not an agent's."*

In the epic loop that is one agent turn per cycle, up to the loop bound, spent invoking a
script. Once a prelude can establish that the PR is mergeable, the entire happy path should be
prelude → postlude with no model call at all.

### Shape

- A prelude signals the skip through the existing bundle convention — e.g. `FABER_SKIP_AGENT=1`
  in `bundle.env`, alongside the `PR=` / `MODE=` values hooks already write.
- **Not a magic exit code.** Exit status already means pass/fail for hooks and is consumed by
  `set -e` in shell hooks; overloading it with a third meaning will be mis-handled.
- **Opt-in per template**, not implicit per role. A template declares itself agent-skippable;
  the default stays "the agent runs". Skipping is then a reviewable property of the template
  rather than emergent behaviour.
- When the agent is skipped, the step's declared `output` contract must still be satisfied — by
  the postlude, or by the prelude itself. faber must fail loudly if it comes back unsatisfied,
  rather than settling a step with missing outputs.

### Design notes

- Check the interaction with `input_hash` and journal replay: a step that sometimes skips its
  agent must still resume correctly, and a resumed run must not silently change whether the
  agent ran.
- Cost/metering records should reflect that no agent ran, so epic-level accounting stays honest.

### Acceptance criteria

- [ ] A prelude can skip the agent on an opt-in template; the postlude still runs.
- [ ] A template not declaring itself skippable ignores the signal (and says so).
- [ ] A skipped-agent step with unsatisfied declared outputs fails with a clear message.
- [ ] Resume across a skipped-agent step behaves identically to the original run.
- [ ] Journal and cost records show no agent invocation.

## Consideration, not a requirement — hook timeouts

There is **no timeout handling** anywhere in `pipeline/`, `agent/`, or `config/`. That suits the
intended consumer: a wait-for-CI prelude may legitimately block for minutes and nothing will
kill it. The flip side is that a hook which hangs hangs the run indefinitely.

The consuming prelude will self-bound (it polls against per-check budgets and gives up), so
this is not a blocker. Whether faber grows a per-hook timeout budget is a separate decision —
worth raising in review, worth *not* bundling into this change unless it falls out cheaply.

## Why both are needed together

The consuming design is a merge prelude that classifies merge-readiness and then either lands
deterministically or escalates:

| Situation | Outcome |
|---|---|
| mergeable, checks green | skip the agent, postlude lands — **Feature 2** |
| checks pending within budget | keep waiting |
| base moved | update the branch, checks re-run |
| a check hung past budget | cancel + re-run, bounded by attempt cap |
| checks red | route to the review/fix loop |
| still stuck at the cap | agent posts findings, run **halts** — **Feature 1** |

Feature 2 removes the cost from the common path; Feature 1 gives the uncommon path an exit that
is not a failure cascade. Without both, the step is either expensive or unable to stop cleanly.

## Out of scope

- The prelude itself, the CI-aware review step, and any project config — those live in the dot
  repo's faber project and land after both this and the portitor work are released.
- Agent session continuity between steps. Every step is a fresh box with no carried context by
  design; the designs above assume state is re-derived from durable stores (GitHub, beads,
  git), never remembered.

## Related

- `plans/portitor-actions-proxy.md` — the gate-side verbs the prelude will call.
