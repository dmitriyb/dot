# Release signing — SSHSIG key for the spexmachina toolchain

One shared, dedicated, non-resident, passphraseless ed25519 key signs release
artifacts (binaries, install scripts) for the spexmachina toolchain (portitor,
faber, spex) via GoReleaser's `signs:` block (`ssh-keygen -Y sign`), verified
by anyone with `ssh-keygen -Y verify` — no extra tool install, since OpenSSH
ships it everywhere. This doc is the one place the shared facts live, so the
three repos don't drift against each other. Repo-specific mechanics (workflow
YAML, install.sh) live in each repo; this doc only holds what's common.

This key is **distinct** from the per-role, YubiKey-resident commit-signing
keys used to gate dev work through portitor (see `shared/.ssh/signing-key-hashes`
and `shared/.config/faber/spexmachina/keys/README.md`) — see "Two signing
domains" below. Mixing them up is the single most likely way to misconfigure
this.

## Status

| Repo | Status | Notes |
|------|--------|-------|
| portitor | **Operational** | released through `v0.1.2`; the `download → verify → install` round-trip is what the gate image builds on |
| faber | **Operational** | own release pipeline; ships `faber` + `faber-box`; `faber upgrade` moves the pair as a unit; released through `v0.1.2` |
| spex | **In progress** | copy portitor's pattern when spexmachina's release pipeline lands — update this row then |

## Public key

Not secret — safe to record here. This is the exact value that should appear,
byte-identical, in every repo's README and `install.sh`:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIhmCWVDP/Tcm3CqXNjTQTChbKxr223xMob9zc56Uuny release signing
```

Signer-id / principal (used in `-I` and every `allowed_signers` line for this
key): `dvbozhko@gmail.com` — the git commit author email, already public in
every commit, reused here rather than minting a separate identity.

The **private** key is never stored in this repo or any tool repo. It lives
offline (password manager / hardware-backed vault) and is materialized only
as each repo's `SSH_SIGNING_KEY` GitHub Actions secret.

## Generate (once, reused across all three repos)

```bash
ssh-keygen -t ed25519 -N "" -f release-signing -C "portitor/faber/spex release signing"
```

- `-N ""` — empty passphrase, required for unattended CI signing (no TTY to
  answer a prompt).
- Non-resident, deliberately distinct from the YubiKey-resident commit-signing
  key — a hardware key cannot live in a CI secret.
- One key, reused for every repo below — do not regenerate per repo.

## Wire a new repo

Per repo (portitor and faber already done; repeat for spex when it gets a
release pipeline):

```bash
gh secret set SSH_SIGNING_KEY < release-signing
```

- Repo secret, not org/environment — repeat this command in each repo.
- Pipe the **whole file**, never paste manually: the BEGIN/END markers and
  the trailing newline all matter, and a partial paste fails signing with a
  generic, hard-to-diagnose error.
- Publish `release-signing.pub`'s contents in that repo's README install
  section, and bake the same value into its `install.sh`'s `SIGNING_PUBKEY`
  constant — both copies, and this doc's copy above, must be byte-identical.
- Optional: add the same public key under GitHub Settings → SSH and GPG keys
  → Signing keys for the account each repo lives under. That publishes it at
  `https://api.github.com/users/<owner>/ssh_signing_keys`, a second,
  GitHub-hosted place to cross-check the pinned key against.

## Two signing domains — don't cross them

| | Release-artifact signing (this doc) | Commit / role signing (dev-time) |
|---|---|---|
| Namespace | `-n file` | `-n git` |
| Key | one shared, non-resident, passphraseless | per-role, YubiKey-resident |
| Lives in | repo's `SSH_SIGNING_KEY` Actions secret | `~/.ssh` / the YubiKey, registered via `faber add-key` |
| Signs | release binaries, `install.sh` | git commits, gated by portitor's `pre-receive` |
| Verified by | `ssh-keygen -Y verify -n file`, downloaders | portitor's gate, `%GF` → role |
| Reference | this doc + each repo's `RELEASE-SETUP.md` | `shared/.config/faber/spexmachina/keys/README.md` |

The `-n` namespace is what keeps these apart: a signature produced under one
is never valid under the other, even if a key were (accidentally) trusted for
both. Keep them mentally and operationally separate anyway — this key never
belongs in `shared/.ssh/signing-key-hashes` or any role-key registration.

## Footguns

- **`chmod 600` the CI temp key file.** `ssh-keygen` refuses to load a
  private key with looser permissions and fails with a generic error that
  doesn't name the permission bit as the cause.
- **Passphraseless is mandatory, not a shortcut.** There is no TTY in CI to
  answer a passphrase prompt — a protected key simply cannot be loaded there.
- **`gh secret set NAME < file`, never a manual paste** — see "Wire a new
  repo" above.
- **Two (or three, counting this doc) copies of the public key must stay in
  sync by hand.** Each repo's README and its `install.sh` both embed it
  independently; nothing enforces they match. A drifted copy fails closed
  (a verify against the wrong key just fails) but confusingly, since nothing
  points at *which* copy is stale.
- **`ssh-keygen -Y sign` always writes `<file>.sig` next to the input** — no
  flag redirects it. A GoReleaser `signs:` block's `signature:` template must
  be exactly `${artifact}.sig`, or GoReleaser looks for an output file that
  never appears.

## Reference implementation

portitor's `.goreleaser.yaml` (`signs:` block), `.github/workflows/release.yml`
(key materialization + the `install.sh` signing step), `install.sh` itself,
and portitor's own `RELEASE-SETUP.md` (regenerated per-session there, not
committed — repo-specific checklist, not a duplicate of this doc) are the
worked example. Copy the pattern verbatim for spex; update the Status table
above when it lands.
