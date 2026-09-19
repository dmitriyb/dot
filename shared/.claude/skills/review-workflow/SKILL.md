---
name: review-workflow
description: "Manual invocation only — the user's periodic full-spec audit for spexmachina: /spec-review all → /propose, with the audit in a fresh-context subagent and the proposal in the main context; edits no spec file, ends by handing the review proposal to /spec-workflow."
argument-hint: ""
---

# Review Workflow

Invoked as `/review-workflow`, no argument: audit the whole spec, turn the
decisions into one review proposal. Nothing under `spec/` is edited here.

Sequentially:

1. `/spec-review all` — the audit in a fresh-context subagent (fresh eyes,
   read-only), the discussion and the decisions file in the main context, both
   per the skill's own `all` contract
2. `/propose` on that decisions file, in the main context
3. hand over the proposal path; `/spec-workflow <proposal-path>` is the next
   command
