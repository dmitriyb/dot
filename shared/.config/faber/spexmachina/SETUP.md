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
`faber`/`faber-box`/`portitor` are installed from their verified releases
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

Install `faber`, `faber-box`, and `portitor` from their **latest signed
releases** — signed archives, each verified with `ssh-keygen -Y verify` against
the shared release-signing key before anything runs. Do **not** build them from
source. Each tool's own `install.sh` resolves the latest release and performs the
archive verification; you first verify `install.sh` *itself* with the same key
(its `install.sh.sig`), exactly as each tool's README documents. faber's installer
places **both** `faber` and `faber-box` side by side in `INSTALL_DIR` (default
`/usr/local/bin`) so faber's "`faber-box` next to me" resolution works; portitor's
installs `portitor`. This is the same install each README documents — run it by
hand if you prefer; the block below is the verified one-shot.

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
git -C "$DOT" pull   # re-stow if it advanced (see §0)
```

`faber-stack` runs the **installed** `portitor` binary host-side for `add-role`
(it picks the first real `portitor` on `PATH`); no `--portitor-bin` is needed
once the release is installed. The gate container image is built by faber-stack
from dot's own context (`~/.local/share/portitor/Dockerfile`), which fetches +
verifies the latest release binary and bakes in `br` (the beads-close check runs
it inside the gate) — so no portitor checkout is needed at all.

**Updating later:** `faber upgrade` moves `faber` + `faber-box` forward as a unit
(they share a contract version); re-run portitor's `install.sh` (above) to move
`portitor`. The gate image is cached, so to rebuild it against a newer portitor,
drop it — `docker rmi portitor` — and faber-stack rebuilds it on the next `up`.

**Version floor for this config:** the review/fix postludes need a faber
release with the postlude phase (> 0.1.5; older faber silently ignores the
`postlude:` keys — the hooks simply don't run), and the gate policy in
`$PROJECT/portitor/policy.json` (transparent-approve: `merge_gate.review:none`
+ a `bead-closed` check, no `reviews_log`) needs a portitor release with
merge-gate v2 transparent-approve (>= 0.1.5; an OLDER gate binary strict-refuses
`review:none`/`checks` — or the retired `review:internal`/`reviews_log` — at
boot, so run `docker rmi portitor` and the next `up` in one step — the policy
and the new image land together).

### macOS host notes (skip on Linux)

Two Docker-Desktop quirks need one explicit file, `~/.config/faber/host.json`
(faber's per-machine config; strict-decoded, no environment involved):

- the VM presents faber's forwarded agent socket as root-owned, so the box's
  dropped user needs group-0 membership (`--group-add`; membership, not root
  powers) — `agent_socket_group`;
- the VM does not share `/usr/local`, so the default faber-box mount silently
  becomes an empty directory — keep a real COPY under `~` (a symlink resolves
  back to the unshared path) and point `box_bin` at it. Refresh the copy after
  every `faber upgrade`.

```fish
mkdir -p ~/.local/libexec
install /usr/local/bin/faber-box ~/.local/libexec/faber-box
printf '{"agent_socket_group":"0","box_bin":"%s"}\n' ~/.local/libexec/faber-box \
    > ~/.config/faber/host.json
```

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

Day-to-day you can skip this step: `faber-stack up --build` (§6) runs
validate + build for you before bringing the gate up.

---

## 3. Create the role keys

Three distinct keypairs — implementer, reviewer, merger — so portitor can tell
them apart by fingerprint. YubiKey resident + no-touch, so autonomous boxes sign
without a prompt. Register each pubkey on GitHub as a *Signing Key* separately.
Skip any role whose key you already have.

A registered key alone is not enough for the green **Verified** badge: GitHub
also requires the commit's *committer email* to be a verified email on the
account that owns the key. That email is **role-registry state** — registered
with the key binding via `faber add-key --git-email` (step 4); faber reads no
configuration from the process environment, and a template's `env:` block
cannot carry it either (the `FABER_` namespace is engine-owned). Without it
every commit shows **Unverified** (`reason: no_user`) despite a valid
signature; gated steps refuse to start instead of committing as an
unverifiable synthetic address. The gate's own signature check is key-based
and unaffected either way.

```fish
for role in implementer reviewer merger
    ssh-keygen -t ed25519-sk -O resident -O no-touch-required \
        -O application=ssh:$INSTANCE-$role -N "" -C "$INSTANCE-$role" \
        -f ~/.ssh/{$INSTANCE}_$role
