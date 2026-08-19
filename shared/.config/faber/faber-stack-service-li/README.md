# faber-stack-service-li — the playground with a local implementer

The faber-e2e acceptance target for the goose + local-model box chain, BEFORE
spexmachina-li touches the real repo. Same disposable repo and gate instance
as ../faber-stack-service (skills/hooks/workflows/keys referenced from there);
implement / implement-next / fix run goose + qwen/qwen3.8-27b, review / merge
stay exactly as the base playground has them (review opus/high; merge
sonnet/low, deterministic postlude-only).

Design rationale (sidecar, goose-agent wrapper, skill delivery, open items):
see ../spexmachina-li/README.md — identical apart from instance names.

## Run (COSTS real usage on the claude side; local model must be serving)

```sh
lms load qwen/qwen3.8-27b --context-length 32768 && lms server start
faber-e2e reset
faber-e2e run --project ~/.config/faber/faber-stack-service-li   # runs faber-stack up first
llm-sidecar up --instance faber-stack-service                    # after the stack exists
faber-e2e assert
```

NOTE the ordering wrinkle: `llm-sidecar up` needs the instance network, which
`faber-e2e run` creates via `faber-stack up` — on a FIRST run, either run
`faber-stack up` once beforehand and then the sidecar, or accept that the
implement boxes fail until the sidecar is up. Cleanest first run:

```sh
role-keys --json | faber-stack up --instance faber-stack-service \
  --slug dvb-service/faber-stack-service --pat service-bot/dvb-service \
  --project ~/.config/faber/faber-stack-service-li --commit-email <email> --build
llm-sidecar up --instance faber-stack-service
faber-e2e full --project ~/.config/faber/faber-stack-service-li
```
