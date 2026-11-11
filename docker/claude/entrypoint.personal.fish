#!/usr/bin/env fish
# Secrets arrive later (docker-claude injects them into /run/secrets) and sessions enter over
# SSH, so token loading lives in /etc/fish/conf.d/00-docker-claude.fish, not here.
source /etc/docker-claude/save-container-env.fish

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

# sshd is the container's main process and docker-claude's readiness signal (port 2223,
# published on 127.0.0.1); every session, dcp's and the IDE's, enters through it.
exec sudo /usr/sbin/sshd -D -e
