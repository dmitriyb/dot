---
name: spec-workflow
description: "Manual invocation only — the user's spec-authoring loop for spexmachina, faber's authoring-side pair: /spec → /spec-review → /mint, with /spec and /mint in the main context and /spec-review in a fresh-context subagent, commits behind explicit pauses, ending in push and PR handover."
argument-hint: "<proposal-path>"
---

# Spec Workflow

Invoked as `/spec-workflow <proposal-path>`: the argument is the proposal to
drive, a path under `spec/proposals/` (the same value step 1 hands to `/spec`).

Sequentially. `/spec` and `/mint` run in the main context — authoring is a
stream of judgement calls that belong where the user is, and the adapter/ingest
mutations run foreground behind announced pauses; only `/spec-review` runs in a
subagent (fresh eyes, read-only):

1. `/spec` on `<proposal-path>`, in the main context
2. `/spec-review`, in fresh-context subagents, never in the main context. First run the scope
   script once on a scratch stage (`python3 skills/spec-review/scope.py --stage <tmp>`) and read
   its `size` and `reviewers` lines; that many independent reviewers run in parallel, each
   invoking `/spec-review` with no argument on its own stage (the read plan makes their reading
   identical, so the second reviewer's reading is served from the prompt cache), each read-only,
   each handing back a pointer to its stage's `FINDINGS.tsv`. The reviewer models are a
   parameter of the run, stated before launching. Then, before discussing anything, per run:
   audit the transcript against its stage (`skills/spec-review/audit-reads.py <transcript>
   <stage>`) — a run that read outside the stage is discarded and rerun — and take its cost
   figures (`skills/spec-review/cost.py <transcript>`). Union the findings
   (`skills/spec-review/merge-findings.py <merged> <stage>...`), cut the passages
   (`skills/spec-review/passages.py <merged>`), and run one verification subagent over the union
   (`skills/spec-review/verify.md`). Present to the user: the audit results, the cost per reviewer
   and the cache split, the findings table rendered from the merged file with each row's verdict
   and which reviewers found it, and the open questions. Only findings that hold are discussed.
   Fixes are applied in the main context only after discussion and an explicit go
3. after discussion and agreement (if applicable) commit, with mandatory pause
   before
4. `/mint` on the result, in the main context — its per-node absorb table
   comes back for confirmation before the pipeline (adapter, ingest) runs;
   commit behind the same mandatory pause
5. push the branch
6. hand over a PR title and a one-short-paragraph description (*why* and
   *how*); the user opens the PR
