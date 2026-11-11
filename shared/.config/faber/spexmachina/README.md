# spexmachina faber project

Runs spexmachina development through faber boxes: implement / review / fix / merge,
gated by portitor. Built on the **component-library** config model — the substrate
plus five reusable named libraries (`images`, `skills`, `hooks`, `templates`,
`workflows`), assembled by `orchestrator.yaml` via `include:`.

## Layout

```
orchestrator.yaml   project assembly: substrate (network/remote/credentials/identities) + include
templates.yaml      implement / review / fix / merge  (named refs into the libraries)
                    — project-owned because each entry carries PORTITOR_HOST, this
                    instance's gate container
workflows.yaml      bead (auto-merge chain) / epic (the same chain per child, sequential)
                    — project-owned because its `repo` param default names this repo
portitor/           the declarative gate policy, its predicate scripts, and the gate's
                    extra tools (gate-image.json → gate-overlay.nix; see below)
stack.example.json  the instance manifest faber-stack reads (copy to the gitignored stack.json)
keys/               the gate's host-key pin, written by portitor deploy (see keys/README.md)

../base/            the SHARED library — ONE copy for every project in this tree:
  images.yaml       spex-box — pinned toolset (nixos-25.11 / Go 1.25.10) + overlay
  overlay.nix       claude-code + spex + br derivations (real, verified hashes)
  skills.yaml       implement / review / fix / merge / go-expert  → skills/<name>/
  hooks.yaml        gather-context / claim-bead / next-bead-context / claim-next-bead /
                    fetch-pr / reopen-bead / wait-checks / post-* / finish-implement /
                    release-bead → hooks/<name>
  skills/           the SKILL.md trees
  hooks/            the hook executables (context runs before prelude; cwd = the clone)
```

## Two overlays, two sets of versions

The boxes and the gate are built from **different overlays**, and each carries its own tool
versions:

- `../base/overlay.nix` — the boxes' tools (claude-code, spex, br, the portitor client), built
  by `faber build`.
- `portitor/gate-overlay.nix` — the gate's tools (br only), named by
  `portitor/gate-image.json` and built by `portitor deploy`.

They are independent on purpose: bumping a box tool never rebuilds or swaps the gate, and
the gate's br moves only when its own file changes. Neither file reads the other (faber and
portitor each stage an overlay alone), so a br bump meant for both is two edits.

## The gate policy (`portitor/`)

`portitor/policy.json` is the **declarative** static gate policy — `action_roles`,
`merge_gate`, `content_rules`, `identity_only_roles`, `checks`, `default_branch`,
`require_up_to_date_with_default`. `faber-stack` builds `repos.d/<repo>.json` afresh from it
on every `up`, so a removed key never lingers, and the roles it grants are the roles the
gate registers. It is data: no shell lives in it.

`portitor/checks/` holds the shell **predicate scripts** `merge_gate.checks` refers to.
`faber-stack` installs them into the gate's config dir, which `portitor deploy` bakes into
the gate image at `/etc/portitor`, so a predicate is referenced as
`["/bin/sh", "/etc/portitor/checks/<name>.sh"]` and portitor appends the PR number and
head SHA as `$1` and `$2`. They are real files rather than shell embedded in JSON so they
can be linted, tested against a live mirror, and diffed. `faber-stack` fails at startup
if a policy references a script that is not there — a missing script would otherwise make
the command exit non-zero, which the gate reports as an ordinary "did not pass".

**Two things run shell inside the gate**, and the gate image is minimal — portitor's fixed
part (bash, coreutils, gawk, git, gh, openssh) plus `portitor/gate-image.json` (`br`), with
**no `grep`, `sed` or `jq`**:
`merge_gate.checks` predicates, and the `content_rules.semantic` check (which shells `br`).
Boxes are a different environment entirely and do have those tools.

`bead-closed` is the one predicate today: a PR may land if it **closed a bead** (counted
with `br` against the merge-base — only the reviewer may close one, so a closed bead is
proof a reviewer signed off) **or** if it is **drift-only** (touches nothing outside
`drifts/` and `.beads/`). The second branch exists because the blocking-drift protocol
requires landing a report with the bead left `open`. Producing that shape is the box's
job (see the `fix`/`implement` skills) — nothing normalises it automatically, so a drift
PR that still carries code is refused here and costs the cycle.

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
faber-stack up spexmachina          # images, gate config, egress, gate (../SETUP.md)
cd <this dir>
faber run bead --param bead=<id>
faber run epic --param epic=<epic-id>
```

## Status

- **Complete**: image (real hashes, incl. the in-box `pr`/`portitor` client), hooks, skills,
  templates, workflows, the assembly. `faber-stack up` (see `../SETUP.md`) builds the images and stands up the
  egress and the gate (roles, mirror, host-key pin).
- `bead` is the primary, proven shape — trial it on the Batch-B bugs first.
  `epic` is a pull-loop of that same chain (implement → review loop → auto-merge):
  each cycle's box selects the next ready epic bead from inside the clone
  (`next-bead-context`), lands it, and the loop settles on the first cycle that
  finds nothing ready — or that finds a blocking drift report in `drifts/` (the
  spec is disputed; `/drift-workflow` in the repo triages, then rerun the epic). Strictly sequential by construction — every merge advances
  main and the gate's stale-base rule rejects branches claimed off an older main.
