# portitor — proxy the GitHub Actions surface (target: v0.2.0)

**Repo:** `github:dmitriyb/portitor` · **Process:** `/pr-workflow` · **Release:** minor bump to
`0.2.0` (new action verbs + config schema keys — feature, not patch).

## Why

The faber epic loop lands a bead per cycle: implement → bounded review/fix loop → merge. The
merge step fails today whenever CI has not settled, because portitor's merge gate requires
`mergeStateStatus == CLEAN` and a PR whose checks are still running reads `UNSTABLE`. The
post-merge hook retries 5×3s — a window sized for GitHub's mergeability lag, not for CI
duration — then fail-stops the whole epic.

The fix is a prelude that waits for checks *before* the merge step commits to landing, and
that can re-run a job which has hung. Neither is expressible today: **portitor's action set is
PR-domain only** (`fetch|comment|review|reply|resolve|describe|merge|close`). Nothing reaches
the Actions API, so the gate's PAT scope is inert no matter how it is provisioned.

Boxes have no route to GitHub except through the gate — their egress allow-list is the
Anthropic API and the Go module proxies. Anything a box needs from Actions must be proxied.

## Background (verified against the tree)

| Fact | Anchor |
|---|---|
| Action verbs are a closed, validated set | `internal/config/config.go:377` |
| Dispatch is default-deny against `action_roles` | `cmd/portitor/main.go:416` |
| Declared-but-unwired verbs error rather than fall through | `cmd/portitor/main.go:529` |
| `g.run` pins `-R <repo>` on every gh call; `runAPI` does **not** | `internal/action/action.go:53,70` |
| `Fetch` returns PR conversation only — no check state | `internal/action/action.go:397` |
| `FetchMergeState` already queries `mergeStateStatus,statusCheckRollup` | `internal/action/action.go:589` |
| Merge gate requires `CLEAN` | `internal/action/action.go:640` |
| `CheckRun` decodes only name/context/conclusion/state | `internal/action/action.go:564` |

`gh pr view --json statusCheckRollup` already returns `status`, `startedAt`, `completedAt`,
`workflowName`, and `detailsUrl` (which embeds run id and job id). portitor currently discards
all of it — the data is on the wire, the struct just drops it.

## Design decisions (settled)

**The box names the PR; the gate resolves the run.** No verb accepts a run id or job id. The
gate derives the workflow run from the PR's head SHA. This is the same discipline `-R` already
encodes, and it matters more here: the repo has a `release.yml`. A caller-supplied run id would
let a box re-run a release workflow, publishing artifacts entirely outside the review path.

**No `workflow_dispatch`, ever.** Re-run replays an already-defined workflow on an
already-pushed commit — no new code, no caller-supplied inputs, blast radius is compute.
`workflow_dispatch` takes arbitrary inputs and is a code-execution primitive. It stays out of
the verb set.

**Check state lives in one verb.** `fetch` remains the PR-conversation domain (reviews,
comments, threads). CI and merge-readiness state go in `checks`. Two verbs, two domains, no
overlapping views to drift apart. `fetch-pr`-style context hooks call both.

**Cancellation is run-level.** The GitHub API has no per-job cancel. The stuck path is
therefore: cancel the run, then re-run failed/cancelled jobs. Already-completed green jobs are
not re-run, which is the desired outcome, but the mechanism is coarser than "re-run that one
job" — policy must be written against run-level semantics.

**Enforcement belongs in the gate, not the caller.** The prelude runs inside a box; box-side
limits are advisory. The gate refuses a re-run when the attempt cap is reached or when the
run's head SHA no longer matches the PR head — the same reasoning that makes `merge_gate`
re-derive state rather than trust the request.

**The gate cannot distinguish callers.** Prelude and agent both authenticate as the same role,
so "automatic re-runs only for stuck jobs" is a client-side policy and must not be presented as
a gate guarantee. What the gate *can* enforce is a config switch on whether a run whose jobs
completed with `FAILURE` may be re-run at all, plus the attempt cap that bounds every case.

## Work items

### 1. `pr checks --pr N` (read)

Returns, as JSON:

