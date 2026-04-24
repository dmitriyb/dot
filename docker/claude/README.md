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

Work account credentials are picked up automatically from the macOS Keychain (stored by `claude login`).

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

## Usage

```bash
docker-claude -p              # Personal account (Max subscription via OAuth)
docker-claude -w              # Work account (via wire proxy, default)
docker-claude --direct        # Work account (direct API key from keychain)
docker-claude -r              # Rebuild all images (pulls latest dotfiles)
docker-claude -r -w           # Rebuild base + work, then launch
docker-claude --no-cache      # Full fresh rebuild (re-downloads everything)
docker-claude --workspace ~/projects -p  # Custom workspace mount (personal only)
```

Aliases: `dc` (docker-claude), `dcp` (-p), `dcw` (-w), `dcwd` (--direct).

## Architecture

- **Three images**: `claude-dev-base` (shared), `claude-dev-personal`, `claude-dev-work`
- **Separate auth**: personal uses `CLAUDE_CODE_OAUTH_TOKEN` (keychain), work uses wire proxy by default (`--direct` falls back to `ANTHROPIC_API_KEY` from keychain); `gh` CLI uses `GH_TOKEN` from keychain (optional)
- **Persistent volumes**: `claude-personal` / `claude-work` for Claude Code state, `claude-work-repos` for work repos (native ext4), `claude-share` / `claude-state` for nvim plugins, fish history, tmux resurrect
- **SSH agent forwarding**: host agent forwarded into container (YubiKey signing works for git)
- **IDEA access**: dedicated ed25519 key for SSH, auto-generated per machine at build time
- **MCP servers**: work entrypoint filters to only Docker-compatible servers (ijproxy via host IDE, Context7, PluginModelAnalyzer)
- **Nested tmux**: container uses `C-b` prefix, `ctrl+arrow` for window nav (host uses `C-a`, `shift+arrow`)
- **Images are built per-machine**: `HOST_UID` build arg matches container user to host UID
