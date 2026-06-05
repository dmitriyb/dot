#!/usr/bin/env fish
# ~/.claude is ephemeral (image-baked settings.json + skills). Only projects/ persists
# via a submounted volume. Set the container's default mode to auto.
python3 -c '
import json, os
src = os.path.expanduser("~/dot/claude/settings.json")
dst = os.path.expanduser("~/.claude/settings.json")
cfg = json.load(open(src))
cfg.setdefault("permissions", {})["defaultMode"] = "auto"
os.makedirs(os.path.dirname(dst), exist_ok=True)
if os.path.lexists(dst): os.remove(dst)
with open(dst, "w") as f: json.dump(cfg, f, indent=2)
'

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
