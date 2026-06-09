#!/usr/bin/env fish
# ~/.claude is ephemeral (image-baked settings.json + skills). Persistent state lives on the
# /workspace repo volume: session transcripts + prompt history are symlinked into
# /workspace/.claude-state, and per-project trust is regenerated from /workspace each boot.
# Set the container's default mode to auto.
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

# Persist conversation transcripts + prompt history on the /workspace volume, and trust every
# workspace project. Trust is a pure function of /workspace contents, regenerated each boot —
# no stale entries, no persisted caches/memories.
python3 -c '
import json, os, glob, shutil
home = os.path.expanduser("~")
ws, state = "/workspace", "/workspace/.claude-state"
os.makedirs(os.path.join(state, "projects"), exist_ok=True)
hist = os.path.join(state, "history.jsonl")
open(hist, "a").close()  # create if missing

# Symlink persistent artifacts from ~/.claude into the /workspace volume
def relink(link, target):
    if os.path.islink(link): os.unlink(link)
    elif os.path.isdir(link): shutil.rmtree(link)
    elif os.path.exists(link): os.remove(link)
    os.symlink(target, link)
relink(os.path.join(home, ".claude", "projects"), os.path.join(state, "projects"))
relink(os.path.join(home, ".claude", "history.jsonl"), hist)

# Trust /workspace and every immediate subdirectory (each is a project)
cfgp = os.path.join(home, ".claude.json")
cfg = json.load(open(cfgp)) if os.path.exists(cfgp) else {}
cfg.setdefault("hasCompletedOnboarding", True)
projects = cfg.setdefault("projects", {})
for p in [ws] + [d for d in sorted(glob.glob(ws + "/*")) if os.path.isdir(d)]:
    projects.setdefault(p, {})["hasTrustDialogAccepted"] = True
json.dump(cfg, open(cfgp, "w"), indent=2)
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
