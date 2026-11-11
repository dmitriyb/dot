# goose-local — scratch faber project for local-model agents

Phase-B test harness: faber 0.3.0 drives a **goose** box (declarative invoke
profile) against an OpenAI-compatible inference server on the container host —
LM Studio serving `qwen/qwen3.8-27b`. Companion to the faber-free Phase A in
`dot/docker/goose-local/`. Playground, not production: no egress lock, no
portitor, dummy API key, default bridge network.

## Run

LM Studio side first (see `dot/docker/goose-local/README.md` for the full
checklist): model loaded, server on :1234, `curl :1234/v1/models` shows the id.

```sh
cd ~/.config/faber/goose-local     # or the dot checkout path
faber validate --config "$PWD/orchestrator.yaml"
faber build    --config "$PWD/orchestrator.yaml"
faber run hello-flow --config "$PWD/orchestrator.yaml" \
  --param task='...'
```

`--config` MUST be an absolute path — relative hook/overlay paths reach the
docker wiring unresolved otherwise (same guard `faber-epic` codifies).

## What this proved (2026-08-18, faber 0.3.0, goose-cli 1.13.1)

End to end green: faber renders the goose-dialect argv from the
`invoke_profiles` block, the box reaches the host endpoint, the model executes
tool calls, and the agent writes `$FABER_RESULT_DIR/output.json` which faber
validates into `steps.<id>.outputs`.

## Schema/behavior findings (probed against the deployed 0.3.0 binary)

- `invoke_profiles:` is a top-level map; there is NO built-in `goose` preset —
  a template's `invoke.profile` must name a profile declared here. Resolved
  profiles gain `model_flag: --model` by default (goose accepts it).
- An EMPTY `effort_flag` means "engine default" (`--effort`, which goose
  rejects, exit 2) — the flag cannot be suppressed, and template `effort:` is
  mandatory. Routed here through goose's `--system` with a free-text effort
  string; validate accepts arbitrary strings.
- Path-bearing sections (`hooks:`, `images:` with `overlay:`) must live in
  include files: include-relative paths are resolved against the declaring
  file, inline ones leak to docker/nix relative to the caller's CWD.
- `network:`/`remote:`/`credentials:`/`identities:` are all optional — with no
  network section the box runs on the default bridge and
  `host.docker.internal` resolves (that is the point of this scratch).
- faber-box creates `/home/box` FRESH at box start: image-baked home content
  (e.g. a goose `config.yaml` package) never reaches the agent. In-box agent
  config must be written by the PRELUDE hook (`hooks/setup-goose`).
- goose 1.13.1 with no config enables its `dynamic_task` subagent builtin; the
  27B model delegates to it and the nested loop wedges against the slow local
  endpoint (2 wedged runs killed). Prompt-level steering did not stop it;
  `enabled: false` in the prelude-written config did.
- Bound the agent: `--no-session --max-turns 25` in `fixed_flags` (an
  unbounded local model once tried to hand-compile a C downloader to fetch a
  missing interpreter).

## Files

- `orchestrator.yaml` — substrate + invoke profile + template + workflow.
- `images.yaml` — goose-box (include: overlay path resolves file-relative).
- `overlay.nix` — box-etc only.
- `hooks.yaml`, `hooks/task-context`, `hooks/setup-goose` — context: task →
  CONTEXT.md (+ output.json instruction); prelude: goose config.
