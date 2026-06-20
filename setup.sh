#!/usr/bin/env bash
set -euo pipefail

DOTDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DOTDIR"

echo "Setting up dotfiles from $DOTDIR..."

# Headless = servers + containers: no graphical session, no init-managed agent.
# Forced via DOT_PROFILE=headless (the docker image sets this). On Linux it's also
# inferred from the absence of a Wayland/X display. macOS GUI sessions have neither
# WAYLAND_DISPLAY nor DISPLAY but are never headless, so the inference is Linux-only.
is_headless() {
    [ "${DOT_PROFILE:-}" = headless ] && return 0
    [ "$(uname)" = Darwin ] && return 1
    [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ] && return 0
    return 1
}

# Remove symlinks a previous run created (i.e. that point into THIS repo) before
# stowing. This makes setup.sh idempotent and robust across any restructure — renamed
# packages, files moved between packages, or moved within a package — by converging to
# whatever the current layout stows, instead of leaving orphaned/dangling links that
# would dangle or make stow abort. Only links resolving into $DOTDIR are touched; real
# files and symlinks pointing elsewhere are left untouched.
prune_repo_links() {
    local dir link tgt
    for dir in ~/.config ~/.local ~/.claude ~/.ssh ~/Library/LaunchAgents; do
        [ -d "$dir" ] || continue
        while IFS= read -r link; do
            if [ -e "$link" ]; then
                # Resolvable link: drop it only if its real target lives inside the repo.
                tgt="$(cd "$(dirname "$link")" && cd "$(dirname "$(readlink "$link")")" 2>/dev/null && pwd)" || continue
                case "$tgt/" in "$DOTDIR"/*) rm -f "$link" ;; esac
            else
                # Broken link: can't resolve it, so match the repo dir name in the link
                # string (stow writes relative links like ../../<repo>/...). Safe to drop.
                case "$(readlink "$link")" in
                    "$DOTDIR"/* | */"$(basename "$DOTDIR")"/*) rm -f "$link" ;;
                esac
            fi
        done < <(find "$dir" -type l 2>/dev/null)
    done
}

# Home-mirror layout: every package mirrors ~ and stows to a single target (~).
# Pre-create the dirs that must stay real so stow folds *inside* them (links the
# leaves) instead of replacing the whole directory with a symlink.
mkdir -p ~/.config ~/.claude/skills ~/.ssh/config.d

# Back up any pre-existing real settings.json so stow can own that path.
if [ -e ~/.claude/settings.json ] && [ ! -L ~/.claude/settings.json ]; then
    mv ~/.claude/settings.json ~/.claude/settings.json.pre-stow.bak
    echo "Backed up existing ~/.claude/settings.json."
fi

# Clear stale links from any earlier layout so stow can re-converge cleanly.
prune_repo_links

# Shared layer (every OS): .config, .local/bin, .claude, .ssh.
stow -t ~ shared
echo "Stowed shared."

# OS-specific layer.
case "$(uname)" in
    Darwin)
        stow -t ~ mac
        echo "Stowed mac."
        ;;
    Linux)
        if is_headless; then
            stow -t ~ headless
            echo "Stowed headless."
        else
            stow -t ~ arch
            echo "Stowed arch."
        fi
        ;;
esac

# Inject Include into ~/.ssh/config if missing (config.d/* comes from the shared layer).
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

# Activate the OS-managed ssh-agent. Skipped on headless/containers — they have no
# init system and consume the forwarded SSH_AUTH_SOCK instead.
if ! is_headless; then
    case "$(uname)" in
        Darwin)
            launchctl bootout "gui/$(id -u)/com.user.ssh-agent" 2>/dev/null || true
            launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.user.ssh-agent.plist || true
            echo "Loaded launchd ssh-agent."
            ;;
        Linux)
            systemctl --user enable --now ssh-agent.service || true
            echo "Enabled systemd user ssh-agent.service."
            ;;
    esac
fi

echo "Done."
