# spexmachina faber project

Runs spexmachina development through faber boxes: implement / review / fix / merge,
gated by portitor. Built on the **component-library** config model — the substrate
plus five reusable named libraries (`images`, `skills`, `hooks`, `templates`,
`workflows`), assembled by `orchestrator.yaml` via `include:`.

## Layout

```
orchestrator.yaml   project assembly: substrate (network/remote/credentials/identities) + include
images.yaml         spex-box — pinned toolset (nixos-25.11 / Go 1.25.10) + overlay
skills.yaml         implement / review / fix / merge / go-expert  → skills/<name>/
hooks.yaml          gather-context / claim-bead / next-bead-context / claim-next-bead / fetch-pr / release-bead → hooks/<name>
templates.yaml      implement / review / fix / merge  (named refs into the libraries)
workflows.yaml      bead (auto-merge chain) / epic (the same chain per child, sequential)
overlay.nix         claude-code + spex + br derivations (real, verified hashes)
skills/             the SKILL.md trees (implement / review / fix / merge / go-expert)
hooks/              the hook executables (context runs before prelude; cwd = the clone)
keys/               role + gateway keys — filled at the portitor step (see keys/README.md)
```

## The box contract this project targets

- Phase order: clone → signing → **context** hook → **prelude** hook → agent → result.
  `gather-context` (read-only, resolves spec) runs *before* `claim-bead` (branch + signed claim).
- Hooks run **in the box**, cwd = the repo clone (`/workspace/<repo>`), `/bin/bash`, nix-image tools.
- Inputs arrive as `FABER_INPUT_<UPPER>`; context/prelude write `$FABER_BUNDLE_DIR/{CONTEXT.md,bundle.env}`;
  `BRANCH` in `bundle.env` is the declared side-effect.
- Each skill's last act writes `$FABER_RESULT_DIR/output.json` with its declared `output:` fields —
  that JSON is how faber scores the step and feeds `${steps.<id>.<field>}` onward.

## Run

```bash
cd <this dir>
faber validate --config orchestrator.yaml [--emit-ir]
faber build    --config orchestrator.yaml
faber run bead --config orchestrator.yaml --param bead=<id>
faber run epic --config orchestrator.yaml --param epic=<epic-id>
```

## Status

- **Complete**: image (real hashes, incl. the in-box `pr`/`portitor` client), hooks, skills,
  templates, workflows, the assembly. `faber-stack up` (see `../SETUP.md`) stands up the gate:
  roles, mirror, host-key pin — everything `keys/README.md` describes.
- `bead` is the primary, proven shape — trial it on the Batch-B bugs first.
  `epic` is a pull-loop of that same chain (implement → review loop → auto-merge):
  each cycle's box selects the next ready epic bead from inside the clone
  (`next-bead-context`), lands it, and the loop settles on the first cycle that
  finds nothing ready — or that finds a blocking drift report in `drifts/` (the
  spec is disputed; `/drift-fix` in the repo triages, then rerun the epic). Strictly sequential by construction — every merge advances
  main and the gate's stale-base rule rejects branches claimed off an older main.
