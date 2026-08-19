# spexmachina-li — spexmachina with a local implementer

The spexmachina box chain with the WRITING roles moved to a local model:
implement / implement-next / fix run **goose + qwen/qwen3.8-27b** (LM Studio on
the host), review / merge stay **Claude Code opus, high effort**. Skills,
hooks, workflows, keys and the gate stack are ../spexmachina's, referenced —
this directory carries only the substrate, the goose invoke profile, the two
images and the templates.

## Moving parts on top of the base stack

1. LM Studio serving the model on host :1234 — declared in ./local-llm.json
   and stood up automatically by `faber-epic` / `faber-e2e` via `llm-local up`
   (load + serve + a tool-calling preflight that fails before any paid boxes
   launch); `--no-local` skips it, manual equivalent:
   `llm-local up --project . --instance spex`.
2. `llm-sidecar up --instance spex` (part of the same bring-up) — a socat
   bridge on spex-net + the docker bridge; boxes reach the endpoint as
   `http://spex-llm:1234` (the internal net cannot reach the host, and the
   egress proxy is CONNECT-to-443-only).
3. The `goose-agent` wrapper in ./overlay.nix — writes the goose config
   (developer extension on, `dynamic_task` OFF) at exec time, because faber-box
   creates the home fresh and the base preludes are single-file mounts that
   cannot be extended. Provider/model/endpoint ride in the template env.
4. Skill delivery: goose has no slash commands; the invoke profile's
   `prompt_template` instructs the agent to read
   `/faber/skills/<skill>/SKILL.md` from the read-only skills mount.
   `skills_link` stays `.claude/skills` so the `~/.claude/skills/...`
   references inside the skill texts keep resolving.

## Run

Epic, one command (needs a gitignored ./stack.json — copy
../spexmachina/stack.example.json; same instance `spex`):

```sh
faber-epic spexmachina-li <epic-id>
```

Single bead, manual:

```sh
cd ~/.config/faber/spexmachina-li     # substrate paths are CWD-anchored
faber validate --config "$PWD/orchestrator.yaml"
faber build    --config "$PWD/orchestrator.yaml"
llm-local up --project "$PWD" --instance spex   # model + preflight + sidecar
faber run bead --config "$PWD/orchestrator.yaml" --param repo=spexmachina --param bead=<id>
```

Rehearse on the playground first: `faber-e2e run --project
~/.config/faber/faber-stack-service-li` (see that project's README).

## Ported, not yet exercised — verify before first real run

- Cross-directory references (`../spexmachina/*.yaml` includes, the base
  overlay path, keys, get-token) — `faber validate` passes, but build/run
  path resolution for the overlay and host key is exercised only at
  `faber build` / `faber run`.
- The `claude_code_oauth_token` file-mode secret: whether faber injects it
  into every box or only claude ones — if it reaches the goose boxes, the
  local-model box carries a Claude credential it does not need.
- `spex-box` here is meant to hash identically to the base project's so the
  built claude images are reused — confirm the tag matches at `faber build`.
- Budgets: do not pass `--budget` to goose templates — the engine default
  `budget_flag` (`--max-budget-usd`) is not a goose flag.
- The skill texts were written for Claude Code (slash-command framing,
  `@~/.claude/skills/...` references). The read-instruction port delivers
  their content, but a 27B local model may need slimmer, goose-native
  recipes — the invoke-profile plan's recipe route is the follow-up if e2e
  shows it.
