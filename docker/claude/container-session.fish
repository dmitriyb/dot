# Installed as /etc/fish/conf.d/00-docker-claude.fish: runs for every session sshd starts in
# the container, before the user's conf.d and config.fish.

if test -r ~/.container-env
    for kv in (string split0 <~/.container-env)
        set -l parts (string split -m1 = -- $kv)
        set -q parts[2]; or continue
        set -gx $parts[1] $parts[2]
    end
end

# /run/secrets/<lowercase_var> → <UPPERCASE_VAR>, written by docker-claude over `docker exec` stdin.
for f in /run/secrets/*
    test -f "$f" -a -r "$f"; or continue
    set -gx (string upper (basename "$f")) (cat "$f")
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

# ~/.ssh/rc repoints this link at each new session's forwarded agent, so shells that outlive
# their session (tmux) keep signing after a reconnect.
if test -S ~/.ssh/agent.sock
    set -gx SSH_AUTH_SOCK ~/.ssh/agent.sock
end
