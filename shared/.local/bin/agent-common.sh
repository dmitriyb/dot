# agent-common.sh — shared host-side helpers for the container launchers.
#
# Sourced, not executed. Canonical home for the cross-platform keychain reads,
# the resident no-touch signing-agent bring-up, and path resolution. `dca`
# sources this; `docker-claude` still carries its own inline copies (a later
# refactor should switch it to this lib to remove the duplication).

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

# Ephemeral signing agent: sets SIGN_SOCK and loads ONLY the no-touch sign-only
# key (identified by hash). The resident key is pulled off the YubiKey at launch
# (PIN + 1 touch); its handle file is removed once loaded. The agent is killed
# and its socket removed on script exit (trap), so nothing is left at rest.
start_signing_agent() {
	if [[ ! -s "$SIGNING_HASH_FILE" ]] || ! grep -qiE '^[[:space:]]*[0-9a-f]{64}[[:space:]]*$' "$SIGNING_HASH_FILE"; then
		echo "Error: no signing-key hash configured in $SIGNING_HASH_FILE." >&2
		echo "Add one with: printf '%s' '<app-suffix>' | sha256sum" >&2
		exit 1
	fi
	SIGN_SOCK="$(mktemp -u "${TMPDIR:-/tmp}/dca-agent.XXXXXX.sock")"
	eval "$(ssh-agent -a "$SIGN_SOCK")" >/dev/null
	SIGN_PID="$SSH_AGENT_PID"
	trap 'kill "$SIGN_PID" 2>/dev/null; rm -f "$SIGN_SOCK"' EXIT
	local dir key
	dir="$(mktemp -d)"
	(cd "$dir" && ssh-keygen -K -N "" >/dev/null) # download resident creds (PIN + touch)
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

# start_file_agent <keyfile> — ephemeral ssh-agent holding ONLY <keyfile> (a
# plain no-touch file key, for the disposable sandbox). Sets SIGN_SOCK; torn down
# on exit. Same forwarded-agent contract as start_signing_agent — the container
# can't tell whether the key came from a file or the YubiKey; only the fingerprint
# matters. The production path uses start_signing_agent (resident YubiKey key).
start_file_agent() {
	local keyfile="$1"
	[[ -f "$keyfile" ]] || { echo "Error: role key not found: $keyfile" >&2; exit 1; }
	SIGN_SOCK="$(mktemp -u "${TMPDIR:-/tmp}/dca-agent.XXXXXX.sock")"
	eval "$(ssh-agent -a "$SIGN_SOCK")" >/dev/null
	SIGN_PID="$SSH_AGENT_PID"
	trap 'kill "$SIGN_PID" 2>/dev/null; rm -f "$SIGN_SOCK"' EXIT
	SSH_AUTH_SOCK="$SIGN_SOCK" ssh-add "$keyfile" >/dev/null 2>&1 \
		|| { echo "Error: failed to load role key $keyfile into agent" >&2; exit 1; }
}
