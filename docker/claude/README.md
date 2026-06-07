# Docker Claude Code

Isolated Claude Code environments running in Fedora containers with full dotfiles, SSH agent forwarding (YubiKey), and separate personal/work images.

## What's inside

**Base** (shared): Fish, tmux, neovim (with plugins), starship, eza, bat, fzf, zoxide, lazygit, direnv, glow, [beads_rust](https://github.com/Dicklesworthstone/beads_rust), [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer), and Claude Code (native binary).

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

```bash
docker-claude -p              # Personal account (Max subscription via OAuth)
docker-claude -p --agent      # Personal, agent mode: forward an ephemeral no-touch signing agent
docker-claude -w              # Work account (via wire proxy, default)
docker-claude --direct        # Work account (direct API key from keychain)
docker-claude -r              # Rebuild all images (pulls latest dotfiles)
docker-claude -r -w           # Rebuild base + work, then launch
docker-claude --no-cache      # Full fresh rebuild (re-downloads everything)
docker-claude --workspace ~/projects -p  # Custom workspace mount (personal only)
```

Aliases: `dc` (docker-claude), `dcp` (-p), `dca` (-p --agent), `dcw` (-w), `dcwd` (--direct).

## Architecture

- **Three images**: `claude-dev-base` (shared), `claude-dev-personal`, `claude-dev-work`
- **Separate auth**: personal uses `CLAUDE_CODE_OAUTH_TOKEN` (keychain), work uses wire proxy by default (`--direct` falls back to `ANTHROPIC_API_KEY` from keychain); `gh` CLI uses `GH_TOKEN` from keychain (optional)
- **Persistent volumes**: `claude-personal-projects` / `claude-work-projects` (Claude Code `projects/`), `claude-personal-repos` / `claude-work-repos` (cloned repos; work on native ext4), `claude-fish-data` (fish history), `claude-tmux-data` (tmux resurrect). Neovim plugins and the Claude binary are baked into the image.
- **SSH agent forwarding**: by default the host agent is forwarded (YubiKey touch-signing works for git). With `--agent` (personal only), an ephemeral signing-only agent holding just a no-touch FIDO2 key is forwarded instead, and git transport switches to `GH_TOKEN` over HTTPS — so agents can sign commits without touch prompts but can't authenticate as you. The agent is torn down on container exit; the no-touch key is identified by hash in `~/.ssh/signing-key-hashes` (no key name in the repo).
- **IDEA access**: dedicated ed25519 key for SSH, auto-generated per machine at build time
- **MCP servers**: work entrypoint filters to only Docker-compatible servers (ijproxy via host IDE, Context7, PluginModelAnalyzer)
- **Nested tmux**: container uses `C-b` prefix, `ctrl+arrow` for window nav (host uses `C-a`, `shift+arrow`)
- **Images are built per-machine**: `HOST_UID` build arg matches container user to host UID
