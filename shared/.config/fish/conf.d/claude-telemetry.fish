# Host Claude Code sessions -> the per-workstation edge collector (otel-edge,
# localhost:4317), which buffers and forwards to the home collector. Host
# sessions are personal by definition (work runs inside dcw containers, which
# get none of this). Aggregates only: session/account labels off; the
# per-shell service.instance.id keeps concurrent sessions' counters distinct.
# Shell-level env ON PURPOSE: an env block in shared/.claude/settings.json
# would be copied into WORK containers by the entrypoints.
# Opt out for a shell: set -gx CLAUDE_NO_TELEMETRY 1 (before starting claude).
if not set -q CLAUDE_NO_TELEMETRY; and command -q uuidgen
    set -gx CLAUDE_CODE_ENABLE_TELEMETRY 1
    set -gx OTEL_METRICS_EXPORTER otlp
    set -gx OTEL_EXPORTER_OTLP_PROTOCOL grpc
    set -gx OTEL_EXPORTER_OTLP_ENDPOINT http://localhost:4317
    set -gx OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE cumulative
    set -gx OTEL_RESOURCE_ATTRIBUTES "account=personal,surface=host,service.instance.id="(uuidgen | tr '[:upper:]' '[:lower:]')
    set -gx OTEL_METRICS_INCLUDE_SESSION_ID false
    set -gx OTEL_METRICS_INCLUDE_ACCOUNT_UUID false
    set -gx OTEL_METRICS_INCLUDE_VERSION false
end
