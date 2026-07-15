# keys/ — role + gateway key material (supplied at the portitor step)

This directory is referenced by `orchestrator.yaml`'s substrate but is
**intentionally empty of secrets** — filling it is the portitor-gate step, the
one piece deliberately left until last. Nothing here is committed except this
README (see `.gitignore`).

## What goes here

| File | Kind | Used by | Notes |
|------|------|---------|-------|
| `implementer` | private signing key (resolver-interpreted) | `identities.implementer` | reuse dot's per-role key (`~/.dca-keys/…` / FIDO2 sk) |
| `reviewer` | private signing key | `identities.reviewer` | the **only** key portitor lets sign bead-closes |
| `merger` | private signing key | `identities.merger` | the **only** key portitor lets merge PRs |
| `portitor_host_key.pub` | portitor's SSH **host** public key | `remote.host_key_file` | pins `StrictHostKeyChecking=yes`; get it from the portitor deploy |

The `identities.*.key` values are resolver-interpreted references, not
necessarily raw files — a FIDO2 `sk-` key reference or an agent handle is valid.
Match whatever dot's ssh-agent identity flow already uses.

## The rest of the portitor step (outside this repo)

1. Register the three role **public** keys on portitor and map each fingerprint
   to its role (implementer / reviewer / merger), including the `role_rule` that
   only the reviewer/owner may add `"status":"closed"` to `.beads/issues.jsonl`.
2. Onboard the repo: `portitor add-repo --repo spexmachina --upstream https://github.com/dmitriyb/spexmachina.git` (portitor holds the GitHub PAT).
3. Put the portitor/`pr` **client** on the box PATH (the `fetch-pr`/`review`/`fix`/`merge` legs call it) — via the overlay or a small delivery.
4. Pin `portitor_host_key.pub` here.

Until then: the **implement** leg, the image, and the whole config *structure*
are complete and independent of portitor; the review/fix/merge legs need the
client + host key + role keys above.
