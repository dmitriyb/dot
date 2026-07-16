# egress-proxy — a tiny allow-listing forward proxy. It sits on both the
# internal agent network (agent-facing) and a normal bridge (internet), and only
# proxies HTTPS CONNECT to the allow-listed hosts (see filter). It holds no
# secrets — it just constrains where the agent can talk.
#
#   docker build -t egress-proxy docker/claude/egress
#
# The image is GENERIC: the baked `filter` below is only a safe DEFAULT
# (api.anthropic.com only), so a bare `docker run egress-proxy` still
# allow-lists nothing else. Per-instance stacks OVERRIDE it by bind-mounting
# their own allow-list over /etc/tinyproxy/filter: faber-stack writes
# $CONFIG_DIR/egress-filter from its --allow hosts and portitor-stack.yml mounts
# it read-only at that path. See README.md ("Per-instance egress seam").
FROM alpine:3.20
# tinyproxy is the proxy itself; openssh-client provides ssh-keyscan, which
# faber-stack runs FROM this image (attached to the internal net) to pin the
# gate's ed25519 host key. busybox has no ssh-keyscan, so without this the pin
# step silently fails and the box cannot verify the gate.
RUN apk add --no-cache tinyproxy openssh-client
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY filter /etc/tinyproxy/filter    # baked default only; overridable by a bind mount (see above)
EXPOSE 8888
# Run in the foreground; tinyproxy drops to the tinyproxy user per the config.
CMD ["tinyproxy", "-d", "-c", "/etc/tinyproxy/tinyproxy.conf"]
