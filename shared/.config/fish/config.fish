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
# Theme Integration (omarchy on Linux, dotfiles fallback on macOS)
# =============================================================================

# Load theme: prefer omarchy (Linux), fallback to dotfiles (macOS)
if test -f ~/.config/omarchy/current/theme/fish.theme
    source ~/.config/omarchy/current/theme/fish.theme
else if test -f ~/.config/themes/current/fish.theme
    source ~/.config/themes/current/fish.theme
end

# Reload theme on SIGUSR1 signal (triggered by theme switching)
function __reload_theme --on-signal SIGUSR1
    if test -f ~/.config/omarchy/current/theme/fish.theme
        source ~/.config/omarchy/current/theme/fish.theme
    else if test -f ~/.config/themes/current/fish.theme
        source ~/.config/themes/current/fish.theme
    end
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
    alias ls 'eza -lh --git --group-directories-first --icons=auto'
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
alias c claude
alias ceh 'claude --effort high'
alias cex 'claude --effort xhigh'
alias cem 'claude --effort maximum'
# docker-claude is the single entrypoint for the containerized Claude cockpit.
alias dc docker-claude
alias dcp 'docker-claude personal'
alias dcw 'docker-claude work'

# faber gate tooling
alias fbs faber-stack
alias pbr portitor-branch

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

# ssh-agent lifecycle is owned by the OS layer (systemd user service on Linux,
# launchd on macOS) or by Docker (-e SSH_AUTH_SOCK) in containers. The shell only
# *consumes* the socket — it never spawns, kills, or removes an agent. This avoids
# the per-shell agent leak that fish's "config.fish runs for every non-interactive
# shell" model otherwise causes.
#
# Switch away from macOS's default Keychain agent (`.../com.apple.launchd.../Listeners`):
# it holds FIDO2/SK keys but can't *sign* with them (Apple's OpenSSH has no SK support),
# so we point at our Homebrew agent instead. A Docker-forwarded `/ssh-agent` and a live
# systemd socket are kept as-is.
if not set -q SSH_AUTH_SOCK; or test -z "$SSH_AUTH_SOCK"; or not test -S "$SSH_AUTH_SOCK"; or string match -q "*/com.apple.launchd.*" "$SSH_AUTH_SOCK"
    if set -q XDG_RUNTIME_DIR; and test -S "$XDG_RUNTIME_DIR/ssh-agent.socket"
        set -gx SSH_AUTH_SOCK "$XDG_RUNTIME_DIR/ssh-agent.socket"
    else if test -S "$HOME/.ssh/agent.sock"
        set -gx SSH_AUTH_SOCK "$HOME/.ssh/agent.sock"
    end
end
