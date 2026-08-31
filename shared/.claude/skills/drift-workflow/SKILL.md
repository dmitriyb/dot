---
name: drift-workflow
description: "Manual invocation only — the user's drift-triage loop for spexmachina: /drift → /spec-review → /mint, with /drift and /mint in the main context and /spec-review in a fresh-context subagent, a per-report and per-node assessment before any commit, commits behind explicit pauses, ending in push and PR handover."
argument-hint: "[drift-report-files]"
---

# Drift Workflow

Invoked as `/drift-workflow [files]`: arguments name specific `drifts/drift-*.json`
reports; with none given, every report in `drifts/` is in scope.

Sequentially. `/drift` and `/mint` run in the main context — verdicts fork on
judgement calls that belong to the user, and the adapter/ingest mutations run
foreground behind announced pauses; only `/spec-review` runs in a subagent
(fresh eyes, read-only):

1. `/drift` on the reports, in the main context — collect, validate, verdict
   each (accepted / rejected / overtaken), apply the accepted corrections with
   `/spec` discipline; each verdict that rests on a fork or an unverifiable
   assumption is put to the user before it is applied
2. `/spec-review` on the modules #1 edited — audit in the subagent; fixes only
   after discussion
3. the pre-commit assessment, before anything is committed: per changed node —
   what changed, cosmetic (records shipped, test-pinned behaviour) or
   formative (births work), and the task count that follows; after discussion
   and agreement commit, with mandatory pause before
4. `/mint` on the result, in the main context — its per-node absorb table
   comes back for confirmation before the pipeline (adapter, ingest) runs;
   commit behind the same mandatory pause
5. push the branch
6. hand over a PR title and a one-short-paragraph description (verdict per
   report, the baseline decision and *why*); the user opens the PR. A blocking
   triage's epic resumes with `faber run epic` after the merge
