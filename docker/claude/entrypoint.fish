#!/usr/bin/env fish
# Ensure Claude Code settings exist in ~/.claude/ (mounted volume)
if not test -f ~/.claude/settings.json
    mkdir -p ~/.claude
    cp ~/.config/claude/settings.json ~/.claude/settings.json
end

# Start fish interactive shell
exec fish
