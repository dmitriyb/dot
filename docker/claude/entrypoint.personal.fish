#!/usr/bin/env fish
# settings.json is image-authoritative — overwrite from seed every launch.
# Other ~/.claude state (projects/, todos/, .claude.json) stays in the volume.
mkdir -p ~/.claude
cp ~/.config/claude/settings.json ~/.claude/settings.json

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
