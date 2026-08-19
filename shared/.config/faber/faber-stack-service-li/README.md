# faber-stack-service-li — the playground with a local implementer

The faber-e2e acceptance target for the goose + local-model box chain, BEFORE
spexmachina-li touches the real repo. Same disposable repo and gate instance
as ../faber-stack-service (skills/hooks/workflows/keys referenced from there);
implement / implement-next / fix run goose + qwen/qwen3.8-27b, review / merge
stay exactly as the base playground has them (review opus/high; merge
sonnet/low, deterministic postlude-only).

Design rationale (sidecar, goose-agent wrapper, skill delivery, open items):
see ../spexmachina-li/README.md — identical apart from instance names.

## Run (COSTS real usage on the claude side)

```sh
faber-e2e full --project ~/.config/faber/faber-stack-service-li
```

That is the whole sequence: `run` sees this project's `local-llm.json` and
stands the model up itself via `llm-local up` — LM Studio load + serve, a
tool-calling preflight that fails BEFORE any paid boxes launch, and the
`faber-stack-service-llm` sidecar joined to the instance network right after
`faber-stack up` creates it. `--no-local` skips the bring-up (e.g. model
already serving and verified).
