# agent-common.sh — sourced by docker-claude, cred-store, faber's get-token and faber-stack;
# never executed. Single source of truth for the host.conf reader and the secret-backend reads.

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

# Stdin only: `-e` and host files would expose the value to `docker inspect`, `ps` or the host
# disk, and a host file is unreadable under userns-remap. No-op on an empty value.
inject_secret() {
	local ctr="$1" name="$2" value="$3"
	[[ -n "$value" ]] || return 0
	if ! printf '%s' "$value" | docker exec -i -u dev "$ctr" sh -c 'umask 077; cat >"/run/secrets/$1"' sh "$name"; then
		echo "Error: writing secret '$name' into $ctr failed." >&2
		return 1
	fi
	if ! printf '%s' "$value" | docker exec -i -u dev "$ctr" sh -c 'test "$(sha256sum <"/run/secrets/$1")" = "$(sha256sum)"' sh "$name"; then
		echo "Error: secret '$name' in $ctr does not match the value sent." >&2
		return 1
	fi
}

HOST_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/dot/host.conf"

# key=value data stowed by the OS layer; parsed, never sourced.
host_conf() {
	local want="$1" key value
	[[ -f "$HOST_CONF" ]] || return 1
	while IFS='=' read -r key value || [[ -n "$key" ]]; do
		[[ "$key" =~ ^[[:space:]]*(#|$) ]] && continue
		if [[ "$key" == "$want" ]]; then
			printf '%s\n' "$value"
			return 0
		fi
	done <"$HOST_CONF"
	return 1
}

_secrets_backend() {
	local backend
	if ! backend="$(host_conf secrets.backend)"; then
		echo "Error: no secrets backend configured (secrets.backend in $HOST_CONF) — re-run dot's setup.sh." >&2
		return 1
	fi
	case "$backend" in
	security | secret-tool | systemd-creds) printf '%s\n' "$backend" ;;
	*)
		echo "Error: unknown secrets.backend '$backend' in $HOST_CONF." >&2
		return 1
		;;
	esac
}

# Every backend's "not found" is normalised to this; any other non-zero is a failed lookup.
SECRET_NOTFOUND_RC=44

_keychain_read() {
	local backend="$1" service="$2" account="${3:-}" rc=0
	case "$backend" in
	security)
		security find-generic-password -s "$service" ${account:+-a "$account"} -w 2>/dev/null || rc=$?
		return "$rc" # 44 is errSecItemNotFound
		;;
	secret-tool)
		secret-tool lookup service "$service" ${account:+account "$account"} 2>/dev/null || rc=$?
		((rc == 1)) && return "$SECRET_NOTFOUND_RC"
		return "$rc"
		;;
	systemd-creds)
		local dir name file
		dir="$(host_conf secrets.dir)" || {
			echo "Error: secrets.dir missing in $HOST_CONF." >&2
			return 2
		}
		name="$service${account:+.$account}"
		file="$HOME/$dir/$name.cred"
		[[ -f "$file" ]] || return "$SECRET_NOTFOUND_RC"
		# systemd-creds exits 1 on any failure, so it must not share the not-found code.
		systemd-creds decrypt --user --name="$name" "$file" - || return 2
		;;
	esac
}

keychain_store_hint() {
	local backend="$1" service="$2" account="${3:-}"
	echo "Store it with:" >&2
	case "$backend" in
	security) echo "  security add-generic-password -s $service${account:+ -a $account} -w '<value>'" >&2 ;;
	secret-tool) echo "  secret-tool store --label='$service${account:+ $account}' service $service${account:+ account $account}" >&2 ;;
	systemd-creds) echo "  cred-store $service${account:+ $account}    (reads the value from stdin, hidden on a tty)" >&2 ;;
	esac
}

keychain_require() {
	local service="$1" account="$2" label="$3" hint="$4" backend value rc=0
	backend="$(_secrets_backend)" || exit 1
	value=$(_keychain_read "$backend" "$service" "$account") || rc=$?
	if ((rc == 0)); then
		printf '%s' "$value"
	elif ((rc == SECRET_NOTFOUND_RC)); then
		echo "Error: $label not found ($backend: service=$service${account:+, account=$account})." >&2
		[[ -n "$hint" ]] && echo "$hint" >&2
		keychain_store_hint "$backend" "$service" "$account"
		exit 1
	else
		echo "Error: $backend lookup failed for $label (rc=$rc)." >&2
		exit "$rc"
	fi
}

keychain_optional() {
	local service="$1" account="$2" label="$3" hint="$4" backend value rc=0
	backend="$(_secrets_backend)" || exit 1
	value=$(_keychain_read "$backend" "$service" "$account") || rc=$?
	if ((rc == 0)); then
		printf '%s' "$value"
	elif ((rc == SECRET_NOTFOUND_RC)); then
		echo "Warning: $label not found ($backend: service=$service${account:+, account=$account}); continuing without it." >&2
		[[ -n "$hint" ]] && echo "$hint" >&2
		keychain_store_hint "$backend" "$service" "$account"
	else
		echo "Warning: $backend lookup failed for $label (rc=$rc); continuing without it." >&2
	fi
}
