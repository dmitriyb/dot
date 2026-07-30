# Plan: faber — move the hardcoded agent-CLI dialect into a declarative invocation profile

> **Repo:** `github.com/dmitriyb/faber` (Apache-2.0, Go). Run this from the faber repo, not dot.
> **Spec-driven:** faber's `spec/**` is authoritative (spexmachina format). Land the spec change first, then the code — same as any faber bead.

## Context

faber's README and env contract promise it "hardcodes no agent vendor" (`FABER_AGENT_CLI` has no default). But the one nondeterministic phase, `agent/box/invoke.go`, **hardcodes Claude Code's headless CLI dialect**:

```go
// agent/box/invoke.go
func (i Invocation) Prompt() string { return "/" + i.Skill + "\n\n" + i.Body /* + extra trailer */ }
func (i Invocation) Argv() []string {
    argv := []string{i.CLI, "-p", i.Prompt(), "--permission-mode", "bypassPermissions"}
    if i.Effort != ""    { argv = append(argv, "--effort", i.Effort) }
    if i.MaxBudget != "" { argv = append(argv, "--max-budget-usd", i.MaxBudget) }
    return argv
}
```

So `FABER_AGENT_CLI` swaps the **binary name, not the invocation shape** — `FABER_AGENT_CLI: goose` would emit `goose -p … --permission-mode bypassPermissions …`, which Goose rejects. This is a **policy leak in a "mechanism-only" engine**.

**Goal:** make the invocation shape *data* — a per-template invocation profile compiled into the IR and consumed by `faber-box` — so `invoke.go` becomes a pure template-expander with zero vendor knowledge. First consumer: a **`goose` profile** (the harness selected after full assessment). The existing `claude` behavior becomes the built-in default profile, reproduced **byte-for-byte** (determinism / golden IR).

