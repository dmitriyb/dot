#!/usr/bin/env fish
# Ensure Claude Code settings exist in ~/.claude/ (mounted volume)
if not test -f ~/.claude/settings.json
    mkdir -p ~/.claude
    cp ~/.config/claude/settings.json ~/.claude/settings.json
end

# Persist .claude.json in the volume (survives --rm)
# The baked-in /home/dev/.claude.json has onboarding defaults;
# copy it to the volume on first run, then always symlink.
if not test -f ~/.claude/.claude.json
    cp ~/.claude.json ~/.claude/.claude.json 2>/dev/null
end
ln -sf ~/.claude/.claude.json ~/.claude.json

# Import SSH public keys from forwarded agent for IDEA Remote Development access
if test -n "$SSH_AUTH_SOCK"
    ssh-add -L >> ~/.ssh/authorized_keys 2>/dev/null
    sort -u -o ~/.ssh/authorized_keys ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys 2>/dev/null
end

# Start sshd for IDEA Remote Development
sudo /usr/sbin/sshd 2>/dev/null

# Create workspace readme on first run
if not test -f /workspace/README.md
    printf '%s\n' \
        '# Workspace' \
        '' \
        'Clone repos here (native ext4, persistent across restarts).' \
        '' \
        '## Shallow clone + branch checkout' \
        '' \
        '```bash' \
        '# 1. Shallow clone (default branch, depth 1)' \
        'git clone --depth 1 --single-branch ssh://git@<work-repository>.git' \
        '' \
        '# 2. Fetch only your branch tip (no history)' \
        'git fetch --depth 1 origin <your-branch>' \
        '' \
        '# 3. Create local branch from fetched tip' \
        'git checkout -b <your-branch> FETCH_HEAD' \
        '```' \
        '' \
        '## Sparse checkout (optional — only materialize dirs you work in)' \
        '' \
        '```bash' \
        'git sparse-checkout init --cone' \
        'git sparse-checkout set dir1 dir2 dir3' \
        '```' \
        '' \
        '## Deepen history later (for blame/log)' \
        '' \
        '```bash' \
        'git fetch --deepen=50' \
        '```' \
        > /workspace/README.md
end

# Filter MCP servers for Docker environment
for dir in /workspace/*
    if test -f "$dir/.claude/settings.local.json"
        and grep -q enabledMcpjsonServers "$dir/.claude/settings.local.json"
        python3 -c "
import json, sys
p = sys.argv[1]
with open(p) as f: cfg = json.load(f)
keep = ['Context7', 'PluginModelAnalyzer', 'ijproxy']
cfg['enabledMcpjsonServers'] = [s for s in cfg.get('enabledMcpjsonServers', []) if s in keep]
with open(p, 'w') as f: json.dump(cfg, f, indent=2)
" "$dir/.claude/settings.local.json" 2>/dev/null
    end
end

# Start fish interactive shell
exec fish
