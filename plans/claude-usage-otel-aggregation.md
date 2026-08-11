# Plan: Centralized personal Claude Code usage aggregation via OpenTelemetry

**Status (2026-08-11, v2).** A full local prototype was built in dot, verified
end-to-end, and deliberately discarded: partial (Mac-only) operation has no
value, and the server half belongs in the planned infra repo (see Repo split).
This document is the v1 plan folded together with everything the prototype
proved — execute it against the infra repo when that exists. All "verified"
claims below were tested live on 2026-08-11.

## Context

**Problem.** On an individual Claude subscription (Pro/Max, OAuth) Anthropic
exposes **no** account-wide token/cost ledger — no REST endpoint, no Console
view (Console covers API keys only; Org Analytics is Teams/Enterprise). OAuth
exposes only rate-limit percentages (`/usage`). Exact token counts exist solely
client-side, in each session's API responses — and personal sessions run mostly
in ephemeral containers whose local transcripts die with the container.

**Intended outcome.** One durable collector endpoint that *every* personal
Claude Code surface pushes exact token+cost telemetry to, backed by a queryable
dashboard: the account-wide ledger the subscription doesn't provide. Work usage
is out of scope (separate instruments; work containers stay uninstrumented).

**Surfaces to cover (all three — no partial solution):**
1. `dcp` personal containers (docker-claude) — seams verified.
2. Host interactive sessions — host == personal by definition.
3. Faber boxes (autonomous agents on isolated instance networks).

## Resolved decisions

- **Cardinality: aggregates only.** No `session.id` / account-UUID metric
  labels (constant series count vs ~20–50k dead series/year). Per-session
  detail, if ever wanted, goes through an OTLP logs pipeline, not metrics.
- **Deployment: home server**, as a documented service in the future infra
  repo. No Mac-local operation phase.
- **Auth: a discoverable endpoint requires a real handshake** — obscurity is
  not encryption. See Auth below.

## Topology: edge/gateway collectors

OTEL collectors both receive and send OTLP, so they chain. Producers always
push to a stable machine-local address; only the edge collector's upstream
ever changes.

```
host session ──────┐
dcp container A ───┼─OTLP→ edge collector (per workstation)
dcp container B ───┤         └─OTLP, mTLS/tunnel, queue+retry→ home-server collector → prometheus → grafana
faber box (inst X)─┘                                            (infra repo)
```

Why an edge collector per workstation instead of pushing cross-machine
directly: (a) clients never reconfigure when the server side moves; (b) the
collector's sending queue retries across link-down windows — client SDKs
cannot (Claude Code's exporter fails soft and silently drops; verified in
docs); (c) it terminates the faber instance networks locally (below).

## Per-surface wiring (client side, lives in dot)

### 1. dcp containers — verified seams

`shared/.local/bin/docker-claude`: personal mode has TWO `docker run` sites
(agent mode and normal mode — both must get the args; work mode untouched).
The verified args block, mirroring the `WORK_COMMON_ARGS` pattern:

```bash
PERSONAL_OTEL_ARGS=()
if [[ -z "${DOCKER_CLAUDE_NO_TELEMETRY:-}" ]]; then
  PERSONAL_OTEL_ARGS=(
    -e CLAUDE_CODE_ENABLE_TELEMETRY=1
    -e OTEL_METRICS_EXPORTER=otlp
    -e OTEL_EXPORTER_OTLP_PROTOCOL=grpc
    -e OTEL_EXPORTER_OTLP_ENDPOINT="${DOCKER_CLAUDE_OTEL_ENDPOINT:-http://host.docker.internal:4317}"
    -e OTEL_RESOURCE_ATTRIBUTES="account=personal,service.instance.id=$(uuidgen | tr '[:upper:]' '[:lower:]')"
    -e OTEL_METRICS_INCLUDE_SESSION_ID=false
    -e OTEL_METRICS_INCLUDE_ACCOUNT_UUID=false
    -e OTEL_METRICS_INCLUDE_VERSION=false
  )
  # Linux: host.docker.internal is Docker-Desktop-only; map to the host gateway.
  # (No --add-host exists anywhere in the repo today — the work JetBrains URL
  # has the same latent gap on Linux.)
  [[ "$(uname)" != "Darwin" ]] && PERSONAL_OTEL_ARGS+=(--add-host=host.docker.internal:host-gateway)
fi
# inject as ${PERSONAL_OTEL_ARGS[@]+"${PERSONAL_OTEL_ARGS[@]}"} into BOTH personal run sites
```