**Scope note (what's already vendor-neutral, leave alone):**
- **Skills binding** — already data: `FABER_SKILLS_LINK` / `BoxSpec.SkillsLink` symlinks the read-only `/faber/skills` mount to an agent-specific `$HOME` path. No change needed.
- **Output capture** — already convention: the skill/recipe writes `/faber/result/output.json` (`contract.OutputFile`), validated against `FABER_OUTPUT_SCHEMA`. Vendor-neutral at faber's layer. No change needed.
- The **only** hardcoded thing is prompt assembly + argv flags in `invoke.go`. Keep the blast radius there.

## Design: the invocation profile

Optional per-template `invoke:` block in `orchestrator.yaml`. **Absent ⇒ built-in `claude` profile** (back-compat; the reference `examples/code-review-loop` config keeps working untouched). A named preset is sugar; inline fields override for advanced/custom CLIs.

```yaml
templates:
  implement:
    run: { env: { FABER_AGENT_CLI: goose, GOOSE_MODE: auto } }  # vendor env already allowed here
    skill: implement
    invoke:
      profile: goose            # named preset: claude | goose  (sugar)
      # inline overrides (all optional; shown to document the shape):
      subcommand: ["run"]       # tokens between CLI and prompt (goose: ["run"]; claude: [])
      prompt_flag: "-t"         # flag carrying the prompt string   (claude: "-p")
      skill_mode: flag          # prefix ⇒ "/{skill}" into prompt (claude); flag ⇒ separate arg (goose recipe)
      skill_flag: "--recipe"    # used when skill_mode: flag
      prompt_template: "{body}{extra}"     # claude default: "/{skill}\n\n{body}{extra}"
      fixed_flags: []           # claude: ["--permission-mode","bypassPermissions"]
      effort_flag: "--effort"   # omitted from argv when FABER_EFFORT empty
      budget_flag: "--budget"   # claude: "--max-budget-usd"; goose native hard-cap
```

**Two built-in presets** (encode known-good dialects so configs stay terse):

- **`claude`** (default, reproduces today exactly):
  `subcommand: []`, `prompt_flag: -p`, `skill_mode: prefix`,
  `prompt_template: "/{skill}\n\n{body}{extra}"`,
  `fixed_flags: [--permission-mode, bypassPermissions]`, `effort_flag: --effort`, `budget_flag: --max-budget-usd`.
  (`{extra}` expands to `"\n\nADDITIONAL INSTRUCTION: " + FABER_EXTRA_INSTRUCTION` or empty — preserve the current trailer verbatim.)
- **`goose`** (first new consumer — **flag values TBD against `goose run --help` at impl time**, see Open items):
  `subcommand: [run]`, `prompt_flag: -t`, `skill_mode: flag`, `skill_flag: --recipe`,
  `prompt_template: "{body}{extra}"`, `fixed_flags: []`, drop `--permission-mode` (use `GOOSE_MODE=auto` via template env), `budget_flag: --budget` (native hard cap — a metering win), `effort_flag:` → model/reasoning config (likely env, not a flag).

## Implementation (file by file)

1. **`spec/agent/impl_phase_sequencing.md`** (+ any `spec/agent/*.json`): add the invocation-profile requirement; state the `claude` default and byte-for-byte back-compat. Land first (spec-driven repo).
2. **`config/types.go`** — add an `Invoke` struct to the template type (all fields optional; `Profile string` + inline overrides). **`config/desugar.go`** — expand `profile:` presets into concrete fields, then apply inline overrides; inject the `claude` preset when `invoke:` is absent. **`config/ir.go`** — carry the resolved profile onto `ResolvedTemplate`. **`config/validate.go`** — validate at `faber validate` (field paths, never mid-run): unknown preset name; `prompt_template` must contain `{body}`; `skill_mode: flag` requires `skill_flag`; `skill_mode: prefix` requires `{skill}` reachable in the template; reject engine-owned collisions.
3. **`agent/contract/contract.go`** — add `EnvInvokeProfile = "FABER_INVOKE_PROFILE"` (JSON payload). **Bump `ContractVersion` 1 → 2** (env-contract shape change; faber/faber-box ship lockstep, so the bump is a stale-`FABER_BOX_BIN` detector). Box treats absence as the `claude` default (tolerant for direct sequencer invocations).
4. **`agent/runspec.go` (`BuildRunSpec`)** — marshal `tpl.Invoke` to JSON and emit `FABER_INVOKE_PROFILE`. No secret, engine-owned name (add to `EngineOwnedEnv` set in `config`).
5. **`agent/box/env.go`** — parse `FABER_INVOKE_PROFILE` into a `Profile` on the box `Env` (default `claude` when absent/empty).
6. **`agent/box/invoke.go`** — rewrite `Prompt()`/`Argv()` as **pure expanders over the profile**: build `[CLI] + subcommand + [prompt_flag, expand(prompt_template)] + skillArgs + fixed_flags + effortArg + budgetArg`. Delete all literal Claude strings from this file.

## Tests
- `agent/box/invoke_test.go` — table tests: `claude` preset argv/prompt **identical to current output** (guard the byte-for-byte default); `goose` preset argv; empty-effort/empty-budget omission; `skill_mode: flag` vs `prefix`; extra-instruction trailer.
- `config/*_test.go` — golden IR: absent `invoke` injects `claude`; preset expansion; inline override precedence; validation failures surface with field paths (extend `gen_golden_test.go`, `validate` tests).
- `agent/runspec_test.go` — assert `FABER_INVOKE_PROFILE` emitted and engine-owned.
- `pipeline` property/fuzz tests still green (determinism preserved).
- Add a `goose` variant under `examples/` (or a second template in `code-review-loop`) as an executable reference.

## Verification (end to end)
1. `go test ./...` — all green; the new byte-for-byte `claude` guard passes (proves zero behavior change for existing configs).
2. `faber validate --config examples/code-review-loop/orchestrator.yaml` — unchanged config still validates (default profile injected).
3. Author a minimal `goose`-profile template; `faber validate` then `faber build` it (Nix-pins the Goose binary into the image).
4. `faber run` one box against a throwaway repo + a local/vLLM (or Anthropic-API) endpoint via the existing `token-proxy`/`get-token` wiring; confirm: Goose is invoked with the goose-dialect argv (check the box's JSON log line `agent start`), edits land, commit is signed, push reaches the portitor gateway, and `output.json` matches the declared schema.
5. Confirm Goose's OTLP exporter reaches the collector from `plans/claude-usage-otel-aggregation.md` (same stack, new client).

## Open items to confirm at implementation time
- **Exact Goose CLI surface** (`goose run` flags for prompt, recipe/params, budget, reasoning/effort, and non-interactive `GOOSE_MODE=auto`) — finalize the `goose` preset against `goose --help` of the pinned version. The preset values above are provisional.
- **Skill → recipe mapping**: decide `skill_mode: flag` (`--recipe {skill}`, faithful; needs recipe files + `output.json`-writing instructions) vs simpler prompt-injection via the skills mount. Recommended: recipe route, mapping the spexmachina `implement/review/fix/merge` skills to Goose recipes.
- **`effort`** likely isn't a Goose flag → may map to model/reasoning env rather than `effort_flag`; allow the profile to route effort to env if needed.

## Out of scope (separate, dot-side work)
- Standing up Goose + local/vLLM endpoints + the OTel collector (that's `plans/claude-usage-otel-aggregation.md` and the `spexmachina` faber-config, not the faber engine).
- The Anthropic **subscription-vs-API** reality: Goose-on-Claude uses an API key, not the Max sub — route local/vLLM for routine beads, Claude-API for sharp ones. A routing policy, not an engine change.
