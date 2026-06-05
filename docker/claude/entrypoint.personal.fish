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
