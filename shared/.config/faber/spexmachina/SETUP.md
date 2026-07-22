# faber gate-stack setup — host runbook

End-to-end setup to run a repo's development through the spex/faber → portitor
gate. This runbook is **generic**: it is parameterized on `<instance>` / `<slug>`
/ `<pat>` / `<project>`, and uses **spexmachina** as the concrete worked example
throughout. Each step is an explanation block followed by a separate command
block (**fish** syntax). Run on your host (faber-on-host). `< … >` marks a value
you supply.

The whole gate stack is one command — `faber-stack up` — which folds the
otherwise-manual bring-up (create the internal network, run the gate + egress,
`docker exec … add-repo`/`add-role`, `ssh-keyscan` the host key) into a single
idempotent step.

## Per-instance isolation

Each repo runs on its **own** gate instance: its own internal network, egress
proxy, gate container, mirror volume, and **scoped PAT**. A compromised box for
repo A therefore cannot reach repo B's mirror or PAT. Never share a PAT across
repos. One knob — `--instance <name>` — derives every object name, so the box's
`orchestrator.yaml` and the gate stack agree by construction:

```text
--instance spex  ⇒  network spex-net · egress spex-egress · gate portitor-spex · volume spex-repos · project spex
```

## Parameters (fill once; the blocks below reference them)

The spexmachina values are shown as the example. `faber`/`faber-box`/`portitor`
are installed as **verified release binaries** (§1) and the gate image is built
by faber-stack from dot's own context — so **no source checkout is needed at
all**. `DOT` is your dot checkout; `PROJECT` is the installed project dir
(`~/.config/faber/<name>`, stowed from dot — its `keys/` receives the host-key
pin); `PAT` is the keychain service holding this repo's scoped GitHub PAT.

```fish
set -x INSTANCE spex
set -x SLUG     dmitriyb/spexmachina
set -x PAT      portitor-spex
set -x PROJECT  ~/.config/faber/spexmachina
set -x DOT      ~/dot
```

---

## 0. Prerequisites (verify, don't redo)

docker + nix are on the host; the Anthropic setup-token is in the keychain;
`faber`/`faber-box`/`portitor` are installed from their verified v0.1.0 releases
(§1). The faber assets install from dot via **stow**: `faber-stack`/`role-keys`
→ `~/.local/bin`, the gate compose + egress build-context → `~/.local/share/{portitor,egress}`,
and this project → `~/.config/faber/spexmachina`. Re-stow after `git -C $DOT pull`.

```fish
security find-generic-password -s anthropic -a personal -w >/dev/null; and echo "anthropic token OK"
docker info >/dev/null; and nix --version
command -v faber-stack; and command -v role-keys; and command -v faber; and command -v portitor
```

---

## 1. Install the release binaries (verified)

Install `faber`, `faber-box`, and `portitor` from their **v0.1.0 releases** —
signed archives, each verified with `ssh-keygen -Y verify` against the shared
release-signing key before anything runs. Do **not** build them from source. Each
tool's own `install.sh` performs the archive verification; you first verify
`install.sh` *itself* with the same key (its `install.sh.sig`), exactly as each
tool's README documents. faber's installer places **both** `faber` and
`faber-box` side by side in `INSTALL_DIR` (default `/usr/local/bin`) so faber's
"`faber-box` next to me" resolution works; portitor's installs `portitor`.

```fish
# The shared release-signing key (identical across portitor / faber / spex).
echo 'dvbozhko@gmail.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIhmCWVDP/Tcm3CqXNjTQTChbKxr223xMob9zc56Uuny' >/tmp/release-signers

for tool in portitor faber
    set -l base https://github.com/dmitriyb/$tool/releases/download/v0.1.0
    curl -fsSLO $base/install.sh; and curl -fsSLO $base/install.sh.sig
    ssh-keygen -Y verify -f /tmp/release-signers -I dvbozhko@gmail.com -n file \
        -s install.sh.sig <install.sh
    and env VERSION=v0.1.0 sh install.sh   # install.sh then verifies the archive(s) itself
    rm -f install.sh install.sh.sig
end
git -C "$DOT" pull   # re-stow if it advanced (see §0)
```

`faber-stack` runs the **installed** `portitor` binary host-side for `add-role`
(it picks the first real `portitor` on `PATH`); no `--portitor-bin` is needed
once the release is installed. The gate container image is built by faber-stack
from dot's own context (`~/.local/share/portitor/Dockerfile`), which fetches +
verifies the same release binary and bakes in `br` (the beads-close check runs it
inside the gate) — so no portitor checkout is needed at all.

---

## 2. Build the box image

`faber validate` runs the package-resolution proof first (the toolset-image risk
point); `faber build` then produces the box image. Sanity-check the toolset
resolves inside the built image (replace the tag with the one `faber build`
printed).

```fish
cd "$PROJECT"
faber validate --config orchestrator.yaml
faber build    --config orchestrator.yaml
docker run --rm faber/implement:<toolset-hash> sh -lc 'spex --help >/dev/null && br --version && claude --version'
```

---

## 3. Create the role keys

