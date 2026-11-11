# faber stack — end-to-end acceptance in CI instead of by hand

**Repos:** `dot` (the stack: `faber-stack`, the playground project) · possibly `faber` (a scripted
agent CLI) · **Status:** plan only, nothing built.

## Why

The whole faber → portitor stack (box images, egress, gate, the implement / review / fix / merge
chain, the epic loop) is accepted today only by hand: the `faber-stack-service` playground project
against the disposable repo `dvb-service/faber-stack-service`, driven by `faber-e2e reset | run |
assert`. Nothing runs it on a change, so a broken hook, policy or stack step surfaces in the next
real epic. portitor's own acceptance suite already runs in CI against a disposable repo; the stack
as a whole should too.

The obstacle is cost and credentials: an end-to-end run spends real agent tokens on every
implement / review / fix step, and needs the playground's GitHub PAT.

## What to settle

- **Separate the stack from the model.** Most of what breaks is the stack, not the model: hooks,
  policy, gate rules, the loop's control flow. faber invokes any agent CLI (`FABER_AGENT_CLI` plus
  invoke profiles), so a scripted stand-in agent — deterministic edits from the bead, a fixed
  review verdict — could drive the full chain with no model tokens. Then CI runs the scripted
  agent on every change, and a real-model run stays manual or rare (main only, scheduled, with a
  budget cap). Open: what the scripted agent must emit for each skill's result contract.
- **Credentials, as in portitor's acceptance tier.** One disposable repo, a fine-grained PAT on it
  only (Contents, Pull requests, Actions, Commit statuses; no Workflows), an operator-prepared seed
  tag the run resets to, and a test that the PAT cannot write workflows. A real-model run also
  needs a model token in CI: decide whether that is acceptable at all, and if so its scope and cap.
- **Where it runs.** Hosted runners have Docker and can install Nix (portitor's CI does), but no
  GPU, so the local-model (`-li`) variants stay out.
- **What the run asserts.** Today's `faber-e2e assert`: PRs merged, beads closed (which the
  gate's bead-closed check requires before a merge), commits showing GitHub's Verified
  signature, review threads resolved. Plus the run's own exit code and journal.

## Context

- `faber-stack-service`, its `-li` variant and `faber-e2e` move to `shared/.config/faber/old/` with
  the `spexmachina`-only rework of `faber-stack`; this plan is where they come back from.
- `faber-e2e`'s header says `--instance test`, the project README says `faber-stack-service`;
  reconcile when reviving it.
