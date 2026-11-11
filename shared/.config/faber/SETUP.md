# faber gate-stack setup — host runbook

End-to-end setup to run a repo's development through the faber → portitor gate, with
**spexmachina** as the worked example. Each step is an explanation followed by a command
block (**fish** syntax). `< … >` marks a value you supply.

The whole stack is one command, `faber-stack up <project>`. It reads every instance fact
from `<project>/stack.json` and `<project>/portitor/policy.json`, and leaves the gate to
`portitor deploy`.

## Per-instance isolation

Each repo runs on its **own** instance: its own internal network, egress proxy, gate,
volumes and **scoped PAT**, so a compromised box for repo A cannot reach repo B's mirror
or PAT. `stack.json`'s `instance` derives every object name:

```text
instance spex  ⇒  network spex-net · egress spex-egress · gate portitor-spex
                  · volumes spex-repos, spex-hostkey · pin keys/portitor_host_key.pub
```

`orchestrator.yaml` and `templates.yaml` restate those names; `faber-stack up` refuses
when they disagree.

---

## 0. Prerequisites

- docker and nix on the host.
- faber's own Anthropic setup-token (`anthropic/faber`, separate from dcp's
  `anthropic/personal`) in the host's secret backend — the one `~/.config/dot/host.conf`
  declares (`security` on macOS, `secret-tool` on Arch, `systemd-creds` via `cred-store` on
  headless hosts).
- dot stowed: `faber-stack`, `role-keys`, `secret-get` → `~/.local/bin`; the egress build
  context → `~/.local/share/egress`; this project → `~/.config/faber/spexmachina`.

```fish
~/.config/faber/base/hooks/get-token claude_code_oauth_token >/dev/null; and echo "anthropic token OK"
docker info >/dev/null; and nix --version
for t in faber-stack role-keys secret-get faber faber-box portitor portitor-gate
    command -q $t; or echo "missing: $t"
end
```

---

## 1. Install the release binaries (verified)

Install `faber`, `faber-box`, `portitor` and `portitor-gate` from their latest signed
releases; never build them from source. First verify each tool's `install.sh` against the
shared release-signing key; `install.sh` then verifies the archives it installs.
faber's installer places `faber` and `faber-box` side by side; portitor's places the
`portitor` / `portitor-gate` pair (`portitor-gate` is the linux build `portitor deploy`
bakes into the gate image).

```fish
# The shared release-signing key (identical across portitor / faber / spex).
echo 'dvbozhko@gmail.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIhmCWVDP/Tcm3CqXNjTQTChbKxr223xMob9zc56Uuny' >/tmp/release-signers

for tool in portitor faber
    set -l base https://github.com/dmitriyb/$tool/releases/latest/download
    curl -fsSLO $base/install.sh; and curl -fsSLO $base/install.sh.sig
    ssh-keygen -Y verify -f /tmp/release-signers -I dvbozhko@gmail.com -n file \
        -s install.sh.sig <install.sh
    and sh install.sh   # VERSION unset ⇒ install.sh resolves + verifies the latest release
    rm -f install.sh install.sh.sig
end
```

**Version floor:** faber ≥ 0.8.0 (no host path reaches a box, so Docker userns-remap hosts
work) and portitor ≥ 0.4.0 (`portitor deploy`).

**Updating later:** `faber upgrade` moves `faber` + `faber-box` as a unit, `portitor
upgrade` moves the `portitor` pair. The next `faber-stack up` rebuilds what changed: box
and gate images are tagged by content hash, so a new binary or a policy edit is a new
image. The gate itself is replaced on every `up`, changed or not, so `up` refuses while
boxes are on the instance network. `faber resume` refuses a run whose
images changed since it started (`--fresh` starts over). `faber-stack prune` removes the
instance's images no container uses.

### macOS host notes (skip on Linux)

faber 0.8.0 **refuses** a `~/.config/faber/host.json` that still carries
`agent_socket_group`: delete that line. `box_bin` and the `~/.local/libexec/faber-box`
copy it pointed at are no longer needed.

---

## 2. Create the role keys

Three distinct keypairs — implementer, reviewer, merger — so portitor can tell them apart
by fingerprint. YubiKey resident + no-touch, so autonomous boxes sign without a prompt.
Register each pubkey on GitHub as a *Signing Key*. Skip any role whose key you already have.

GitHub shows **Verified** only when the commit's committer email is a verified email on the
key owner's account; that email is registered with the role in step 3. Without it every
commit shows **Unverified** (`reason: no_user`), and gated steps refuse to start.

```fish
for role in implementer reviewer merger
    ssh-keygen -t ed25519-sk -O resident -O no-touch-required \
        -O application=ssh:spex-$role -N "" -C "spex-$role" \
        -f ~/.ssh/spex_$role
end
```

If the resident credentials exist on the YubiKey but this host has no handle files (the
YubiKey moved to another host), recover them with `restore-role-keys` (PIN + one touch),
naming each key by its application without `ssh:`; without arguments it lists what the
YubiKey holds and asks which to restore. Only the keys you name are restored, because a
restored handle signs without a touch. Do **not** use raw `ssh-keygen -K`: it stamps every
handle "user presence required", and the boxes' autonomous signing then dies with "agent
refused operation". The `.pub` files must land in `~/.ssh`: `faber-stack` needs one per role.

```fish
restore-role-keys spex-implementer spex-reviewer spex-merger
```

---

## 3. Register the roles with faber

