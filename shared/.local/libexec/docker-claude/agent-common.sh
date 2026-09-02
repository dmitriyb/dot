# agent-common.sh — shared host-side helpers for docker-claude.
#
# Sourced, not executed. Single source of truth for the cross-platform keychain
# reads, the /run/secrets token mounts, and path resolution. Sourced by
# docker-claude (the entrypoint); lives next to it in .local/libexec/docker-claude.

# Portable `readlink -f` (BSD/macOS readlink lacks -f): walk the symlink chain.
resolve_path() {
	local p="$1" target
	while [ -L "$p" ]; do
		target="$(readlink "$p")"
		case "$target" in
			/*) p="$target" ;;
			*) p="$(cd "$(dirname "$p")" && pwd)/$target" ;;
		esac
	done
	printf '%s\n' "$p"
}

# dot_root <start-dir> — walk up until a dir containing docker/claude is found, and
# print it (the dot repo root). Depth-robust: lets the host launchers live anywhere
# under the repo (e.g. .local/libexec/docker-claude) without hardcoding `cd ../../..`.
dot_root() {
	local d="$1"
	while [[ "$d" != / && ! -d "$d/docker/claude" ]]; do d="$(dirname "$d")"; done
	[[ -d "$d/docker/claude" ]] && printf '%s\n' "$d"
}

# ---- secret files (keep tokens out of `docker inspect` Config.Env + host `ps`) ----
# Instead of `-e VAR=secret` (visible in docker inspect and the run cmdline), write the
# secret to a private host tmpfile and bind-mount it read-only at /run/secrets/<name>;
# the container entrypoint reads /run/secrets/* back into the env (filename uppercased
# → var name). SECRET_ARGS holds the -v mounts; SECRET_FILES the tmpfiles to clean up.
SECRET_FILES=()
SECRET_ARGS=()

# add_secret_mount <name> <value> — register a secret mounted at /run/secrets/<name>.
# No-op on an empty value (e.g. an optional, unset token).
add_secret_mount() {
	local name="$1" value="$2" f
	[[ -n "$value" ]] || return 0
	f="$(mktemp "${TMPDIR:-/tmp}/dc-secret.XXXXXX")" || return 1
	chmod 600 "$f"
	printf '%s' "$value" >"$f"
	SECRET_FILES+=("$f")
	SECRET_ARGS+=(-v "$f:/run/secrets/$name:ro")
}

# cleanup_secrets — shred the host tmpfiles (call after `docker run` returns).
cleanup_secrets() {
	[[ ${#SECRET_FILES[@]} -gt 0 ]] && rm -f "${SECRET_FILES[@]}"
	SECRET_FILES=()
}

# Platform-specific "not found" exit code from the keychain CLI.
if [[ "$(uname)" == "Darwin" ]]; then
	KEYCHAIN_NOTFOUND_RC=44 # errSecItemNotFound
else
	KEYCHAIN_NOTFOUND_RC=1 # secret-tool / libsecret
fi

# Pure passthrough to the OS keychain; stdout + exit code verbatim, no policy.
_keychain_read() {
	local service="$1" account="${2:-}"
	if [[ "$(uname)" == "Darwin" ]]; then
		if [[ -n "$account" ]]; then
			security find-generic-password -s "$service" -a "$account" -w 2>/dev/null
		else
			security find-generic-password -s "$service" -w 2>/dev/null
		fi
	else
		if [[ -n "$account" ]]; then
			secret-tool lookup service "$service" account "$account" 2>/dev/null
		else
			secret-tool lookup service "$service" 2>/dev/null
		fi
	fi
}

# Required secret: prints an Error and aborts if missing or unreadable.
keychain_require() {
	local service="$1" account="$2" label="$3" hint="$4" value rc=0
	value=$(_keychain_read "$service" "$account") || rc=$?
	if ((rc == 0)); then
		printf '%s' "$value"
	elif ((rc == KEYCHAIN_NOTFOUND_RC)); then
		echo "Error: $label not found in keychain (service=$service${account:+, account=$account})." >&2
		[[ -n "$hint" ]] && echo "$hint" >&2
		exit 1
	else
		echo "Error: keychain lookup failed for $label (rc=$rc)." >&2
		exit "$rc"
	fi
}

# Optional secret: prints a Warning and returns empty if missing or unreadable.
keychain_optional() {
	local service="$1" account="$2" label="$3" hint="$4" value rc=0
	value=$(_keychain_read "$service" "$account") || rc=$?
	if ((rc == 0)); then
		printf '%s' "$value"
	elif ((rc == KEYCHAIN_NOTFOUND_RC)); then
		echo "Warning: $label not found in keychain (service=$service${account:+, account=$account}); continuing without it." >&2
		[[ -n "$hint" ]] && echo "$hint" >&2
	else
		echo "Warning: keychain lookup failed for $label (rc=$rc); continuing without it." >&2
	fi
}
