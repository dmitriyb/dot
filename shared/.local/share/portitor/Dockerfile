# portitor gate image — SELF-CONTAINED, built entirely from dot (no portitor
# checkout). The gate runs the VERIFIED portitor v0.1.0 RELEASE binary and adds
# `br`, which the repo's content_rules bead-close check shells out to inside the
# gate to parse .beads/issues.jsonl. The runtime contract (sshd + forced-command
# wiring) is supplied by gate-entrypoint.sh, a dot-maintained copy of portitor's
# deploy entrypoint — so no source tree is needed to build or run the gate.
#
#   docker build -t portitor \
#     --build-arg PORTITOR_VERSION=v0.1.0 [--build-arg TARGETARCH=arm64] .
#
# faber-stack builds this automatically when the `portitor` image is missing.

ARG ALPINE_VERSION=3.20

# --- fetch + verify the portitor release binary ------------------------------
# Runs portitor's OWN signed install.sh: we verify install.sh with the shared
# release-signing key, and install.sh then verifies the release archive it pulls
# (ssh-keygen -Y verify). It auto-detects os/arch via uname, so the build-stage
# platform (linux + the target arch) selects the correct linux binary — never the
# host's darwin build. No archive names or arch tokens are hand-coded here.
FROM alpine:${ALPINE_VERSION} AS fetch
ARG PORTITOR_VERSION=v0.1.0
RUN apk add --no-cache curl openssh-keygen tar
WORKDIR /fetch
RUN printf '%s\n' \
    'dvbozhko@gmail.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIhmCWVDP/Tcm3CqXNjTQTChbKxr223xMob9zc56Uuny' \
    > allowed_signers
RUN set -eu; \
    base="https://github.com/dmitriyb/portitor/releases/download/${PORTITOR_VERSION}"; \
    curl -fsSLO "${base}/install.sh"; \
    curl -fsSLO "${base}/install.sh.sig"; \
    ssh-keygen -Y verify -f allowed_signers -I dvbozhko@gmail.com -n file \
        -s install.sh.sig < install.sh; \
    mkdir -p /out; \
    VERSION="${PORTITOR_VERSION}" INSTALL_DIR=/out sh install.sh

# --- runtime: git-over-ssh gate (portitor's contract) + br for content checks -
FROM alpine:${ALPINE_VERSION}
# git/openssh-server/tini/github-cli reproduce portitor's runtime; gcompat+libgcc
# let the glibc `br` binary run on musl Alpine (br needs libgcc_s.so.1).
RUN apk add --no-cache git openssh-server tini github-cli curl gcompat libgcc \
    && adduser -D -s /bin/sh git \
    # adduser -D leaves the account locked (! in shadow); sshd refuses pubkey
    # login to a locked account ("invalid user"). Mark it valid-but-passwordless.
    && sed -i 's/^git:!/git:*/' /etc/shadow \
    && mkdir -p /srv/git /home/git/.ssh \
    && chown -R git:git /srv/git /home/git \
    && chmod 700 /home/git/.ssh \
    # key-only sshd
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# br (beads_rust): pinned by the sha256 of the installer SCRIPT (the tool version
# it fetches still floats); bump the hash on a legit upstream script change:
#   curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh | sha256sum
RUN curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh -o /tmp/br.sh \
    && echo "c398f2fbfbb5facaf255fd52cca22bb3ffe90f0a6e4660e4c34213a9c39863aa  /tmp/br.sh" | sha256sum -c - \
    && sh /tmp/br.sh && rm /tmp/br.sh \
    && cp "$HOME/.local/bin/br" /usr/local/bin/br \
    && chmod 0755 /usr/local/bin/br \
    && br --version

COPY --from=fetch /out/portitor /usr/local/bin/portitor
COPY gate-entrypoint.sh /usr/local/bin/portitor-entrypoint
RUN chmod +x /usr/local/bin/portitor-entrypoint

EXPOSE 22
VOLUME ["/srv/git"]
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/portitor-entrypoint"]
