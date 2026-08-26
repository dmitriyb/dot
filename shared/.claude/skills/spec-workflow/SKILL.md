---
name: spec-workflow
description: "Manual invocation only — the user's spec-authoring loop for spexmachina, faber's authoring-side pair: /spec → /spec-review → /mint sequentially in fresh-context subagents, commits behind explicit pauses, ending in push and PR handover."
argument-hint: "<proposal-path>"
---

# Spec Workflow

Invoked as `/spec-workflow <proposal-path>`: the argument is the proposal to
drive, a path under `spec/proposals/` (the same value step 1 hands to `/spec`).

Sequentially, each skill step in a subagent (independent context):

1. `/spec` on `<proposal-path>`
2. `/spec-review` on the modules #1 edited — audit in the subagent; fixes only
   after discussion
3. after discussion and agreement (if applicable) commit, with mandatory pause
   before
4. `/mint` on the result — its per-node absorb table comes back for
   confirmation; commit behind the same mandatory pause
5. push the branch
6. hand over a PR title and a one-short-paragraph description (*why* and
   *how*); the user opens the PR