`role-keys --apply` names each key and runs `faber add-key`, the global
role → fingerprint registry faber resolves identities against; `--git-email` registers the
committer email with every role. `orchestrator.yaml`'s identities stay empty entries
(`implementer: {}` …) so faber looks each up by name. `faber-stack up` reads the same
registry through `role-keys --json`.

```fish
role-keys --apply --git-email <verified-account-email>
```

---

## 4. Store the scoped PAT

One fine-grained PAT per instance, on this repo only: **Contents** read/write, **Pull
requests** read/write, **Actions** read (write to let the gate rerun jobs), **Commit
statuses** read. Never share a PAT across repos. `portitor deploy` runs `secret-get
<pat_service> <pat_account>` and delivers the PAT as a file inside the gate container: it
is never on an argv, in an env var, in an image or in a host file.

```fish
security add-generic-password -s portitor-spex -a default -w '<PAT>'   # macOS
secret-tool store --label=portitor-spex service portitor-spex account default   # Arch
cred-store portitor-spex default                                       # headless
secret-get portitor-spex default >/dev/null; and echo "PAT OK"
```

---

## 5. Bring up the stack — one command

Copy `stack.example.json` to `stack.json` (host-local, gitignored) and fill it in:

| Field | Meaning |
|---|---|
| `instance` | derives every object name (above) |
| `slug` | `<owner>/<repo>` on GitHub |
| `repo` | optional: the gate's repo name, default the name part of `slug` |
| `policy` | optional: the gate policy, default `portitor/policy.json` (relative paths resolve against the project) |
| `config_dir` | optional: where the generated gate config, egress filter and `deploy.json` live, default `~/.config/portitor/<instance>` |
| `pat_service`, `pat_account` | where step 4 stored the PAT (`pat_account` defaults to `default`) |
| `allow` | the **complete** egress allow-list; boxes reach nothing else, `api.anthropic.com` included |
| `commit_emails` | required, non-empty: the gate's `allowed_committer_emails`; a pushed commit with another committer email is refused |
| `map` | optional `{<portitor role>: <registry name>}` when the registry names a role differently |

An unknown key in `stack.json` is refused. The tools the policy's commands need inside the
gate are not host data: they live beside the policy, in `portitor/gate-image.json`
(`{overlay, packages}`, the overlay path relative to that file; spexmachina's adds `br`
from `portitor/gate-overlay.nix`).

`faber-stack up` then, on every run:

1. checks every input before anything is built or written: `stack.json`, that no box is on
   the instance network, that `orchestrator.yaml` and `templates.yaml` name this instance,
   `faber validate`, the policy and its check scripts, the role registry, `gate-image.json`;
2. builds the gate config afresh under `<config_dir>/gate` from `policy.json`, `stack.json`
   and the role registry (roles are the ones the policy grants), and validates it with
   `portitor validate-config` before it replaces the previous one;
3. runs `faber build` from the project dir (existing image tags are skipped);
4. builds the egress image with the allow-list inside and starts `<instance>-egress`;
5. runs `portitor deploy`: builds the gate image, validates the config inside it, reads the
   PAT (`secret-get` prints which secret, at the moment it reads it), replaces the gate,
   verifies it, and writes the host-key pin on the first deploy.

It converges: a field removed from `stack.json` or `policy.json` is gone after the next run.

```fish
cp ~/.config/faber/spexmachina/stack.example.json ~/.config/faber/spexmachina/stack.json
$EDITOR ~/.config/faber/spexmachina/stack.json
faber-stack up spexmachina
```

**Migrating from the flag-driven `faber-stack`:** an old `stack.json` is refused. Rename
`commit_email` to `commit_emails` (a list), add `api.anthropic.com` to `allow` (the list is
now complete, nothing is added implicitly), and drop any `gate_image` (it moved to
`portitor/gate-image.json`).

**Migrating from the compose-built gate:** remove the old container and images once
(`docker rm -f portitor-spex; docker rmi portitor-spex-config portitor-spex`) and the old
pin (`rm ~/.config/faber/spexmachina/keys/portitor_host_key.pub`): the new gate keeps its
host key in `spex-hostkey`, and `portitor deploy` refuses a pin that volume does not hold.
The `spex-repos` mirror volume is reused.

---

## 6. Run

Workflows run from the project dir: faber reads `orchestrator.yaml` there and keeps its run
state in `./.faber`.

```fish
cd ~/.config/faber/spexmachina
faber run bead --param bead=<bead-id>   # pick one with `br ready` in a spexmachina checkout
faber run epic --param epic=<epic-id>
```

An epic is a pull-loop of the bead chain: each cycle's box picks the next ready epic bead,
lands it, and the loop ends on the first cycle that finds nothing ready or finds a blocking
drift report on main (`halt_reason: blocking_drift`; triage with /drift-workflow, then
rerun). A failed cycle stops the epic after the beads already landed; run
`portitor-branch clear` (alias `pbr`) to drop its stale mirror branch, then
`faber resume <run-id>` (`faber runs` lists them).

---

## 7. Lifecycle

```fish
faber-stack status spexmachina           # containers, images (in use / unused), volumes, pin
faber-stack down spexmachina             # remove the gate, egress and network; volumes and
                                         # pin stay. Refused while boxes are on the network
faber-stack down spexmachina --volumes   # also the volumes and pin — refused while a mirror
                                         # branch holds commits GitHub does not have
faber-stack prune spexmachina            # remove this instance's unused images
```
