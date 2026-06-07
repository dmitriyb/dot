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
