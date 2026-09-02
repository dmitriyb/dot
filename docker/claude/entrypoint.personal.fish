#!/usr/bin/env fish
# Load mounted secrets into the env: /run/secrets/<lowercase_var> → <UPPERCASE_VAR>
# (CLAUDE_CODE_OAUTH_TOKEN, GH_TOKEN — mounted read-only by docker-claude instead of
# passing -e, so they never appear in `docker inspect`). Runs before GH_TOKEN is used.
if test -d /run/secrets
    for f in /run/secrets/*
        test -f "$f"; or continue
        set -gx (string upper (basename "$f")) (cat "$f")
    end
end

# Workaround for anthropics/claude-code#79597: a setup-token's profile omits
# subscriptionType, so the interactive /model picker fail-closes Fable 5 behind a
# "usage credits" wall. Declaring the real plan tier restores it. Only the token path
# needs this (ignored when a /login credential drives). Remove once the token flow
# resolves the tier server-side.
if set -q CLAUDE_CODE_OAUTH_TOKEN
    set -gx CLAUDE_CODE_SUBSCRIPTION_TYPE max
    set -gx CLAUDE_CODE_RATE_LIMIT_TIER default_claude_max_5x
end

# ~/.claude is ephemeral (image-baked settings.json + skills). Persistent state lives on the
# /workspace repo volume: session transcripts + prompt history are symlinked into
# /workspace/.claude-state, and per-project trust is regenerated from /workspace each boot.
# Set the container's default mode to auto.
python3 -c '
import json, os, sys
src = os.path.expanduser("~/dot/shared/.claude/settings.json")
dst = os.path.expanduser("~/.claude/settings.json")
if not os.path.exists(src):
    print(f"warning: {src} missing; skipping settings sync", file=sys.stderr)
else:
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

# Create workspace readme on first run
if not test -f /workspace/README.md
    printf '%s\n' \
        '# Workspace' \
        '' \
        'Clone repos here (native ext4, persistent across restarts).' \
        '' \
        '```bash' \
        'git clone --depth 1 --single-branch https://github.com/<user>/<repo>.git' \
        '```' \
        > /workspace/README.md
end

# Import SSH public keys from forwarded agent for IDE Remote Development access
if test -n "$SSH_AUTH_SOCK"
    ssh-add -L >> ~/.ssh/authorized_keys 2>/dev/null
    sort -u -o ~/.ssh/authorized_keys ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys 2>/dev/null
end

# Start sshd for IDE Remote Development (port 2223; published on 127.0.0.1 by docker-claude)
sudo /usr/sbin/sshd 2>/dev/null

# Start fish interactive shell
exec fish
