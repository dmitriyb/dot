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

# Agent mode: the forwarded ssh-agent holds only a no-touch signing key. Sign with
# it, and route GitHub transport over HTTPS + GH_TOKEN so the key signs but never
# authenticates.
if test "$AGENT_MODE" = 1
    # Derive the signing key from the forwarded agent (it holds exactly one key).
    set -l pub (ssh-add -L 2>/dev/null | head -n1)
    if test -n "$pub"
        git config --global user.signingkey "key::$pub"
    end

    # HTTPS remotes also stop the `git@github.com-personal:` includeIf from pulling
    # in the touch-key signingkey, so the global key above wins.
    if test -n "$GH_TOKEN"
        gh auth setup-git 2>/dev/null
        git config --global url."https://github.com/".insteadOf "git@github.com-personal:"
        git config --global url."https://github.com/".insteadOf "git@github.com:"
    end
end

# Start fish interactive shell
exec fish
