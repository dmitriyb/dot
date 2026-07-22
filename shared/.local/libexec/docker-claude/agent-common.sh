# agent-common.sh — shared host-side helpers for docker-claude.
#
# Sourced, not executed. Single source of truth for the cross-platform keychain
# reads, the personal signing-agent bring-up, and path resolution. Sourced by
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

# ---- resident no-touch signing key (the role identity for autonomous runs) ----

# Committed list of SHA-256 hashes identifying the sign-only / no-touch resident
# key(s). Only hashes are stored, never the key name.
SIGNING_HASH_FILE="$HOME/.ssh/signing-key-hashes"

_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum | awk '{print $1}'
	else
		shasum -a 256 | awk '{print $1}'
	fi
}

# True if the given key handle's application suffix is listed in SIGNING_HASH_FILE.
_is_signing_key() {
	local suffix h
	suffix="${1##*_sk_rk_}"
	h="$(printf '%s' "$suffix" | _sha256)"
	grep -vE '^[[:space:]]*(#|$)' "$SIGNING_HASH_FILE" 2>/dev/null | grep -qix "$h"
}

# start_personal_signing_agent — interactive `docker-claude --agent` (personal) mode.
# Loads ONLY the personal no-touch sign-only key, identified by HASH (SIGNING_HASH_FILE).
# The resident key is pulled off the YubiKey at launch (PIN + 1 touch); the handle file
# is removed once loaded; the agent + socket are torn down on exit (trap), so nothing is
# left at rest.
start_personal_signing_agent() {
	if [[ ! -s "$SIGNING_HASH_FILE" ]] || ! grep -qiE '^[[:space:]]*[0-9a-f]{64}[[:space:]]*$' "$SIGNING_HASH_FILE"; then
		echo "Error: no signing-key hash configured in $SIGNING_HASH_FILE." >&2
		echo "Add one with: printf '%s' '<app-suffix>' | sha256sum" >&2
		exit 1
	fi
	SIGN_SOCK="$(mktemp -u "${TMPDIR:-/tmp}/dc-agent.XXXXXX.sock")"
	eval "$(ssh-agent -a "$SIGN_SOCK")" >/dev/null
	SIGN_PID="$SSH_AGENT_PID"
	trap 'kill "$SIGN_PID" 2>/dev/null; rm -f "$SIGN_SOCK"' EXIT
	local dir key; dir="$(mktemp -d)"
	( cd "$dir" && ssh-keygen -K -N "" >/dev/null ) # download resident creds (PIN + touch)
	shopt -s nullglob
	for key in "$dir"/id_*_sk_rk_*; do
		[[ "$key" == *.pub ]] && continue
		if _is_signing_key "$key"; then
			SSH_AUTH_SOCK="$SIGN_SOCK" ssh-add "$key" >/dev/null 2>&1
		fi
	done
	rm -rf "$dir"
	if [[ "$(SSH_AUTH_SOCK="$SIGN_SOCK" ssh-add -L 2>/dev/null | grep -c .)" != 1 ]]; then
		echo "Warning: signing agent does not hold exactly one key." >&2
	fi
}