end
```

If the resident credentials already exist on the YubiKey but this host has no
handle files, recover them with `restore-role-keys` (stowed from dot to
`~/.local/bin`; PIN + one touch). Do **not** use raw `ssh-keygen -K`: it stamps
every downloaded handle "user presence required" regardless of the no-touch
policy the credentials were created with (a stock-OpenSSH limitation), and the
boxes' autonomous signing then dies with "agent refused operation".
`restore-role-keys` downloads and restores the client-side no-touch flag in one
step, installs handle + `.pub` into `~/.ssh`, and verifies with a touch-free
test signature. The **`.pub` file must land in `~/.ssh`** so `role-keys` emits
a `pub` path — `faber-stack` requires one for every role (it feeds both
`AGENT_AUTHORIZED_KEY` and, for signers, `allowed_signers`).

```fish
restore-role-keys
```

---

## 4. Register the roles with faber

`role-keys` enumerates your keys, you name each, and it applies `faber add-key`
locally (the global role→fingerprint registry faber resolves identities against).
`--git-email` registers the committer email with every role — required before
any gated step runs (see step 3). Confirm `orchestrator.yaml`'s three
identities are empty registry entries (`{}`) so faber looks each up by name.

```fish
role-keys --apply --git-email <verified-account-email>
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
(the `:ro` config mount must be complete before boot). The **static gate policy**
— `action_roles` / `merge_gate` / `content_rules` / `identity_only_roles` — comes
from the declarative `$PROJECT/portitor/policy.json` (override with `--policy`);
faber-stack overlays only the computed fields (roles map, signer path, slug,
committer emails). It also writes the per-instance
egress allow-list, brings up `portitor-$INSTANCE` + `$INSTANCE-egress` on
`$INSTANCE-net`, mirrors the repo **in the container**, pins the gate host key
into `$PROJECT/keys/`, and prints the orchestrator substrate it satisfies.
Idempotent — re-run any time; it converges, never duplicating roles, mirrors, or
filter lines.

The two `--allow` entries widen the egress allow-list beyond the default
`api.anthropic.com`: implement/fix boxes run `go build`/`go test` on a fresh
clone, so the Go module proxy and checksum db must be reachable. The allow-list
is CONVERGED on every `up` — flags omitted from a later run are dropped again —
so always run the command with the full set.

The `--commit-email` entry seeds the gate's `allowed_committer_emails` policy:
portitor rejects any pushed commit whose committer email isn't listed, closing
the gap where a box whose role has a misregistered committer email would land
commits GitHub can never verify. Like `--allow`, it is CONVERGED on every `up` — omit
it and the field (and check) is dropped again. It needs a portitor release
that knows the key (an older gate binary refuses a config carrying it).

```fish
role-keys --json \
    | faber-stack up --instance $INSTANCE --slug $SLUG --pat $PAT --project $PROJECT \
        --allow proxy.golang.org --allow sum.golang.org \
        --commit-email dvbozhko@gmail.com \
        --build
```

`--build` folds step 2 in: `faber validate` + `faber build` run first (against
the absolute `$PROJECT/orchestrator.yaml`), so this one command yields images
plus gate and the only thing left is `faber run`.

On the first `up`, faber-stack builds the gate image from dot's context
(`~/.local/share/portitor/`): it fetches + SSHSIG-verifies the latest portitor
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

Pass the config by **absolute path**: with a relative `--config`, faber
resolves the library paths (hooks, skills) relative to the process CWD and
every gated box dies at docker's bind-mount guard ("host path is relative").

```fish
cd "$PROJECT"
br ready
faber run bead --config "$PROJECT/orchestrator.yaml" --param bead=<bead-id>
```

For an epic, the same full chain runs as a pull-loop, one cycle at a time:
each cycle's box picks the next ready epic bead from inside the clone (br in
the image; the host needs no br), lands it, and the loop ends on the first
cycle that finds nothing ready. Sequential landing is also correctness —
every merge advances main and the gate's stale-base rule rejects branches
claimed off an older main. A failed cycle fail-stops the epic after the
already-landed beads; `faber resume` continues — run `portitor-branch clear` (alias `pbr`) first to
drop the failed cycle's stale mirror branch.

```fish
faber run epic --config "$PROJECT/orchestrator.yaml" --param epic=<epic-id>
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
    | faber-stack restart --instance $INSTANCE --slug $SLUG --pat $PAT --project $PROJECT \
        --allow proxy.golang.org --allow sum.golang.org \
        --commit-email dvbozhko@gmail.com
```

---

## What each step unlocks

```text
1–2  release binaries + box image         → the FULL toolset, portitor client included
3–5  role keys + registry + scoped PAT   → the inputs faber-stack consumes
6    faber-stack up                      → gate + egress + net + mirror + host-key, one command
7    faber run                           → full Gate B (implement → review loop → merge)
```
