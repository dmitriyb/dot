# egress-proxy — allow-listing forward proxy

A tiny [tinyproxy](https://tinyproxy.github.io/) forward proxy that constrains
where a faber box can talk on the internet. A box runs on an `internal: true`
docker network with no direct internet; its only outbound HTTPS path is this
proxy, which refuses every host that is not on its allow-list
(`FilterDefaultDeny Yes`). It holds no secrets — it only limits reach, closing
data-exfiltration and any REST/libgit2 bypass to arbitrary hosts.

## Files

| File | Role |
|------|------|
| `egress-image.nix` | builds `egress-proxy` via Nix `dockerTools` (glibc) — tinyproxy + `ssh-keyscan`; pins nixpkgs from the shared `versions.json`. `nix-build egress-image.nix && docker load -i result` (faber-stack does this for you) |
| `tinyproxy.conf` | proxy config: `CONNECT` to 443 only, private client ranges, `Filter "/etc/tinyproxy/filter"` with `FilterDefaultDeny Yes` + `FilterExtended On` + `FilterCaseSensitive Off` |
| `filter` | the **baked default** allow-list (`api.anthropic.com` only) |

## Per-instance egress seam

The image is **generic**. `filter` is baked in only as a safe default, so a bare
`docker run egress-proxy` still allow-lists nothing beyond Anthropic. Each
faber instance supplies its **own** allow-list in a thin derived image:

1. `faber-stack up --instance <name> [--allow <host> …]` writes a per-instance
   filter to `$CONFIG_DIR/egress-filter` (default config dir
   `$XDG_CONFIG_HOME/portitor/<name>/`). Each `--allow <host>` becomes one
   **anchored** extended-regex line `^<host>$` with every `.` escaped; hosts are
   validated against `^[A-Za-z0-9._-]+$` first, so a value can never widen into a
   wildcard / open proxy. With no `--allow`, the file holds the single default
   line `^api\.anthropic\.com$`.
2. `faber-stack` builds `egress-proxy-<name>` = `egress-proxy` plus that file at
   `/etc/tinyproxy/filter` (root-owned, 0644), reads it back out of the image, and
   `portitor-stack.yml` runs the `${INSTANCE}-egress` container from it. Nothing is
   bind-mounted, so the proxy works under Docker userns-remap, and a changed
   allow-list is a changed image that compose recreates the container for.

So the generic image never changes per project; only the thin per-instance layer
does. The baked `filter` remains the fallback for any direct/manual `docker run`
of the generic image.

Regenerating the filter is deterministic and wholesale (never appended), so a
`faber-stack up` re-run converges to exactly the hosts named by `--allow`.
