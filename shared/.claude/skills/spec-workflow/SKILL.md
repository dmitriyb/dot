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
2. `/spec-review` on the modules #1 edited — audit in the subagent; fixes only
   after discussion
3. after discussion and agreement (if applicable) commit, with mandatory pause
   before
4. `/mint` on the result, in the main context — its per-node absorb table
   comes back for confirmation before the pipeline (adapter, ingest) runs;
   commit behind the same mandatory pause
5. push the branch
6. hand over a PR title and a one-short-paragraph description (*why* and
   *how*); the user opens the PR
