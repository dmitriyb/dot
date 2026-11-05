# Sourced by the entrypoints. sshd starts every session from a clean environment, so the
# container's own (Dockerfile ENV, docker run -e) is saved here for the login shell to restore.
# The excluded names are per-session and must come from the session itself.
begin
    set -l prev_umask (umask)
    umask 077
    set -l saved
    for kv in (env -0 | string split0)
        set -l name (string split -m1 = -- $kv)[1]
        contains -- $name HOME HOSTNAME PWD SHLVL TERM _; and continue
        set -a saved $kv
    end
    printf '%s\0' $saved >~/.container-env
    umask $prev_umask
end
