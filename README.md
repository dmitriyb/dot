# dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Contents

- **fish** - Fish shell configuration
- **ghostty** - Ghostty terminal emulator
- **git** - Git configuration
- **nvim** - Neovim (LazyVim-based)
- **tmux** - Tmux terminal multiplexer
- **starship.toml** - Starship prompt

## Installation

### Prerequisites

- [GNU Stow](https://www.gnu.org/software/stow/)

```bash
# Arch Linux
sudo pacman -S stow

# macOS
brew install stow
```

### Setup

Stow the configs:

```bash
cd ~/Work/dot/config
stow -t ~/.config .
```

### Machine-specific overrides

Some configs support local overrides that are not tracked in git:

- **Ghostty**: Create `~/.config/ghostty/local.conf` for font-size, etc.
- **Neovim**: `theme.lua` symlink to omarchy theme system (Linux-specific)

## License

This repository is licensed under the [MIT License](LICENSE).

**Exception**: The Neovim configuration (`config/nvim/`) is based on [LazyVim](https://github.com/LazyVim/LazyVim) and is licensed under [Apache 2.0](config/nvim/LICENSE).
