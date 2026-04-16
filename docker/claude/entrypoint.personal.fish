#!/usr/bin/env fish
# Ensure Claude Code settings exist in ~/.claude/ (mounted volume)
if not test -f ~/.claude/settings.json
    mkdir -p ~/.claude
    cp ~/.config/claude/settings.json ~/.claude/settings.json
end

# Persist .claude.json in the volume (survives --rm)
if not test -f ~/.claude/.claude.json
    cp ~/.claude.json ~/.claude/.claude.json 2>/dev/null
end
ln -sf ~/.claude/.claude.json ~/.claude.json

# Create workspace readme on first run
if not test -f /workspace/README.md
    printf '%s\n' \
        '# Workspace' \
        '' \
        'Clone repos here (native ext4, persistent across restarts).' \
        '' \
        '```bash' \
        'git clone --depth 1 --single-branch git@github.com:<user>/<repo>.git' \
        '```' \
        > /workspace/README.md
end

# Start fish interactive shell
exec fish
