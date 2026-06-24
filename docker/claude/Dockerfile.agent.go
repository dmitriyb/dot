# Dockerfile.agent.go — Go stack layer on the language-agnostic agent base.
#
# The base (claude-dev-agent-base) carries the harness; this adds ONLY the Go
# toolchain a Go project needs to build/test. Each stack gets its own thin layer
# (rust, zig, …) — never bundled together, so a Go run never ships a Rust/Zig
# compiler. `golang` pulls golang-src (the std library source go build needs);
# weak deps are off to avoid the rest of the recommends.
ARG AGENT_BASE=claude-dev-agent-base
FROM ${AGENT_BASE}

USER root
RUN dnf install -y --setopt=install_weak_deps=False golang && dnf clean all
USER dev

# Fail the build if the toolchain is broken.
RUN go version

WORKDIR /workspace
CMD ["/bin/bash"]