- per check: `name`, `status` (`QUEUED|IN_PROGRESS|COMPLETED`), `conclusion`, `startedAt`,
  `completedAt`, `workflowName`
- the owning workflow run: run id, job id, and **`run_attempt`**
- **`mergeStateStatus`** (`CLEAN|BEHIND|DIRTY|UNSTABLE|BLOCKED|UNKNOWN`) and `headRefOid`

`run_attempt` is not in `statusCheckRollup`; it comes from the run object
(`/repos/{owner}/{repo}/actions/runs/{run_id}`). Resolve the run from the PR head SHA and fold
both into one response — callers must not have to parse `detailsUrl` in shell.

`run_attempt` matters because faber boxes are stateless: every step is a fresh container with
no memory of prior attempts, so "have I already re-run this twice?" has to be a fact read from
GitHub, not a counter held by the caller.

Widen `CheckRun` to carry the new fields. Keep `checkName()` and `succeeded()` — they already
handle GitHub's two shapes (check runs vs legacy status contexts).

### 2. `pr rerun --pr N` (write)

1. Resolve the run from the PR head SHA; refuse if the run's head no longer matches (stale).
2. Refuse if `run_attempt >= checks.max_attempts`.
3. Refuse if every job completed `FAILURE` and `checks.allow_rerun_failed` is false.
4. If the run is in flight, cancel it, then re-run failed/cancelled jobs.

Returns the new attempt number so a caller can confirm the re-run took.

### 3. `pr logs --pr N` (read)

Failed jobs only. **Tail and byte-cap server-side** from `checks.log_tail_bytes` — a caller
must not be able to request the full log. Actions logs reach tens of megabytes; an unbounded
response would blow an agent's context budget, and the cap has to be enforced where the box
cannot override it. This is also the natural redaction point if a workflow ever echoes
something it should not.

### 4. Config schema

Add a `checks` block to the per-repo config, alongside `merge_gate`:

- per-check-name budgets (how long before a pending check counts as stuck), with a default
- `max_attempts` (attempt cap enforced by the gate)
- `allow_rerun_failed` (bool)
- `log_tail_bytes`

Budgets are per check name, not one global number: on a representative repo `build` completes
in ~17s, `vet` ~27s, `test` ~97s, and a spec gate can legitimately run for minutes. A single
flat budget either declares healthy jobs stuck or never fires.

Extend the closed verb set with `checks`, `rerun`, `logs` so `action_roles` accepts them.

### 5. Role wiring

- `rerun` → merger only
- `checks`, `logs` → implementer, reviewer, merger (the fixer needs failure detail to act on)

`identity_only_roles: [merger]` constrains commits, not API actions — no conflict.

## Acceptance criteria

- [ ] No verb accepts a run id, job id, or workflow name from the caller.
- [ ] `pr checks` returns per-check state plus `run_attempt` and `mergeStateStatus` in one call.
- [ ] `pr rerun` refuses on stale head, refuses at the attempt cap, and (per config) refuses an
      all-failed run — each with a distinct, attributable message.
- [ ] `pr logs` cannot return more than the configured cap regardless of caller input.
- [ ] A config naming the new verbs validates; an unknown verb still fails closed.
- [ ] Accept-level coverage for the rerun path, in the style of the existing seeded gate accept
      tests.

## Out of scope

- `workflow_dispatch`, or any verb taking caller-supplied workflow inputs.
- Deciding *when* to re-run — that policy lives in the faber prelude.
- Log parsing or failure classification. The gate returns bytes; agents interpret them.

## Deployment ordering — read before rolling out

The gate validates every `repos.d/*.json` at boot, and unknown `action_roles` verbs fail
validation. A repo config naming `checks`/`rerun`/`logs` **will prevent a 0.1.7 gate from
starting**. Order is therefore fixed:

1. Release portitor 0.2.0.
2. Bump `portitor.version` + both arch `sha256` values in the dot repo's shared
   `versions.json` (consumer: `nix-gate`) and rebuild the gate image.
3. Only then add the new verbs to the per-repo config.

## Related

- `plans/faber-halt-and-skip-agent.md` — the faber-side features this unblocks.
- The consuming prelude, the CI-aware review step, and `.github/**` content rules land in the
  dot repo's faber project config once both are released.
