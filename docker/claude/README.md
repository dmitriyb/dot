# Docker Claude Code

Isolated Claude Code environments running in Fedora containers with full dotfiles, SSH agent forwarding (YubiKey), and separate personal/work images.

## What's inside

**Base** (shared): Fish, tmux, neovim (with plugins), starship, eza, bat, fzf, zoxide, lazygit, direnv, glow, Nix (single-user, flakes enabled, with nix-direnv), Claude Code (native binary), and the spec-driven trio — [beads_rust](https://github.com/Dicklesworthstone/beads_rust) (`br`), [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) (`bv`) and [spex](https://github.com/dmitriyb/spexmachina), plus [faber](https://github.com/dmitriyb/faber) for `faber validate` only (no docker socket in the container, so `build`/`run` stay host-side).

**Personal**: + Zig and Rust. No MCP servers. Fast startup.

**Work**: + Bun (for MCP servers), SSH server for IDEA Remote Development, timeout tuning for large repos. Repos live on a native ext4 volume (not VirtioFS) for performance.

## Setup

Each host declares in the stowed `~/.config/dot/host.conf` which modes it may build and run
and where its secrets live; docker-claude refuses anything else before it touches Docker:

| Host layer | `docker_claude.modes` | `secrets.backend` | Container on session exit |
|---|---|---|---|
| `mac` | `work` | `security` (keychain) | stopped |
| `arch` | `personal` | `secret-tool` | stopped |
| `headless` | `personal` | `systemd-creds` (see [Remote server](#remote-server)) | keeps running (`docker_claude.persist`) |

Without the file docker-claude refuses to start — re-run `setup.sh` after pulling.

Store the personal OAuth token (from `claude setup-token`) where the host's backend expects it;
a missing entry also prints the right command:

```bash
secret-tool store --label='anthropic' service anthropic account personal   # Arch
cred-store anthropic personal                                               # headless
```

Work account credentials come from the wire proxy (`jbcentral`) on the Mac.

Optionally, a GitHub CLI token per account so `gh` works in-container without on-disk auth state:

```bash
security add-generic-password -s gh -a work -w '<PAT>'                      # macOS
secret-tool store --label='gh personal' service gh account personal         # Arch
cred-store gh personal                                                      # headless
```

If absent, `gh` just stays unauthenticated — no error.

## How a session starts

1. The mode is checked against `docker_claude.modes`; the image is built if missing.
2. The host's ssh-agent is checked: unreachable refuses the start, empty warns.
3. If the mode's container (`claude-personal` / `claude-work`) is already running, it is reused and
   you get another session in it; otherwise it starts detached with an in-memory `/run/secrets`.
4. Either way, each secret is read from the host's store, written into the container over
   `docker exec` stdin and its hash compared inside the container — so an interrupted start or a
   rotated token is repaired on the next attach (shells already open keep their loaded value). No secret touches argv,
   `docker inspect`, `-e` or the host disk, and nothing depends on host file ownership, so
   userns-remap works unchanged.
5. docker-claude waits for the container's sshd (`docker_claude.start_timeout` seconds), then runs
   `ssh -A docker-personal` / `docker-work`. Login uses the dedicated, touch-free
   `~/.ssh/docker_claude_id_ed25519`; the forwarded agent only signs.
6. Inside, the login shell restores the container's environment and the secrets
   (`container-session.fish`), and `~/.ssh/rc` keeps `~/.ssh/agent.sock` pointing at the newest
   session's agent, so tmux shells keep signing after a reconnect.

## Remote server

dcp on a headless Linux host with a TPM2 and a `systemd-creds` that has `--user`, reached over SSH.
The `headless` layer's `host.conf` selects `systemd-creds` (`host+tpm2`, scoped to your UID) and
keeps the container running across disconnects and `exit`; reconnect with `dcp`, stop it with
`dcp --stop`. Run long jobs in the container's tmux: a process started directly in a session dies
with that session.

**Secrets** — the server keeps its own tokens; nothing is pushed from the laptop.
`cred-store` reads the value from stdin (hidden on a tty), encrypts it, and reads it back through
docker-claude's lookup before reporting success:

```bash
claude setup-token          # on any authenticated Claude Code; copy the token
cred-store anthropic personal
cred-store gh personal      # optional, a PAT for this server only
```

**Agent** — the laptop forwards its agent to one fixed socket path on the server, which the
server-side `ssh -A` into the container then forwards again.

Server, once (replace `<you>`):

```bash
mkdir -m 700 ~/.ssh/agent-fwd
sudo tee /etc/ssh/sshd_config.d/50-agent-fwd.conf <<'EOF'
StreamLocalBindUnlink yes

Match User <you>
    SetEnv SSH_AUTH_SOCK=/home/<you>/.ssh/agent-fwd/agent.sock
Match all
EOF
sudo sshd -t && sudo systemctl reload sshd
sudo sshd -T -C user=<you>,host=localhost,addr=127.0.0.1 | grep -iE '^(setenv|streamlocalbindunlink)'
sudo sshd -T -C user=root,host=localhost,addr=127.0.0.1 | grep -iE '^(setenv|streamlocalbindunlink)'
```

`Include /etc/ssh/sshd_config.d/*.conf` must stand near the top of `/etc/ssh/sshd_config`, before
any `Match`. The two checks must show `setenv` for you and not for root.

Laptop, in your private `~/.ssh/config` (not in this repo), before any `Host *` block:

```
Host <server>
    RemoteForward /home/<you>/.ssh/agent-fwd/agent.sock /Users/<laptop-user>/.ssh/agent.sock
    ExitOnForwardFailure yes
    ForwardAgent no
```

`ExitOnForwardFailure` makes a failed forward abort the connection instead of printing a warning.

## Usage

`docker-claude` is the single entrypoint; everything is a subcommand.

```bash
docker-claude personal             # Personal account (Max subscription via OAuth)
docker-claude work                 # Work account (via wire proxy)
docker-claude personal -r          # Rebuild images, then launch personal
docker-claude personal --no-cache  # Full fresh rebuild (re-downloads everything)
docker-claude personal --stop      # Stop and remove the running container
docker-claude -r                   # Rebuild base + this host's allowed images only
```

Aliases: `dc` (docker-claude), `dcp` (personal), `dcw` (work).

## Trust model

The in-container guardrails are `harness/managed-settings.*.json`, root-owned at
`/etc/claude-code/managed-settings.json`. They block the *honest-path* bypass (`--no-gpg-sign`,
`--no-verify`, `core.hooksPath`, and the dcw commit/push lockdown). They are **defeatable** by
design (git plumbing, libgit2, shell obfuscation) — fast feedback, **not** a wall — so they are
backstopped by the touch key (anything that slips still needs a physical touch). See
`harness/README.md`.

## Installer trust (supply chain)

The `curl … | sh` installers in these Dockerfiles (`starship`, `nix`, `claude`, `beads_rust`,
`beads_viewer` in base; `rustup` in personal; `bun` in work) are **not script-pinned**. TLS is
the trust boundary, and that is stated honestly rather than dressed up.

**Why not pin the installer script?** A committed `sha256sum -c` of the installer script is
*trust-on-first-use (TOFU)*, and its entire root of trust is a single unverified `curl`: you fetch
the script, hash whatever you received, and commit that. There is no independent, out-of-band
source to check the pin against — if you were compromised at pin time, you pin the attacker's hash
and verify against it forever. So the pin proves "same bytes as when I first fetched," **not**
"genuine bytes from upstream." The real in-transit protection is TLS (a network MITM can't
substitute the script without a valid cert for the host); the pin only adds *change-detection*,
and only has value when the artifact is **stable** — a surprise hash change is then investigable.
For these installers (`claude` changes ~weekly; the others float too) legitimate churn is constant,
so the only response to a changed hash is "re-hash and move on" — which collapses the detection
value to zero while imposing ongoing maintenance. That is theater, and it is removed.

**What genuine integrity would require** (none of which a script-hash pin provides): a detached
**signature verified against a pre-distributed public key**, a **signed OS-package repo** (rpm/apt
gpg — the distro key is the out-of-band root, which is why `dnf install …` is categorically
stronger), or **transparency-log attestation** (Sigstore/cosign, SLSA).

**Per-tool audit (2026)** — of the installers here, two clear that bar cheaply:
- **`zig` — signature-verified (implemented).** The tarball is checked with `minisign` against the
  Zig Software Foundation's long-lived public key, baked into `Dockerfile.personal` (reviewed once
  in git). This survives an origin/CDN compromise, unlike a same-origin checksum; the build also
  asserts the signed trusted-comment names the exact tarball (downgrade guard). This replaced the
  earlier `index.json` shasum, which was same-origin (weak).
- **`spex` — signature-verified (implemented).** `Dockerfile.base` fetches `install.sh` plus its
  detached `install.sh.sig` and runs `ssh-keygen -Y verify` against the release-signing Ed25519
  key baked into the Dockerfile — one long-lived key shared by spex, faber and portitor, and the
  same allowed_signers line committed in `shared/.config/faber/SETUP.md`. A pre-distributed key
  is not TOFU and does not churn per release, so this is the real thing rather than a script-hash
  pin. `install.sh` then verifies the downloaded archive against the identical key it carries; the
  build-time check adds what the self-check structurally cannot — detection of a *substituted*
  installer. Failure is fail-closed: the script never reaches `bash`.
- **`lazygit` — transparency-log verified (implemented).** Installed with `go install`,
  not a `curl … | sh`: the Go toolchain checks every module against `sum.golang.org`, a public
  append-only transparency log that is independent of the download origin, and refuses a mismatch.
  This replaced the `atim/lazygit` COPR, which upstream marked unmaintained and which has no
  successful `fedora-44` build (a signed rpm repo would have been stronger still, but Fedora does
  not package lazygit).
- **`bv` — same-origin checksum, fail-closed (implemented).** It shared lazygit's transparency-log
  path until upstream v0.25.0 began vendoring patched dependencies behind `replace` directives;
  `go install pkg@version` refuses any module whose `go.mod` carries those, and no flag overrides
  it, so that path is closed. `install.sh` now fetches the prebuilt release archive and verifies it
  against the release `checksums.txt`, refusing to install on a mismatch — the same TLS trust
  domain as the script itself, so it catches a corrupted download, not an origin compromise. The
  layer then runs `bv --version`, so an installer that exits without installing fails the build.
- **`bun` — PGP signature available, not wired in.** Oven signs `SHASUMS256.txt.asc` with a key
  published on keyservers and pinned in Bun's own repo. Genuinely verifiable, but manual (needs
  `gpg` + keyserver/baked key in the work image) and low-value for an MCP-only tool. Left on TLS.
- **`claude`, `nix`, `rustup`, `starship` — TLS is the ceiling.** No independently-anchored
  signature exists: Claude Code ships only a same-origin manifest checksum (and no npm provenance);
  Nix *dropped* GPG signing in ~2.12 (2022); rustup removed signature verification in 1.26.0 (TUF
  replacement unshipped); starship publishes only same-origin `.sha256`. Nothing to add today.

If any of the four start publishing a verifiable signature against a stable key, that is the lever
to add — not more hashing.

**What is kept** (different category — no re-hash churn, not TOFU theater):
- **`claude`** additionally verifies its downloaded *binary* against Anthropic's manifest checksum
  inside `install.sh`. (Same TLS trust domain, so it catches a corrupted download, not an origin
  compromise — but it is free and automatic.)
- **`zig`** tarball is checked against the `.shasum` fetched *dynamically* from
  `ziglang.org/download/index.json` at build time — no committed hash to maintain.
- **`cargo install --git`** uses `--locked` (upstream `Cargo.lock`) for dependency reproducibility;
  `go install …@latest` floats but is covered by the Go module checksum DB (sumdb).

## Architecture

- **Three images**: `claude-dev-base` (shared), `claude-dev-personal`, `claude-dev-work`
- **Separate auth**: personal uses `CLAUDE_CODE_OAUTH_TOKEN` (host secret backend), work uses the wire proxy (started host-side via the `jbcentral` CLI; the container reaches it through `host.docker.internal`); `gh` CLI uses `GH_TOKEN` from the host secret backend (optional). All of them are injected over `docker exec` stdin into the container's in-memory `/run/secrets`.
- **Persistent volumes**: `claude-personal-repos` / `claude-work-repos` (cloned repos; work on native ext4), `claude-fish-data-personal` / `claude-fish-data-work` (fish history), `claude-tmux-data-personal` / `claude-tmux-data-work` (tmux resurrect). Neovim plugins and the Claude binary are baked into the image. Claude Code's own state piggybacks on the repo volume rather than a dedicated volume: session transcripts (`projects/`) and prompt history (`history.jsonl`) are symlinked from `~/.claude` into `/workspace/.claude-state` by the entrypoint, and per-project trust is regenerated into `~/.claude.json` from the `/workspace` subdirectories on every boot (so trust never re-prompts, with no stale entries or cached state).
- **faber run state mount** (personal only): the host's `~/.local/state/faber` — faber's `state_dir` from `~/.config/faber/host.json`, one flat `runs/` for every project, each journal header carrying its `config_path` and workflow — is bind-mounted at the same path, live, not copied. The agent reads journals, box results and `--sessions` transcripts there; runs are written only by the host-side faber. Workflow config is not mounted: it lives in the dot repo, so edits happen in the `/workspace/dot` clone, where `faber validate` runs (nix, no daemon). `faber build`/`run` do not work in-container, by design.
- **SSH agent forwarding**: every session enters with `ssh -A`, so the container's own sshd creates the agent socket inside the container and YubiKey touch-signing works for git there. No host socket or directory is mounted.
- **SSH access (dcp/dcw sessions and IDEA)**: dedicated ed25519 key for SSH, auto-generated per machine at build time; sshd is the container's main process and is published on `127.0.0.1` only. The container's own host key is baked per image build, so `docker-claude` reads it out of the image and pins it in `~/.ssh/known_hosts.docker-claude` before each run — rebuilds never trip host-key verification, and `StrictHostKeyChecking` stays on (`shared/.ssh/config.d/docker-claude`).
- **MCP servers**: work entrypoint filters to only Docker-compatible servers (ijproxy via host IDE, Context7, PluginModelAnalyzer)
- **Nested tmux**: container uses `C-b` prefix, `ctrl+arrow` for window nav (host uses `C-a`, `shift+arrow`)
- **Images are built per-machine**: `HOST_UID` build arg matches container user to host UID
