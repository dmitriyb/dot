# faber-stack-service faber project (playground / acceptance)

The **acceptance playground** for the faber → portitor stack. It runs the
disposable repo [`dvb-service/faber-stack-service`](https://github.com/dvb-service/faber-stack-service)
through the same box chain spexmachina uses — implement / review / fix / merge —
so the whole gate stack can be exercised end to end on cheap, throwaway work
before it is trusted with a real repo.

It is a near-byte copy of the `spexmachina` project dir: the image, hooks,
skills, templates, and workflows are **identical on purpose** (same toolset hash
⇒ the already-built `faber/*:<hash>` images are reused, no rebuild). Only three
things differ, all minimal:

- **`orchestrator.yaml`** substrate points at this instance: network `faber-stack-service-net`,
  egress `http://faber-stack-service-egress:8888`, gate `portitor-faber-stack-service`, remote
  `ssh://git@portitor-faber-stack-service/srv/git`.
- **`templates.yaml`** sets `PORTITOR_HOST: portitor-faber-stack-service` in every template env.
- **`workflows.yaml`** defaults the `repo` param to `faber-stack-service`.

## How it maps to the faber-stack-service instance

One knob — `--instance faber-stack-service` — derives every object name, so the box side and the
gate side agree by construction:

```text
--instance faber-stack-service  ⇒  network faber-stack-service-net · egress faber-stack-service-egress · gate portitor-faber-stack-service · volume faber-stack-service-repos · project faber-stack-service
```

- slug `dvb-service/faber-stack-service`, PAT keychain service `service-bot` (account `dvb-service`);
- the upstream repo carries the seed spec + beads and the `playground-seed` tag
  (the reset anchor);
- the epic is `mt-oxm` with children `mt-oxm.1` (Mul), `mt-oxm.2` (Add),
  `mt-oxm.3` (Sub) — one trivial single-function bead each.

## Layout

```
orchestrator.yaml   substrate (faber-stack-service-net / faber-stack-service-egress / portitor-faber-stack-service) + include
images.yaml         spex-box — IDENTICAL to spexmachina (toolset hash reuse)
overlay.nix         claude-code + spex + br derivations — IDENTICAL to spexmachina
hooks.yaml/hooks/    gather-context / claim-bead / … — verbatim (project-agnostic)
skills.yaml/skills/  implement / review / fix / merge / go-expert — verbatim
templates.yaml      IDENTICAL except PORTITOR_HOST: portitor-faber-stack-service
workflows.yaml      IDENTICAL except repo default = faber-stack-service
keys/               host-key pin lands here at `faber-stack up` (see keys/README.md)
```

## Run

The scenario driver `faber-e2e` (stowed to `~/.local/bin`) wires the defaults:

```bash
faber-e2e reset          # restore main to playground-seed; converge the gate
faber-e2e run            # faber-stack up + faber run epic  (COSTS real agent usage)
faber-e2e assert         # verify every child bead's PR merged, commits verified, …
faber-e2e full           # reset → run → assert
```

Or drive faber directly (absolute --config is mandatory — a relative one makes
faber resolve hook/skill paths against the CWD and every gated box dies at
docker's bind-mount guard):

```bash
faber validate --config "$PWD/orchestrator.yaml"
faber run epic --config "$PWD/orchestrator.yaml" --param epic=mt-oxm
```
