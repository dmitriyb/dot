#!/usr/bin/env bash
set -euo pipefail

DOTDIR="$(cd "$(dirname "$0")" && pwd)"

echo "Setting up dotfiles from $DOTDIR..."

# Stow config and bin
cd "$DOTDIR"
mkdir -p ~/.config
stow -t ~/.config config
stow -t ~ bin
echo "Stowed config and bin."

# Stow SSH config (ssh/.ssh/config.d/* → ~/.ssh/config.d/*)
mkdir -p ~/.ssh/config.d
stow -t ~ ssh
echo "Stowed SSH config."

# Inject Include into ~/.ssh/config if missing
SSH_CONFIG="$HOME/.ssh/config"
INCLUDE_LINE="Include config.d/*"
if [[ -f "$SSH_CONFIG" ]]; then
    if ! grep -qF "$INCLUDE_LINE" "$SSH_CONFIG"; then
        printf '%s\n\n%s' "$INCLUDE_LINE" "$(cat "$SSH_CONFIG")" > "$SSH_CONFIG"
        echo "Added Include to ~/.ssh/config."
    else
        echo "~/.ssh/config already has Include."
    fi
else
    echo "$INCLUDE_LINE" > "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    echo "Created ~/.ssh/config with Include."
fi

echo "Done."
