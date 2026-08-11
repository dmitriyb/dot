# dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Contents

- **btop** - Btop system monitor
- **fish** - Fish shell configuration
- **ghostty** - Ghostty terminal emulator
- **git** - Git configuration
- **nvim** - Neovim (LazyVim-based)
- **sesh** - Sesh smart tmux session manager
- **tmux** - Tmux terminal multiplexer
- **tuicr** - Terminal code review tool (config only; install via brew/cargo)
- **starship.toml** - Starship prompt
- **themes** - Portable theme system (Tokyo Night, Catppuccin, Gruvbox, Kanagawa)
- **aerospace** - AeroSpace window manager (macOS); its letter workspaces mirror the ones in `arch/.config/omarchy/custom-hyprland.lua`
- **claude** - Claude Code user skills
- **docker/claude** - [Dockerized Claude Code environment](docker/claude/README.md)
- **faber** - [faber → portitor gate-stack configs and tooling](shared/.config/faber/README.md) (projects, `faber-stack`/`faber-epic`/`faber-e2e`/`portitor-branch`, gate + egress build contexts)
- **bin** - helper scripts stowed to `~/.local/bin` (`docker-claude`, the faber tooling, `theme-*`, `role-keys`/`restore-role-keys`/`ssh-load-keys`)

## Installation

### Prerequisites

#### Arch Linux

```bash
sudo pacman -S stow fish tmux neovim starship btop git eza fzf bat zoxide direnv lazygit glow ffmpeg imagemagick docker jq python ttf-jetbrains-mono-nerd
yay -S ghostty tmux-plugin-manager sesh-bin
cargo install tuicr   # terminal code review; requires the Rust toolchain (rustup)
```

#### macOS

```bash
brew install stow fish tmux neovim starship btop git eza fzf bat zoxide direnv lazygit glow ffmpeg imagemagick jq python3 tpm sesh
brew install agavra/tap/tuicr
brew install --cask ghostty docker font-jetbrains-mono-nerd-font
```

### Setup

```bash
cd ~/Work/dot
./setup.sh
```

Idempotent — safe to re-run. Stows config, bin, Claude Code skills/settings, and SSH host aliases, and injects `Include config.d/*` into `~/.ssh/config`.

## Themes

Portable theme system that works on macOS and coexists with [omarchy](https://github.com/getomarchy/omarchy) on Linux.

### On macOS (or Linux without omarchy)

```bash
theme-list      # List available themes
theme-current   # Show current theme
theme-set <name> # Switch theme (hot-reloads fish, tmux, ghostty)
```

### On Linux with omarchy

Omarchy takes precedence. Use `omarchy-theme-set` instead. The fallback chain ensures apps load omarchy themes first, then dotfiles themes if omarchy isn't installed.

### Supported apps

| App | Hot Reload |
|-----|------------|
| Fish | Yes (SIGUSR1) |
| Tmux | Yes (source-file) |
| Ghostty | Yes (SIGUSR2) |
| Btop | Yes (SIGUSR2) |
| Starship | Yes (next prompt) |
| Neovim | Optional (requires nvr) |

### Machine-specific overrides

- **Ghostty**: Create `~/.config/ghostty/local.conf` for font-size, etc.

## License

This repository is licensed under the [MIT License](LICENSE).

**Exception**: The Neovim configuration (`shared/.config/nvim/`) is based on [LazyVim](https://github.com/LazyVim/LazyVim) and is licensed under [Apache 2.0](shared/.config/nvim/LICENSE).
