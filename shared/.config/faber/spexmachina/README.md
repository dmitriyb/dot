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
hooks.yaml          gather-context / claim-bead / fetch-pr / release-bead / list-epic-beads → hooks/<name>
templates.yaml      implement / review / fix / merge  (named refs into the libraries)
workflows.yaml      bead (Gate B, auto-merge) / epic (Gate A, human-landed)
overlay.nix         claude-code + spex + br derivations (real hashes; br x86_64 hash TODO)
skills/             the SKILL.md trees (ported from dot's dca pipeline)
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

- **Complete**: image (real hashes), hooks, skills, templates, workflows, the assembly.
- **Portitor step (remaining, by design)**: role keys + portitor host key in `keys/`, the
  portitor/`pr` client on the box PATH, repo onboarding + role rules. Only the review/fix/merge
  legs depend on it; the implement leg and the config structure do not. See `keys/README.md`.
- Gate B (`bead`) is the primary, proven shape — trial it on the Batch-B bugs first.
  Gate A (`epic`) fans implement over an epic's children with no auto-merge; its single-big-PR
  refinement waits on a faber aggregate step (noted in `workflows.yaml`).
