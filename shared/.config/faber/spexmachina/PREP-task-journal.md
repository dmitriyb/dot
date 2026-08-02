# PREP — running the task-journal epic (spexmachina-y0wc) on the arch host

Briefing for the agent preparing this machine. Context: the epic's 41 beads were minted
from spec commit `5abcb55` on branch `spec/task-journal` (spexmachina); the state commit
is `5095d09`. The epic implements proposal `2026-08-01-task-journal` — the bead-map →
task-journal rewrite — and deliberately runs under the OLD integer-label model; do not
"modernize" any hook or skill to journal vocabulary before the epic lands.

## 0. Ordering — do these in sequence

1. The operator merges the `spec/task-journal` PR into spexmachina main. Nothing below
   makes sense against a main that lacks the epic's spec and beads.
2. `git pull` in: spexmachina, faber, portitor, dot (this file arrives with dot).
3. Everything else below.

## 1. Overlay fixes required before `faber build` works here

`shared/.config/faber/spexmachina/overlay.nix`:

- **br x86_64 hash is a stub.** `brSha256."x86_64" = final.lib.fakeSha256` — the image
  has only ever been built on the arm64 macOS VM. This host is x86_64: fetch the
  `br-0.2.16-linux_x86_64.tar.gz` asset hash (nix-prefetch-url the release URL) and fill
  it, or the build fails on the fake hash.
- **Bump the spex pin.** `spex.src.rev` is `397866dd…` (pre-epic). Set it to the merged
  main HEAD of spexmachina, then refresh BOTH hashes (`src.sha256` and `vendorHash`) —
  standard two-pass: set each to `lib.fakeSha256`, build, copy the real hash from the
  error. The boxes must carry a spex that knows the current spec but still speaks the
  bead-map model — post-merge main is exactly that.
- claude-code pin (2.1.207) is fine; bump only if the operator asks.

## 2. Config verification

- `faber validate --config orchestrator.yaml` then `faber build --config orchestrator.yaml`.
- Models are set per template in `templates.yaml`: implement/fix → `claude-sonnet-5`,
  review → `claude-opus-5` (via `ANTHROPIC_MODEL` in `run.env`). **Verify the box's
  claude actually honors it**: run a throwaway box or `docker run` the image and check
  `ANTHROPIC_MODEL=claude-sonnet-5 claude -p "what model are you"` reports Sonnet.
- **Effort level is NOT configured.** If the operator wants Sonnet on high effort,
  find the mechanism (a settings.json baked via the overlay, or a CLI flag in the
  invoke path) and verify it end-to-end before the first wave; otherwise run with
  defaults and note that in the report.
- Gate stack: `faber-stack up` per SETUP.md if not already standing; confirm the three
  role keys resolve (`faber add-key` registry), the host-key pin exists in `keys/`, and
  a manual `ssh git@portitor-spex` refusal looks right.

## 3. Trial before the epic

Run ONE light bead end-to-end before any fan-out:

    faber run bead --config orchestrator.yaml --param repo=spexmachina --param bead=spexmachina-y0wc.34

(`.34` = ingest: SnapshotSaver — near-no-op code-wise, exercises the full loop: context
hook → claim → implement → PR → review loop.) If the review loop stalls at merge, see §5.
Inspect the PR quality before proceeding.

## 4. The epic runs in WAVES — never one shot

Faber branches every bead off `origin/main`; dep edges gate scheduling, not code
visibility. This epic is one coherent rewrite, so:

1. `faber run epic --config orchestrator.yaml --param epic=spexmachina-y0wc` runs the
   currently-ready leaves. Use `--max-parallel` conservatively (4).
2. The operator reviews and merges that wave's PRs.
3. Re-run the epic command — closed beads drop out of the fan-out; the next wave
   branches off the updated main. Repeat. Expect 4–6 waves.

**Hard rule: the bead that deletes `.bead-map.json` (and runs the backfill) merges
LAST, after every other bead is closed.** The boxes' `gather-context` hook runs
`spex map context <int>` against the map file; once a merged main lacks it, any
remaining bead gets no context. Check the dep graph actually forces this before the
final wave; if it does not, hold that PR manually.

## 5. Known gap — auto-merge cannot succeed

All three role keys belong to one GitHub account, GitHub forbids self-approval, the
review skill posts `--event comment` — but portitor's merge preconditions require
`reviewDecision == APPROVED`. So Gate B's merge step will stall by construction. With
the wave pattern this is moot (the operator merges), but do not burn time "debugging"
it, and do not weaken portitor to work around it. If a fix is wanted later, it is a
portitor change (configurable approval predicate), not a faber or skill hack.

## 6. Budget and models

- Suggested first-wave budget flags: start without `--budget`, observe the trial bead's
  cost in the run report, then set a per-wave budget ~1.5× extrapolated.
- Whole-epic rough order: 10–25M tokens across all waves and review loops.
- If a heavy bead (Reconciler, RefreshHandler, MappingStore, ContextResolver, Resolver)
  thrashes in review on Sonnet, temporarily set `ANTHROPIC_MODEL: claude-opus-5` on the
  `implement` template and re-run just that bead.

## 7. Report back to the operator

After the trial bead: model verification result, effort-level status, cost, PR quality
impression, and any friction in hooks/stack. After each wave: merged PRs, review-loop
iteration counts, cost vs budget, and anything that smells like a spec defect (file it,
don't fix it inline — spec changes go through the pipeline, not through implementation
PRs).
