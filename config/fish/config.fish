# Fish shell configuration
# Cross-platform config using capability-based detection (Badya pattern)

# =============================================================================
# Helper Functions (Badya pattern)
# =============================================================================

# Check if command exists
function _have
    command -q $argv[1]
end

# Source file if readable
function _source_if
    test -r $argv[1]; and source $argv[1]
end

# =============================================================================
# Platform Detection (Homebrew for macOS)
# =============================================================================

# Homebrew (macOS Apple Silicon)
if test -d /opt/homebrew
    eval (/opt/homebrew/bin/brew shellenv)
end

# Homebrew (macOS Intel)
if test -d /usr/local/Homebrew
    eval (/usr/local/bin/brew shellenv)
end

# =============================================================================
# Environment Variables
# =============================================================================

set -gx SUDO_EDITOR "$EDITOR"
set -gx BAT_THEME ansi

# GPG configuration
if _have gpg-connect-agent
    set -gx GPG_TTY (tty)
    gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
end

# Add local bin to PATH
set -gx PATH $HOME/.local/bin $PATH

# =============================================================================
# Omarchy Theme Integration
# =============================================================================

# Load Omarchy theme for fish
_source_if ~/.config/omarchy/current/theme/fish.theme

# Reload theme on SIGUSR1 signal (triggered by omarchy theme switching)
function __omarchy_reload_theme --on-signal SIGUSR1
    _source_if ~/.config/omarchy/current/theme/fish.theme
end

# =============================================================================
# Tool Initialization (capability-based)
# =============================================================================

# Initialize zoxide if available
if _have zoxide
    zoxide init fish | source
end

# Initialize starship prompt
if _have starship
    starship init fish | source
end

# Initialize direnv if available
if _have direnv
    direnv hook fish | source
end

# =============================================================================
# Aliases (capability-based)
# =============================================================================

# File system aliases (eza)
if _have eza
    alias ls 'eza -lh --group-directories-first --icons=auto'
    alias lsa 'ls -a'
    alias lt 'eza --tree --level=2 --long --icons --git'
    alias lta 'lt -a'
end

# FZF with preview
if _have fzf; and _have bat
    alias ff 'fzf --preview "bat --style=numbers --color=always {}"'
end

# Directory navigation with zoxide
if _have zoxide
    function zd
        if test (count $argv) -eq 0
            builtin cd ~
        else if test -d $argv[1]
            builtin cd $argv[1]
        else
            z $argv && printf "\U000F17A9 " && pwd
        end
    end
    alias cd zd
end

# Open function (capability-based: macOS has 'open', Linux uses 'xdg-open')
if not _have open
    function open
        xdg-open $argv >/dev/null 2>&1 &
    end
end

# Directory navigation shortcuts
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'

# Tools
alias d docker
alias r rails

# Neovim function
function n
    if test (count $argv) -eq 0
        nvim .
    else
        nvim $argv
    end
end

# Git aliases
alias g git
alias gcm 'git commit -m'
alias gcam 'git commit -a -m'
alias gcad 'git commit -a --amend'

# Compression functions
function compress
    tar -czf "$argv[1].tar.gz" "$argv[1]"
end

alias decompress 'tar -xzf'

# Write iso file to sd card
function iso2sd
    if test (count $argv) -ne 2
        echo "Usage: iso2sd <input_file> <output_device>"
        echo "Example: iso2sd ~/Downloads/ubuntu-25.04-desktop-amd64.iso /dev/sda"
        echo ""
        echo "Available SD cards:"
        lsblk -d -o NAME | grep -E '^sd[a-z]' | awk '{print "/dev/"$1}'
    else
        sudo dd bs=4M status=progress oflag=sync if=$argv[1] of=$argv[2]
        sudo eject $argv[2]
    end
end

# Format an entire drive for a single partition using ext4
function format-drive
    if test (count $argv) -ne 2
        echo "Usage: format-drive <device> <name>"
        echo "Example: format-drive /dev/sda 'My Stuff'"
        echo ""
        echo "Available drives:"
        lsblk -d -o NAME -n | awk '{print "/dev/"$1}'
    else
        echo "WARNING: This will completely erase all data on $argv[1] and label it '$argv[2]'."
        read -P "Are you sure you want to continue? (y/N): " confirm
        if string match -qi y $confirm
            sudo wipefs -a $argv[1]
            sudo dd if=/dev/zero of=$argv[1] bs=1M count=100 status=progress
            sudo parted -s $argv[1] mklabel gpt
            sudo parted -s $argv[1] mkpart primary ext4 1MiB 100%
            if string match -q "*nvme*" $argv[1]
                sudo mkfs.ext4 -L $argv[2] "$argv[1]p1"
            else
                sudo mkfs.ext4 -L $argv[2] "$argv[1]1"
            end
            sudo chmod -R 777 "/run/media/$USER/$argv[2]"
            echo "Drive $argv[1] formatted and labeled '$argv[2]'."
        end
    end
end

# Transcode a video to a good-balance 1080p that's great for sharing online
function transcode-video-1080p
    set basename (string replace -r '\.[^.]*$' '' $argv[1])
    ffmpeg -i $argv[1] -vf scale=1920:1080 -c:v libx264 -preset fast -crf 23 -c:a copy "$basename-1080p.mp4"
end

# Transcode a video to a good-balance 4K that's great for sharing online
function transcode-video-4K
    set basename (string replace -r '\.[^.]*$' '' $argv[1])
    ffmpeg -i $argv[1] -c:v libx265 -preset slow -crf 24 -c:a aac -b:a 192k "$basename-optimized.mp4"
end

# Transcode any image to JPG image that's great for shrinking wallpapers
function img2jpg
    set basename (string replace -r '\.[^.]*$' '' $argv[1])
    magick $argv[1] -quality 95 -strip "$basename.jpg"
end

# Transcode any image to JPG image that's great for sharing online without being too big
function img2jpg-small
    set basename (string replace -r '\.[^.]*$' '' $argv[1])
    magick $argv[1] -resize 1080x\> -quality 95 -strip "$basename.jpg"
end

# Transcode any image to compressed-but-lossless PNG
function img2png
    set basename (string replace -r '\.[^.]*$' '' $argv[1])
    magick $argv[1] -strip -define png:compression-filter=5 \
        -define png:compression-level=9 \
        -define png:compression-strategy=1 \
        -define png:exclude-chunk=all \
        "$basename.png"
end

# Auto-start ssh-agent
if not set -q SSH_AUTH_SOCK; or not test -S $SSH_AUTH_SOCK
    eval (ssh-agent -c) >/dev/null
    set -gx SSH_AUTH_SOCK $SSH_AUTH_SOCK
    set -gx SSH_AGENT_PID $SSH_AGENT_PID
end
