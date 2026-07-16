# spexmachina pipeline — host setup

End-to-end setup to run spexmachina development through the spex → faber →
portitor gate. Each step is an explanation block followed by a command block.
Run the commands on your host (faber-on-host). `< … >` marks a value you supply.

Fill these once; the blocks below reference them.

```bash
export FABER=~/src/faber                 # faber repo checkout (branch impl/v0.1)
export PORTITOR=~/src/portitor           # portitor repo checkout
export DOT=~/dot                         # dot repo checkout (branch faber-spexmachina-config)
export SPEX_PROJ="$DOT/docker/claude/faber/spexmachina"   # this project dir
```

---

## 0. Prerequisites (already in place from the smoke)

The gateless smoke already established these; verify, don't redo. The Anthropic
setup-token lives in the keychain; docker + nix are on the host.

```bash
security find-generic-password -s anthropic -a personal -w >/dev/null && echo "anthropic token OK"
docker info >/dev/null && nix --version
```

---

## 1. Pull + rebuild the binaries

Pull all three repos, then build the two faber binaries. `faber` runs on the
host; `faber-box` runs inside the linux container, so it is cross-compiled for
linux. Merge the portitor PR first (or pull its branch) so the gate has
`add-role`.

```bash
git -C "$FABER" pull
git -C "$DOT" pull
git -C "$PORTITOR" fetch origin && git -C "$PORTITOR" checkout feat/add-role && git -C "$PORTITOR" pull
cd "$FABER"
go build -o bin/faber ./cmd/faber
CGO_ENABLED=0 GOOS=linux go build -o bin/faber-box ./cmd/faber-box
```

---

## 2. Build the `spex-box` image

The first real nix build of spex/br/claude-code under the 25.11 pin, loaded into
the docker daemon. This is the toolset-image risk point — nothing before it
exercises the overlay build. `validate` runs the package-resolution proof first.

```bash
export PATH="$FABER/bin:$PATH"
cd "$SPEX_PROJ"
faber validate --config orchestrator.yaml
faber build    --config orchestrator.yaml
```

Sanity-check the toolset resolves inside the built image before wiring anything
(replace the tag with the one `faber build` printed).

```bash
docker run --rm faber/implement:<toolset-hash> sh -lc 'spex --help >/dev/null && br --version && claude --version'
```

---

## 3. Create the role keys

Three distinct keypairs — implementer, reviewer, merger — so portitor can tell
them apart by fingerprint. YubiKey resident + no-touch (autonomous boxes sign
without a prompt). Skip any role whose key you already have. Register each
pubkey on GitHub as a *Signing Key* separately.

```bash
for role in implementer reviewer merger; do
  ssh-keygen -t ed25519-sk -O resident -O no-touch-required \
    -O application=ssh:spexmachina-$role -N "" -C "spexmachina-$role" \
    -f ~/.ssh/spexmachina_$role
done
```

---

## 4. Register the roles + reconcile the config

`role-keys` enumerates your keys, you name each, and it applies `faber add-key`
locally (the global role→fingerprint registry) and prints the `portitor
add-role` lines for step 5. Keep the printed lines.

```bash
role-keys --repo spexmachina --apply
```

The committed `orchestrator.yaml` still uses the old path form
(`identities.<role>.key: ./keys/<role>`). Switch the three identities to
registry resolution — drop the `key:` paths so faber looks each role up by name
in the registry you just populated. Leave `remote.host_key_file` alone (step 5
fills it). Result:

Each role is then resolved by name via the registry (`faber add-key --role implementer …`).

```yaml
identities:
  implementer: {}
  reviewer:    {}
  merger:      {}
```

---

## 5. Bring up portitor + onboard spexmachina

One portitor instance per repo, holding this repo's own scoped PAT (never share
a PAT across repos). Store the PAT, bring up the instance on `dca-net`, create
the bare mirror, bind the roles (the lines from step 4), and pin the host key.

```bash
security add-generic-password -s portitor -a default -w '<CONTENTS+PR PAT>'
docker-claude --portitor up
docker exec -u git portitor portitor add-repo --repo spexmachina \
  --upstream https://github.com/dmitriyb/spexmachina.git
```

Run the `portitor add-role` lines role-keys printed (once per role), against the
running instance. The reviewer/implementer get `--pub` (signing → allowed_signers);
merger is identity-only.

```bash
docker exec portitor portitor add-role --repo spexmachina --role implementer --fingerprint <SHA256:…> --pub /etc/portitor/keys/implementer.pub
docker exec portitor portitor add-role --repo spexmachina --role reviewer    --fingerprint <SHA256:…> --pub /etc/portitor/keys/reviewer.pub
docker exec portitor portitor add-role --repo spexmachina --role merger      --fingerprint <SHA256:…>
```

Add the bead-close role rule (only reviewer/owner may add `"status":"closed"` to
`.beads/issues.jsonl`), then pin portitor's SSH host key for faber's
`remote.host_key_file` (run where the `portitor` hostname resolves — inside
`dca-net`).

```bash
ssh-keyscan -t ed25519 portitor > "$SPEX_PROJ/keys/portitor_host_key.pub"
docker exec portitor portitor validate-config --config /etc/portitor/repos.d/spexmachina.json
```

---

## 6. Deliver the portitor/pr client into the box (needed past implement)

The `fetch-pr` / `review` / `fix` / `merge` legs call the `pr` / `portitor`
client inside the box; the `implement` leg does not (it just `git push`es). Add
the client to the `spex-box` overlay (or ship it as a hook-delivered script) so
`command -v pr` succeeds in the box. After editing `overlay.nix`, rebuild the image.

```bash
faber build --config orchestrator.yaml
```

---

## 7. Test the agent

Pick a ready bead. Test the **implement** leg first — it exercises image → box →
clone from portitor → `spex map context` → signed claim → real Claude → push →
gate accepts → PR, without needing the pr-client from step 6. Pick a bead id
with `br ready` or `bv --robot-next`.

```bash
cd "$SPEX_PROJ"
br ready
faber run bead --config orchestrator.yaml --param bead=<bead-id>
```

Once step 6 is done, the same command runs the full **Gate B** chain
(implement → review loop → auto-merge). For a human-reviewed epic instead:

```bash
faber run epic --config orchestrator.yaml --param epic=<epic-id>
```

---

## What each step unlocks

```text
1–2  binaries + spex-box image        → gateless image sanity (tools resolve)
3–4  role keys + registry + config    → faber can resolve identities
5    portitor up + onboarded          → boxes clone/push through the gate
6    pr-client in the box             → review / fix / merge legs
7    implement leg testable after 5;  full Gate B testable after 6
```
