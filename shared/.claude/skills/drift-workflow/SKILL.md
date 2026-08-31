---
name: drift-workflow
description: "Manual invocation only — the user's drift-triage loop for spexmachina: /drift → /spec-review → /mint sequentially in fresh-context subagents, a per-report and per-node assessment before any commit, commits behind explicit pauses, ending in push and PR handover."
argument-hint: "[drift-report-files]"
---

# Drift Workflow

Invoked as `/drift-workflow [files]`: arguments name specific `drifts/drift-*.json`
reports; with none given, every report in `drifts/` is in scope.

Sequentially, each skill step in a subagent (independent context):

1. `/drift` on the reports — collect, validate, verdict each (accepted /
   rejected / overtaken), apply the accepted corrections with `/spec`
   discipline; its per-report verdicts come back for discussion
2. `/spec-review` on the modules #1 edited — audit in the subagent; fixes only
   after discussion
3. the pre-commit assessment, before anything is committed: per changed node —
   what changed, cosmetic (records shipped, test-pinned behaviour) or
   formative (births work), and the task count that follows; after discussion
   and agreement commit, with mandatory pause before
4. `/mint` on the result — its per-node absorb table comes back for
   confirmation; commit behind the same mandatory pause
5. push the branch
6. hand over a PR title and a one-short-paragraph description (verdict per
   report, the baseline decision and *why*); the user opens the PR. A blocking
   triage's epic resumes with `faber run epic` after the merge
