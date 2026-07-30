# Plan: Centralized personal Claude Code usage aggregation via OpenTelemetry

## Context

**Problem.** On an individual Claude subscription (Pro/Max) authenticated via OAuth, Anthropic exposes **no** account-wide, exact token/cost ledger — only rate-limit percentages (`/usage`) and a per-machine, approximate local heuristic. The Console dashboard (`platform.claude.com/usage`) only reflects **API-key** usage; Org Analytics only exists for Teams/Enterprise. `/insights` and `/usage` read **local `.jsonl` transcripts on the current machine only.**

**Why this bites us specifically.** We run Claude Code primarily **inside ephemeral containers**. When a container is torn down, its local transcripts and session cost history go with it. So `/insights`/`/usage` on the host see almost nothing (the report showed "3 sessions · 5 messages"), even though real weekly usage is ~84% of the limit — tens of millions of tokens.

**Key realization.** Token counts are *not* the problem — every Messages API response returns an exact `usage` object (input/output/cacheRead/cacheCreation), regardless of auth method, and Claude Code already reads it. Switching harness (e.g. Pi) changes nothing: on subscription OAuth there is no server ledger, and any harness in an ephemeral box loses local data identically. **The missing piece is durable, centralized aggregation.**

**Intended outcome.** A single always-on collector that every *personal* Claude Code container pushes exact token+cost telemetry to, backed by a queryable dashboard — the account-wide ledger the subscription doesn't provide. Work usage is already covered by reliable instruments and is out of scope (kept separate via an `account=personal` tag or simply by not instrumenting work containers).

## Design

**Principle:** many ephemeral clients → one durable collector. Containers hold no state; they push each request's usage live over OTLP the moment it happens.

```
personal container A ─┐
personal container B ─┼─(OTLP push, live)→  COLLECTOR → STORE → DASHBOARD
personal container C ─┘                     (the only always-on component)
```

**No custom code on either side** — the client is built into Claude Code; the server is off-the-shelf images wired by config.

| You write (config only)            | Already exists (run / point at)              |
| ---------------------------------- | -------------------------------------------- |
| `docker-compose.yml`               | `otel/opentelemetry-collector` image         |
| `otel-collector-config.yaml`       | `prom/prometheus` image                      |
| `prometheus.yml`                   | `grafana/grafana` image                      |
| Grafana `dashboard.json`           | Claude Code's built-in OTEL exporter (client)|
| 5 env vars per container           |                                              |

### Client side (each personal container)
Set env only:
```
CLAUDE_CODE_ENABLE_TELEMETRY=1
OTEL_METRICS_EXPORTER=otlp
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_EXPORTER_OTLP_ENDPOINT=http://<collector>:4317
OTEL_RESOURCE_ATTRIBUTES=account=personal
# optional: OTEL_LOGS_EXPORTER=otlp   (for events, not needed for token totals)
```
Emitted metrics of interest: `claude_code.token.usage` (attrs: type, model, session.id, user.email, + `account=personal`), `claude_code.cost.usage`, `claude_code.session.count`, `claude_code.lines_of_code.count`.

### Server side (the one durable stack)
`docker-compose` with three services:
- **otel-collector** — OTLP receiver on `:4317` (grpc) / `:4318` (http); exports to Prometheus.
- **prometheus** — stores metrics.
- **grafana** — dashboard reading Prometheus; one board: personal tokens (7d/rolling) total, by model, by session; cost.

### The one hard constraint
OTLP is a **live push with no durable client-side buffering** — if the collector is down when a session runs, that data is dropped. So the collector must be up whenever personal containers run. **Decision needed at build time: where the collector lives** (see Open Decision).

### Cardinality knob
`session.id` / account UUID as metric labels can bloat Prometheus. Claude Code exposes toggles (`OTEL_METRICS_INCLUDE_SESSION_ID`, `OTEL_METRICS_INCLUDE_ACCOUNT_UUID`, `OTEL_METRICS_INCLUDE_VERSION`) — confirm exact names against docs at build time and disable per-session labels on the metrics pipeline if we only need aggregates (keep session detail in the logs/events pipeline if wanted).

## Open Decision (resolve before implementing)

**Where does the always-on collector live?** — the only fork that changes networking/durability:
1. **On the Mac host** (recommended if containers run on the Mac): compose stack on the Mac, containers reach `host.docker.internal:4317`. Zero infra/cost; collects only while Mac is on (== when containers run anyway). No TLS/auth needed (loopback).
2. **Home server / VPS**: always-on, multi-machine, reachable anywhere; requires public endpoint + TLS + `OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer …"`.
3. **Managed backend** (Grafana Cloud free tier / Honeycomb): no infra to run; just endpoint + token in each container. Data lives in a third party; free-tier retention caps.

## Files to create (once decision is made)
Proposed home: a self-contained dir in the repo, e.g. `dot/observability/claude-usage/`:
- `docker-compose.yml`
- `otel-collector-config.yaml`
- `prometheus.yml`
- `grafana/dashboard.json` + datasource provisioning
- `.env.example` (collector endpoint) and the container env snippet to inject into personal Claude Code containers

## Verification
1. Bring up the stack: `docker compose up -d`; confirm collector `:4317` reachable and Grafana `:3000` loads.
2. Start one personal container with the env vars set; run a short Claude Code session that spends tokens.
3. In Prometheus, confirm `claude_code_token_usage_total{account="personal"}` increments; check `claude_code_cost_usage`.
4. In Grafana, confirm the dashboard shows the session's exact input/output/cache tokens and cost, sliceable by model/session.
5. Tear down the container; confirm the metrics persist in Prometheus (proves durability across ephemeral containers).
6. Confirm work containers (uninstrumented, or `account=work`) do not pollute the personal view.

## Out of scope
- Work-subscription usage (already covered by reliable instruments).
- Reconstructing past, already-lost container sessions (unrecoverable — telemetry is forward-looking only).

## Notes
- All OTEL env var and metric names above are per current Claude Code monitoring docs; re-verify exact spellings at build time.
- "We'll deal with it later" — this document is the saved reference; no stack is being stood up now.
