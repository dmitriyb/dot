# Docker Claude Code

Isolated Claude Code environments running in Fedora containers with full dotfiles, SSH agent forwarding (YubiKey), and separate personal/work images.

## What's inside

**Base** (shared): Fish, tmux, neovim (with plugins), starship, eza, bat, fzf, zoxide, lazygit, direnv, glow, Nix (single-user, flakes enabled, with nix-direnv), [beads_rust](https://github.com/Dicklesworthstone/beads_rust), [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer), and Claude Code (native binary).

**Personal**: + Zig. No MCP servers. Fast startup.

**Work**: + Bun (for MCP servers), SSH server for IDEA Remote Development, timeout tuning for large repos. Repos live on a native ext4 volume (not VirtioFS) for performance.

## Setup

Store your personal OAuth token (from `claude setup-token`) in the OS keychain:

```bash
# macOS
security add-generic-password -s anthropic -a personal -w '<token>'

# Arch Linux
secret-tool store --label='anthropic' service anthropic account personal
```

Work account credentials are picked up automatically from the OS keychain (stored by `claude login`).

Optionally, store GitHub CLI tokens so `gh` works in-container without on-disk auth state:

```bash
# macOS
security add-generic-password -s gh -a personal -w '<PAT>'
security add-generic-password -s gh -a work     -w '<PAT>'

# Arch Linux
secret-tool store --label='gh personal' service gh account personal
secret-tool store --label='gh work'     service gh account work
```

Tokens are passed in as `GH_TOKEN` at container start. If absent, `gh` just stays unauthenticated — no error.

### Agent mode (no-touch commit signing)

`--agent` (personal only) forwards an ephemeral signing-only agent holding a single no-touch FIDO2 key, so agents inside the container can sign commits without touch prompts. Push/fetch use `GH_TOKEN` over HTTPS, so the key signs but can't authenticate as you.

One-time setup: enroll a resident no-touch key, register its **public** key on GitHub as a *Signing Key*, then record its hash so the scripts can find it without storing the name:

```bash
ssh-keygen -t ed25519-sk -O resident -O no-touch-required -O application=ssh:<name> -f /tmp/k && rm /tmp/k*
printf '%s' '<name>' | sha256sum   # add the digest to ~/.ssh/signing-key-hashes
```

Load your normal (touch) keys into the main agent with `ssh-load-keys`, which excludes any no-touch key listed in `~/.ssh/signing-key-hashes`.

## Usage

`docker-claude` is the single entrypoint; everything is a subcommand.

```bash
docker-claude personal             # Personal account (Max subscription via OAuth)
docker-claude personal --agent     # Personal, agent mode: ephemeral no-touch signing agent
docker-claude work                 # Work account (via wire proxy, default)
docker-claude direct               # Work account (direct API key from keychain)
docker-claude personal -r          # Rebuild images, then launch personal
docker-claude personal --no-cache  # Full fresh rebuild (re-downloads everything)
docker-claude personal --workspace ~/projects  # Custom workspace mount (personal only)
docker-claude dca  …               # one-shot autonomous agent task (payload)
docker-claude dce  …               # whole-epic orchestration (payload)
docker-claude warm …               # warm the offline Go module cache (payload)
docker-claude portitor up          # bring up the shared portitor + egress proxy
```

Aliases: `dc` (docker-claude), `dcp` (personal), `dcw` (work), `dcwd` (direct),
`dca` (dca), `dce` (dce), `dcwarm` (warm). The agent payloads (`dca`/`dce`/`dca-warm`)
live off PATH in `~/.local/libexec/docker-claude/` and are reached only through
`docker-claude` (or these aliases).

## Autonomous agent runner (dca / dce)

Distinct from the interactive cockpit above: `docker-claude dca` runs ONE headless,
egress-locked agent task per container; `docker-claude dce` orchestrates a whole epic
as a phase loop over `dca`. They build their own lean per-stack images
(`claude-dev-agent-base` + `claude-dev-agent-<stack>`) on demand. Run
`docker-claude dca --help`, `… dce --help`, `… warm --help` for full flags.
Prerequisite for both: bring up the shared proxy with `docker-claude portitor up`
(needs a GitHub PAT — keychain service `portitor`, account `default`). First-time
setup: point docker-claude at your portitor checkout once with
`docker-claude portitor init --repo <path-to-portitor> [--config-dir <path>]`
— this persists the paths to `~/.config/docker-claude/portitor.env` so later `up`/`restart`
need no `PORTITOR_REPO` env var. The go stack also needs a one-time
`docker-claude warm --repo <name>` to populate the offline module-cache volume.

### Adding a stack (rust, zig)

The **image side is already generic**: `dca`/`dca-warm` derive the image name
`claude-dev-agent-$STACK` and only need a `docker/claude/Dockerfile.agent.$STACK`
to exist. A new stack file mirrors `Dockerfile.agent.go`:

```dockerfile
ARG AGENT_BASE=claude-dev-agent-base
FROM ${AGENT_BASE}
USER root
RUN dnf install -y --setopt=install_weak_deps=False <toolchain> && dnf clean all
USER dev
RUN <smoke-test>          # rustc --version  /  zig version
WORKDIR /workspace
CMD ["/bin/bash"]
```

The **offline-cache side is NOT generic** — it's Go-only today: `dca-warm` rejects
non-go stacks, and the cache mount in `dca` is gated on `STACK == go` (so the
egress-locked run never reaches a module proxy). Each stack needs its own model:

- **Rust:** a `CARGO_HOME` volume; warm with `cargo fetch`; run with `CARGO_NET_OFFLINE=true`.
- **Zig:** a `ZIG_GLOBAL_CACHE_DIR` volume; warm with `zig build --fetch`.

Implementing a stack = add the Dockerfile above, then generalize the `STACK == go`
branches in `dca` (the cache mount + env) and `dca-warm` into a `case "$STACK"`.

## Trust model (where the boundary actually is)

Two layers, and only one of them is a security boundary:

- **Managed-settings (in-container guardrails)** — `harness/managed-settings.*.json`, root-owned at
  `/etc/claude-code/managed-settings.json`. They block the *honest-path* bypass (`--no-gpg-sign`,
  `--no-verify`, `core.hooksPath`, and the dcw commit/push lockdown). They are **defeatable** by
  design (git plumbing, libgit2, shell obfuscation) — fast feedback, **not** a wall. See
  `harness/README.md`.
- **portitor (server-side enforcement)** — the **real boundary**. The agent can only reach GitHub
  through portitor over SSH (egress-locked to Anthropic + portitor). On every push portitor verifies,
  server-side, that each commit is **SSH-signed by an allowed signer**, that the signer's
  **fingerprint maps to the role** the action requires (implementer vs reviewer), that content
  **role-rules** hold (e.g. only a reviewer may close beads), and that the **default branch** is
  protected — then forwards the branch and opens the PR with its own GitHub token (never exposed to
  the agent). This is audited in `portitor-audit.md`.

Rule of thumb: if a control must hold against a fully-compromised agent, it has to live in portitor
(or GitHub branch protection), not in managed-settings.

## Installer pinning (supply chain)

Every `curl … | sh` installer in the Dockerfiles is **pinned by the sha256 of the installer
*script*** (not the tool version): the image downloads the script, `sha256sum -c` it against a
committed hash, then runs it. This catches a tampered/MITM'd installer (the build fails loudly)
**without** freezing the tool — the script still fetches the latest version. Pinned: `starship`,
`claude`, `nix` (base); `beads_rust`, `rustup` (personal); `bun` (work); `beads_rust`, `claude`
(agent base).

- **Bumping a hash** (when a build fails on a legitimate upstream script change):
  `curl -fsSL <url> | sha256sum` → paste the new hash into the matching `RUN` line.
- **Automating it:** a scheduled CI/renovate job can re-hash each installer URL and open a PR with
  the new values — so pinning never rots (the optional 4th P4 measure).
- **Artifact integrity:** the `zig` tarball is verified against the upstream `.shasum` from
  `ziglang.org/download/index.json`; `cargo install --git` uses `--locked` (upstream `Cargo.lock`)
  for reproducible deps. `go install …@latest` floats but is covered by the Go module checksum DB
  (sumdb) — interactive-only, low risk.

## Architecture

- **Three images**: `claude-dev-base` (shared), `claude-dev-personal`, `claude-dev-work`
- **Separate auth**: personal uses `CLAUDE_CODE_OAUTH_TOKEN` (keychain), work uses wire proxy by default (`--direct` falls back to `ANTHROPIC_API_KEY` from keychain); `gh` CLI uses `GH_TOKEN` from keychain (optional)
- **Persistent volumes**: `claude-personal-repos` / `claude-work-repos` (cloned repos; work on native ext4), `claude-fish-data` (fish history), `claude-tmux-data` (tmux resurrect). Neovim plugins and the Claude binary are baked into the image. Claude Code's own state piggybacks on the repo volume rather than a dedicated volume: session transcripts (`projects/`) and prompt history (`history.jsonl`) are symlinked from `~/.claude` into `/workspace/.claude-state` by the entrypoint, and per-project trust is regenerated into `~/.claude.json` from the `/workspace` subdirectories on every boot (so trust never re-prompts, with no stale entries or cached state).
- **SSH agent forwarding**: by default the host agent is forwarded (YubiKey touch-signing works for git). With `--agent` (personal only), an ephemeral signing-only agent holding just a no-touch FIDO2 key is forwarded instead, and git transport switches to `GH_TOKEN` over HTTPS — so agents can sign commits without touch prompts but can't authenticate as you. The agent is torn down on container exit; the no-touch key is identified by hash in `~/.ssh/signing-key-hashes` (no key name in the repo).
- **IDEA access**: dedicated ed25519 key for SSH, auto-generated per machine at build time
- **MCP servers**: work entrypoint filters to only Docker-compatible servers (ijproxy via host IDE, Context7, PluginModelAnalyzer)
- **Nested tmux**: container uses `C-b` prefix, `ctrl+arrow` for window nav (host uses `C-a`, `shift+arrow`)
- **Images are built per-machine**: `HOST_UID` build arg matches container user to host UID
