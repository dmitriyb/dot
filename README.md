# dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Contents

- **btop** - Btop system monitor
- **fish** - Fish shell configuration
- **ghostty** - Ghostty terminal emulator
- **git** - Git configuration
- **nvim** - Neovim (LazyVim-based)
- **tmux** - Tmux terminal multiplexer
- **starship.toml** - Starship prompt
- **themes** - Portable theme system (Tokyo Night, Catppuccin, Gruvbox, Kanagawa)

## Installation

### Prerequisites

#### Arch Linux

```bash
sudo pacman -S stow fish tmux neovim starship btop git eza fzf bat zoxide direnv lazygit ffmpeg imagemagick docker ttf-jetbrains-mono-nerd
yay -S ghostty tmux-plugin-manager
```

#### macOS

```bash
brew install stow fish tmux neovim starship btop git eza fzf bat zoxide direnv lazygit ffmpeg imagemagick tpm
brew install --cask ghostty docker font-jetbrains-mono-nerd-font
```

### Setup

```bash
cd ~/Work/dot
stow -t ~/.config config && stow -t ~ bin
```

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

**Exception**: The Neovim configuration (`config/nvim/`) is based on [LazyVim](https://github.com/LazyVim/LazyVim) and is licensed under [Apache 2.0](config/nvim/LICENSE).
