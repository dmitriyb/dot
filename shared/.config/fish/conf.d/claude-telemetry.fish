# Host Claude Code sessions -> the per-workstation edge collector (otel-edge,
# localhost:4317), which buffers and forwards to the home collector. Host
# sessions are personal by definition (work runs inside dcw containers, which
# get none of this). The session id keeps concurrent sessions' counters
# distinct; account labels stay off.
# Shell-level env ON PURPOSE: an env block in shared/.claude/settings.json
# would be copied into WORK containers by the entrypoints.
# Opt out for a shell: set -gx CLAUDE_NO_TELEMETRY 1 (before starting claude).
# A preset endpoint means docker-claude configured this container: keep its values.
if not set -q CLAUDE_NO_TELEMETRY; and not set -q OTEL_EXPORTER_OTLP_ENDPOINT
    set -gx CLAUDE_CODE_ENABLE_TELEMETRY 1
    set -gx OTEL_METRICS_EXPORTER otlp
    set -gx OTEL_EXPORTER_OTLP_PROTOCOL grpc
    set -gx OTEL_EXPORTER_OTLP_ENDPOINT http://localhost:4317
    set -gx OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE cumulative
    set -gx OTEL_RESOURCE_ATTRIBUTES account=personal,surface=host
    set -gx OTEL_METRICS_INCLUDE_SESSION_ID true
    set -gx OTEL_METRICS_INCLUDE_ACCOUNT_UUID false
    set -gx OTEL_METRICS_INCLUDE_VERSION false
end
