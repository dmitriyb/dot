# base — the shared faber component library

One copy of the pieces every project in this tree runs. `spexmachina`,
`faber-stack-service` and both `-li` variants pull these in with
`include: [../base/images.yaml, ../base/skills.yaml, ../base/hooks.yaml]`.

Editing anything here edits every project. That is the point: these files
diverged once — `spexmachina` grew bead-id spec resolution and removed-node
cleanup cycles while `faber-stack-service` kept resolving by the retired
`spex:` label, which resolves nothing and produced cycles that implemented
blind. Divergence was possible because there were two copies; now there is one.

```
images.yaml    spex-box — pinned toolset (nixos-25.11 / Go 1.25.10) + overlay
overlay.nix    claude-code + spex + br derivations (real, verified hashes)
skills.yaml    implement / review / fix / merge / go-expert  → skills/<name>/
hooks.yaml     one entry per hook executable                 → hooks/<name>
skills/        the SKILL.md trees — judgement only; the box owns the ceremony
hooks/         the hook executables (context → prelude → agent → postlude)
```

## What is NOT here, and why

Two libraries stay with each project because they carry a project fact that
faber has no way to parameterise:

- **`templates.yaml`** — every entry's `run.env` carries `PORTITOR_HOST`, the
  gate container this instance talks to. `run.env` is a plain string map; the
  only interpolation faber has (`${params...}`, `${steps...}`) is confined to a
  workflow's `with:` bindings. So the value cannot come from the substrate today.
- **`workflows.yaml`** — its `repo` param default names the project's repo, and
  `faber-epic` relies on that default (it passes only `--param epic=`;
  `faber-e2e` does pass `--param repo=`). A shared default would point one
  project at another's repository.

Both are one-line facts wearing a whole file. The fixes are known: a network
alias so `PORTITOR_HOST` is a constant (or a substrate-level `env:` in faber),
and `faber-epic` passing `--param repo` from `stack.json`'s `slug`.

## Assembly rules worth knowing before editing

- `include:` **union-merges** the named libraries; paths resolve relative to the
  file that declares them, so `../base/...` works from anywhere in this tree.
- A duplicate library key across two included files is a **validation error**,
  not an override. There is no layering — a project can only add disjoint keys,
  never replace one of these. To vary a role (as the `-li` projects do for
  `implement`), the varying entry must live in a file the project includes
  *instead of* the shared one, under the same key.
- `faber validate` checks that hook and skill NAMES resolve. It does **not**
  check that the files behind them exist — a renamed hook file passes validation
  and fails in the box.
