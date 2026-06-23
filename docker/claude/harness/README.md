# Agent harness (container ground base)

Enforcement scaffolding baked into the Docker Claude images. Part of the larger plan
(see the design doc); this directory is **Phase 0** — the lean, usable floor.

## Files

- **`managed-settings.base.json`** — Claude Code *managed* settings, installed **root-owned**
  at `/etc/claude-code/managed-settings.json` in `Dockerfile.base`. Managed settings are the
  **highest precedence** layer — the agent (running as `dev`) cannot override or edit them.
  Baseline = **honest-path anti-bypass** deny rules (block the obvious `--no-gpg-sign`,
  `--no-verify`, `core.hooksPath` overrides). Inherited by the personal and (future) agent images.

- **`managed-settings.work.json`** — **overlay** copied over the base file in `Dockerfile.work`
  (managed settings are a single file, so this is a **superset**, not a merge). The **dcw
  lockdown**: the agent may edit/read/build/test but **must not commit or push** — you do those
  yourself. Covers every commit-creating porcelain (`commit`/`merge`/`rebase`/`cherry-pick`/
  `revert`/`am`) plus `push`. Backstopped by the touch key (anything that slips still needs a
  physical touch).

## Important: these are NOT the wall

The deny rules are positional command-string globs — **defeatable** (git plumbing, libgit2,
REST, shell obfuscation). They stop the *casual/accidental* bypass and give immediate value, but
the **real, unbypassable enforcement is the `portitor` proxy** (a later phase) which inspects the
*result* server-side, plus GitHub branch protection / `require signed commits` for hosted repos.
Treat this layer as honest-path fast feedback, not a guarantee.

## Precedence note

`/etc/claude-code/managed-settings.json` outranks user (`~/.claude/settings.json`) and project
(`.claude/settings.json`) settings, and a managed `deny` holds even under
`--dangerously-skip-permissions` / bypass mode. Because the file is root-owned and `dev` can't
write it, the agent cannot disable these in-session.
