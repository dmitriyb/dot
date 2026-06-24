# dca-egress-proxy — a tiny allow-listing forward proxy. It sits on both the
# internal dca network (agent-facing) and a normal bridge (internet), and only
# proxies HTTPS CONNECT to the Anthropic API (see filter). It holds no secrets —
# it just constrains where the agent can talk.
#
#   docker build -t dca-egress-proxy docker/claude/egress
FROM alpine:3.20
RUN apk add --no-cache tinyproxy
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY filter /etc/tinyproxy/filter
EXPOSE 8888
# Run in the foreground; tinyproxy drops to the tinyproxy user per the config.
CMD ["tinyproxy", "-d", "-c", "/etc/tinyproxy/tinyproxy.conf"]
