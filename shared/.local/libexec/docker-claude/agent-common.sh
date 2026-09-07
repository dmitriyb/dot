# agent-common.sh — sourced by docker-claude, never executed. Single source of truth
# for the cross-platform keychain reads and the /run/secrets token mounts.

# Depth-robust: launchers can live anywhere under the repo, no hardcoded `cd ../../..`.
dot_root() {
	local d="$1"
	while [[ "$d" != / && ! -d "$d/docker/claude" ]]; do d="$(dirname "$d")"; done
	if [[ ! -d "$d/docker/claude" ]]; then
		echo "Error: dot repo root not found: no ancestor of '$1' contains docker/claude." >&2
		return 1
	fi
	printf '%s\n' "$d"
}

# `-e VAR=secret` is visible in `docker inspect` and host `ps`; a 0600 tmpfile mounted
# read-only at /run/secrets/<name> is not. The container entrypoint reads it back.
SECRET_FILES=()
SECRET_ARGS=()

# No-op on an empty value: an optional token that isn't stored simply isn't mounted.
add_secret_mount() {
	local name="$1" value="$2" f
	[[ -n "$value" ]] || return 0
	f="$(mktemp "${TMPDIR:-/tmp}/dc-secret.XXXXXX")" || return 1
	chmod 600 "$f"
	printf '%s' "$value" >"$f"
	SECRET_FILES+=("$f")
	SECRET_ARGS+=(-v "$f:/run/secrets/$name:ro")
}

# Registered on EXIT, not left to the call site: `set -e` aborts before reaching
# it when `docker run` returns non-zero, leaving the token file on disk.
cleanup_secrets() {
	[[ ${#SECRET_FILES[@]} -gt 0 ]] && rm -f "${SECRET_FILES[@]}"
	SECRET_FILES=()
}
trap cleanup_secrets EXIT

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