- **`service.instance.id` per-run UUID is load-bearing:** with session.id
  disabled, two concurrent containers emit *identical* cumulative-counter
  series from independent SDKs — last-write-wins corrupts `increase()`. The
  per-run UUID keeps series distinct at bounded cardinality; dashboards
  `sum()` over it.
- Env var names, toggle defaults (`SESSION_ID`/`ACCOUNT_UUID` default true,
  `VERSION` false) and fail-soft behavior re-verified against
  code.claude.com/docs/en/monitoring-usage (claude-code 2.1.220).
- Plain `-e` is fine while nothing is secret. If a bearer token is ever used,
  `OTEL_EXPORTER_OTLP_HEADERS` goes via `add_secret_mount` (the
  `/run/secrets/*` → uppercased-env entrypoint convention yields the var for
  free) — never `-e`.

### 2. Host sessions

Same five env vars in the host environment, `OTEL_RESOURCE_ATTRIBUTES` with a
distinguishing attr (e.g. `surface=host`). **Seam caveat (verified):** an
`env` block in stowed `shared/.claude/settings.json` is the wrong place — the
entrypoints copy that file into containers, including WORK ones. Use
shell-level env in the stow packages (fish config), or first verify what the
work entrypoint copies.

### 3. Faber boxes

Boxes sit on internal `${INSTANCE}-net` with only gate + egress as outbound
paths. Do NOT route OTLP through tinyproxy (HTTP CONNECT + Node OTLP
exporters that don't honor proxy env = fragile). Instead:
- The edge collector joins each instance network (`docker network connect`,
  done by `faber-stack up`, same as gate/egress join it) under a stable alias.
- Boxes get the env block with `OTEL_EXPORTER_OTLP_ENDPOINT=http://<alias>:4317`
  and `instance=<name>` in resource attrs for per-project slicing.
- No internet path opens: the collector only accepts OTLP; worst case a
  compromised box writes metrics into your own prometheus.
- **Open unknown:** where faber declares box env vars (orchestrator.yaml /
  box-launch path). If no generic env seam exists, faber needs a tiny feature.

## Server side (lives in the infra repo)

Three off-the-shelf services — compose or the infra repo's equivalent:
- **otel-collector** (`otel/opentelemetry-collector-contrib` — contrib, NOT
  core: guarantees the `prometheus` exporter and auth extensions). OTLP
  receivers on 4317/4318; prometheus exporter with
  **`resource_to_telemetry_conversion: enabled: true`** — verified critical:
  without it `account=personal` / `service.instance.id` land in `target_info`
  instead of becoming query labels.
- **prometheus** — scrapes the collector (15s interval vs the 60s client
  export so short sessions aren't missed; `honor_labels: true`), long
  retention (prototype used 5y), named volume = the ledger; document backup.
- **grafana** — provisioned datasource + one dashboard.
  **Verified gotcha:** give the provisioned datasource an explicit
  `uid` from the FIRST boot — adding a uid after Grafana has auto-assigned
  one crash-loops provisioning ("data source not found"); fix requires
  wiping grafana state.

### Verified metric facts (do not re-derive)

Confirmed by pushing Claude-Code-shaped OTLP through the collector and
querying back through Grafana:
- `claude_code.token.usage` (unit `tokens`) → stored as
  **`claude_code_token_usage_tokens_total`**, labels `account`, `model`,
  `type` ∈ {input, output, cacheRead, cacheCreation}, `service_instance_id`.
- `claude_code.cost.usage` (unit `USD`) → **`claude_code_cost_usage_USD_total`**.
- Working query shapes: stat `sum(increase(...{account="personal"}[7d]))`;
  stacked `sum by (type|model) (increase(...[$__interval]))` (interval 1h);
  daily bars with interval 1d. `increase()` on a flat counter is 0 — a
  series' pre-first-scrape accumulation is lost, bounded by one 60s export
  interval per session; acceptable.
- `user.email` remains a metric attribute even with toggles off —
  single-valued, harmless; strippable with a collector `attributes` processor.
- Image pins (Docker Hub multi-arch manifest-list digests, current at
  2026-08-11; re-resolve at build time): otel-collector-contrib 0.158.0,
  prometheus v3.13.2, grafana 13.1.3. Pin in the infra repo's own manifest
  (dot's versions.json only if dot consumes them, e.g. for the edge
  collector).

## Auth

A reachable endpoint gets a cryptographic handshake, not obscurity:
1. **Preferred: network layer** — WireGuard/Tailscale as the infra-repo-wide
   baseline. The endpoint exists only inside the tunnel; mutual key auth and
   encryption are the protocol; collector config stays plain OTLP. Every
   other self-hosted service inherits the same protection.
2. **Alternative/addition: mTLS between collectors** — receiver `tls:
   {cert_file, key_file, client_ca_file}` refuses clients without a cert
   from your CA; the edge collector's `otlp` exporter carries the client
   cert. One self-signed CA, two certs, config-only.
3. Bearer token (`bearertokenauth` extension) is hardening on top, not the
   handshake.

Blind-copy safety: committed config carries only machine-local endpoints
(`host.docker.internal`, instance-net aliases) and the per-host override env
var — a copier's telemetry lands on their own machine or nowhere. The real
endpoint + credentials live outside the repo (env/keychain/tunnel).

## Repo split

- **dot**: everything producers need — docker-claude args, host env, faber
  wiring, and the per-workstation edge collector (it runs where the
  workstation is; a `claude-usage-stack`-style stowed launcher reading pinned
  images from versions.json worked well in the prototype).
- **infra repo** (planned, does not exist yet): the server stack, auth/CA or
  tailnet membership, retention + ledger backup, and the documentation of
  this service alongside the rest of the self-hosted fleet.

## Verification (adapt from the prototype's proven sequence)

1. Server stack up; prometheus target for the collector UP; grafana loads.
2. Synthetic check without burning tokens: POST a Claude-Code-shaped OTLP
   JSON metric to the collector's 4318 (`/v1/metrics`), confirm translated
   names + `account` label at the collector's `:8889/metrics`, then in
   prometheus/grafana. Push a second, higher sample — `increase()` must show
   the delta. Wipe test series before real use (collector restart + prometheus
   volume reset, or keep a `test` account label value and filter it out).
3. Real `dcp` session → dashboard fills; container teardown → data persists.
4. `dcw` work session → zero claude_code series.
5. `DOCKER_CLAUDE_NO_TELEMETRY=1 dcp` → `docker inspect` shows no OTEL env.
6. Kill the link between edge and server mid-session → edge queue retries,
   no loss (the property direct client push cannot give).
7. Faber: box on instance net pushes via the collector alias; per-instance
   label visible; box still has no internet path (egress filter unchanged).
8. Unauthenticated/untunneled client from another machine is rejected.

## Open items

- Faber box env seam (orchestrator.yaml vs faber code) — inspect before
  planning that wiring.
- Host-session env seam — shell-level env vs settings.json copy semantics of
  the WORK entrypoint.
- Infra repo bootstrap itself (structure, tunnel baseline) — separate effort;
  this service should be one of its first documented entries.
