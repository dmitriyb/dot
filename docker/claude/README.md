# Docker Claude Code

Isolated Claude Code environments running in Fedora containers with full dotfiles, SSH agent forwarding (YubiKey), and separate personal/work images.

## What's inside

**Base** (shared): Fish, tmux, neovim (with plugins), starship, eza, bat, fzf, zoxide, lazygit, direnv, glow, Nix (single-user, flakes enabled, with nix-direnv), Claude Code (native binary), and the spec-driven trio — [beads_rust](https://github.com/Dicklesworthstone/beads_rust) (`br`), [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) (`bv`) and [spex](https://github.com/dmitriyb/spexmachina), plus [faber](https://github.com/dmitriyb/faber) for `faber validate` only (no docker socket in the container, so `build`/`run` stay host-side).

**Personal**: + Zig and Rust. No MCP servers. Fast startup.

**Work**: + Bun (for MCP servers), SSH server for IDEA Remote Development, timeout tuning for large repos. Repos live on a native ext4 volume (not VirtioFS) for performance.

## Setup

Store your personal OAuth token (from `claude setup-token`) in the OS keychain:

```bash
# macOS
security add-generic-password -s anthropic -a personal -w '<token>'

# Arch Linux
secret-tool store --label='anthropic' service anthropic account personal
```

Work account credentials are picked up automatically from the OS keychain (stored by `claude login`).

Optionally, store GitHub CLI tokens so `gh` works in-container without on-disk auth state:

```bash
# macOS
security add-generic-password -s gh -a personal -w '<PAT>'
security add-generic-password -s gh -a work     -w '<PAT>'

# Arch Linux
secret-tool store --label='gh personal' service gh account personal
secret-tool store --label='gh work'     service gh account work
```

Tokens are passed in as `GH_TOKEN` at container start. If absent, `gh` just stays unauthenticated — no error.

## Usage

`docker-claude` is the single entrypoint; everything is a subcommand.

```bash
docker-claude personal             # Personal account (Max subscription via OAuth)
docker-claude work                 # Work account (via wire proxy)
docker-claude personal -r          # Rebuild images, then launch personal
docker-claude personal --no-cache  # Full fresh rebuild (re-downloads everything)
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

The `curl … | sh` installers in these Dockerfiles (`starship`, `nix`, `claude`, `beads_rust` in
base; `rustup` in personal; `bun` in work) are **not script-pinned**. TLS is the trust
boundary, and that is stated honestly rather than dressed up.

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
- **`lazygit` (and `bv`) — transparency-log verified (implemented).** Installed with `go install`,
  not a `curl … | sh`: the Go toolchain checks every module against `sum.golang.org`, a public
  append-only transparency log that is independent of the download origin, and refuses a mismatch.
  This replaced the `atim/lazygit` COPR, which upstream marked unmaintained and which has no
  successful `fedora-44` build (a signed rpm repo would have been stronger still, but Fedora does
  not package lazygit).
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
- **Separate auth**: personal uses `CLAUDE_CODE_OAUTH_TOKEN` (keychain), work uses the wire proxy (started host-side via the `jbcentral` CLI; the container reaches it through `host.docker.internal`); `gh` CLI uses `GH_TOKEN` from keychain (optional)
- **Persistent volumes**: `claude-personal-repos` / `claude-work-repos` (cloned repos; work on native ext4), `claude-fish-data-personal` / `claude-fish-data-work` (fish history), `claude-tmux-data-personal` / `claude-tmux-data-work` (tmux resurrect). Neovim plugins and the Claude binary are baked into the image. Claude Code's own state piggybacks on the repo volume rather than a dedicated volume: session transcripts (`projects/`) and prompt history (`history.jsonl`) are symlinked from `~/.claude` into `/workspace/.claude-state` by the entrypoint, and per-project trust is regenerated into `~/.claude.json` from the `/workspace` subdirectories on every boot (so trust never re-prompts, with no stale entries or cached state).
- **faber config mount** (personal only): the host's `~/.config/faber` — every project's orchestrator/hooks/skills and, since `faber-epic` runs from the project dir, every project's `.faber/runs/` (journals, box results, `--sessions` transcripts) — is bind-mounted read-write at the same path, resolved through its stow symlink. The in-container agent reads run journals and edits workflow config in place; runs are written only by the host-side faber. `faber validate` works in-container (nix, no daemon); `faber build`/`run` do not, by design.
- **SSH agent forwarding**: the host agent is forwarded, so YubiKey touch-signing works for git inside the container.
- **IDEA access**: dedicated ed25519 key for SSH, auto-generated per machine at build time
- **MCP servers**: work entrypoint filters to only Docker-compatible servers (ijproxy via host IDE, Context7, PluginModelAnalyzer)
- **Nested tmux**: container uses `C-b` prefix, `ctrl+arrow` for window nav (host uses `C-a`, `shift+arrow`)
- **Images are built per-machine**: `HOST_UID` build arg matches container user to host UID