Three distinct keypairs — implementer, reviewer, merger — so portitor can tell
them apart by fingerprint. YubiKey resident + no-touch, so autonomous boxes sign
without a prompt. Register each pubkey on GitHub as a *Signing Key* separately.
Skip any role whose key you already have.

```fish
for role in implementer reviewer merger
    ssh-keygen -t ed25519-sk -O resident -O no-touch-required \
        -O application=ssh:$INSTANCE-$role -N "" -C "$INSTANCE-$role" \
        -f ~/.ssh/{$INSTANCE}_$role
end
```

If the resident credentials already exist on the YubiKey but this host has no
handle files, recover the handles straight into `~/.ssh` instead (PIN + touch;
`ssh-keygen -K` downloads *every* resident credential into the cwd — filenames
don't matter, tools match by fingerprint). The **`.pub` file must land in
`~/.ssh`** so `role-keys` emits a `pub` path — `faber-stack` requires one for
every role (it feeds both `AGENT_AUTHORIZED_KEY` and, for signers,
`allowed_signers`).

```fish
cd ~/.ssh
ssh-keygen -K -N ""
```

---

## 4. Register the roles with faber

`role-keys` enumerates your keys, you name each, and it applies `faber add-key`
locally (the global role→fingerprint registry faber resolves identities against).
Confirm `orchestrator.yaml`'s three identities are empty registry entries (`{}`)
so faber looks each up by name.

```fish
role-keys --apply
```

The identities block should read:

```yaml
identities:
  implementer: {}
  reviewer:    {}
  merger:      {}
```

`faber-stack` consumes the **same** role material as `role-keys --json` on stdin
(step 6) — you do not transcribe the `portitor add-role` lines by hand any more.

---

## 5. Store the scoped PAT

One keychain entry per instance — a Contents+PR token scoped to just this repo.
Never share a PAT across repos. `faber-stack` reads it by `--pat $PAT` and hands
it to the gate **only** as a docker file-secret (`/run/secrets/gh_token`) — never
on argv, never a container env var, so `docker inspect` never reveals it.

```fish
security add-generic-password -s $PAT -a default -w '<CONTENTS+PR PAT>'
```

---

## 6. Bring up the gate stack — one command

The heart of the runbook. Pipe `role-keys --json` into `faber-stack up`. It
validates the inputs, seeds the portitor config and builds the roles **host-side**
(the `:ro` config mount must be complete before boot), writes the per-instance
egress allow-list, brings up `portitor-$INSTANCE` + `$INSTANCE-egress` on
`$INSTANCE-net`, mirrors the repo **in the container**, pins the gate host key
into `$PROJECT/keys/`, and prints the orchestrator substrate it satisfies.
Idempotent — re-run any time; it converges, never duplicating roles, mirrors, or
filter lines.

```fish
role-keys --json \
    | faber-stack up --instance $INSTANCE --slug $SLUG --pat $PAT --project $PROJECT
```

On the first `up`, faber-stack builds the gate image from dot's context
(`~/.local/share/portitor/`): it fetches + SSHSIG-verifies the portitor v0.1.0
release binary and bakes in `br` for the beads-close check (needs network for
that one build; cached afterwards). Host-side `add-role` uses the **installed**
release `portitor` binary. Add `--allow <host>` (repeatable) to widen the egress
allow-list beyond the default `api.anthropic.com`; add `--map <portitor-role>=<name>`
if your registry names a role differently (e.g. `--map implementer=implementer_work`).

Verify the printed substrate matches `orchestrator.yaml` — `network.name`,
`network.proxy`, `remote.url`, `no_proxy`, and that
`keys/portitor_host_key.pub` now exists.

```fish
cat "$PROJECT/keys/portitor_host_key.pub"
```

---

## 7. Test the agent

Everything the box needs — including the `portitor` client (`portitor pr …`) the
steps use to talk to the gate (the box holds no GitHub credential; the client
forwards each PR action over the same pinned SSH channel git uses) — was baked
into the image by the step-2 build, and the gate is up from step 6.
Run one bead through the full **Gate B** chain (implement → review loop →
auto-merge). Pick a ready bead first.

```fish
cd "$PROJECT"
br ready
faber run bead --config orchestrator.yaml --param bead=<bead-id>
```

For a human-reviewed epic instead (fan-out, no auto-merge):

```fish
faber run epic --config orchestrator.yaml --param epic=<epic-id>
```

---

## 8. Lifecycle

`status`/`down` need only `--instance` (no slug/pat/project/stdin); `restart`
takes the same inputs as `up`, roles on stdin exactly as in step 6. `down` keeps
the `$INSTANCE-repos` mirror volume, so a later `up` is instant.

```fish
faber-stack status --instance $INSTANCE
faber-stack down   --instance $INSTANCE
role-keys --json \
    | faber-stack restart --instance $INSTANCE --slug $SLUG --pat $PAT --project $PROJECT
```

---

## What each step unlocks

```text
1–2  release binaries + box image         → the FULL toolset, portitor client included
3–5  role keys + registry + scoped PAT   → the inputs faber-stack consumes
6    faber-stack up                      → gate + egress + net + mirror + host-key, one command
7    faber run                           → full Gate B (implement → review loop → merge)
```
