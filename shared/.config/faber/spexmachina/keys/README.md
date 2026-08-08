# keys/ — gateway host-key pin only

This directory holds exactly one thing: the portitor host-key pin. **Role keys do
not live here.** They live in `~/.ssh`, and faber resolves an identity by *name →
fingerprint → the matching `~/.ssh` key* through its registry (`faber add-key`),
not by a path in this dir. Nothing here is committed except this README (see
`.gitignore`).

## What goes here

| File | Kind | Used by | Notes |
|------|------|---------|-------|
| `portitor_host_key.pub` | portitor's SSH **host** public key | `remote.host_key_file` | pins `StrictHostKeyChecking=yes`; capture with `ssh-keyscan -t ed25519 portitor-spex` |

That's it. The `identities` block in `orchestrator.yaml` carries **no** `key:`
paths — each role (`implementer`/`reviewer`/`merger`) is an empty entry resolved
via the registry.

## How role identities are wired (not here)

1. Keys live in `~/.ssh` (or on the YubiKey), any filename — the fingerprint is
   the id. Register each with faber: `faber add-key --role implementer --fingerprint SHA256:…`
   (the `role-keys` helper generates these lines). faber matches the fingerprint
   to a key in `~/.ssh` at run time.
2. Register the same fingerprint on the gate: `portitor add-role --repo spexmachina
   --role implementer --fingerprint SHA256:… [--pub …]`, including the role rule
   that only reviewer/owner may add `"status":"closed"` to `.beads/issues.jsonl`.
3. Onboard the repo on its per-repo instance: `portitor add-repo --repo spexmachina
   --upstream https://github.com/dmitriyb/spexmachina.git` (the `portitor-spex`
   instance holds the GitHub PAT).
4. Pin `portitor_host_key.pub` here.

Steps 2–4 are what `faber-stack up` performs (roles, mirror, host-key pin). The
in-box portitor/`pr` **client** is already part of the image toolset
(`portitor-client` in `overlay.nix` + `images.yaml`) — no separate delivery.
See `../../SETUP.md` for the full ordered runbook.
