# goose-local — scratch container for local-model agents

Phase-A test harness: Block's **goose** CLI in a Nix-built container, talking to
an OpenAI-compatible inference server on the container host (LM Studio serving
Qwen3.8-27B). Proves the agent ↔ local-endpoint ↔ tool-calling loop with no
faber involvement. The faber-native variant (invoke profile, `faber build/run`)
is separate — see the goose-local faber project config.

Not production: runs on the default bridge network (host reachability), config
mounted rw, dummy API key. The faber egress/portitor invariants do not apply
here and nothing in this directory should migrate into a box image as-is.

## Layout

- `goose-image.nix` — `dockerTools.buildLayeredImage`, nixpkgs pinned via
  `shared/.local/share/versions.json` (same rev as the spex-box/gate/egress
  images). `goose-cli` comes from nixpkgs at that pin.
- `config/config.yaml` — goose config, mounted at `/root/.config/goose`.
  `GOOSE_MODEL` must match the id the server reports at `GET /v1/models`.
- `run.sh` — `nix-build` + `docker load` + `docker run`. No args → interactive
  `goose session`; args pass through (`./run.sh goose run -t "…"`,
  `./run.sh bash`).
- `workspace/` — created at runtime, mounted at `/workspace`. Gitignored.

## Host checklist (once per model)

1. Update LM Studio and its runtimes (`lms runtime update`) — new hybrid
   architectures need a recent runtime build.
2. Download a quant (4-bit ≈ 15 GB; 8-bit ≈ 28 GB if quality disappoints).
3. `lms load <model> --context-length 32768`, then `lms server start` (:1234).
4. `curl -s http://localhost:1234/v1/models | jq -r '.data[].id'` → put the
   exact id into `config/config.yaml` `GOOSE_MODEL`.
5. Tool-calling gate — goose is unusable if this returns null:

   ```sh
   curl -s http://localhost:1234/v1/chat/completions -H 'Content-Type: application/json' -d '{
     "model": "<id>",
     "messages": [{"role":"user","content":"What is the weather in Paris? Use the tool."}],
     "tools": [{"type":"function","function":{"name":"get_weather",
       "parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}]
   }' | jq '.choices[0].message.tool_calls'
   ```

## Smoke tests

1. `./run.sh` — banner shows provider/model; a trivial question answers
   (container → host connectivity).
2. `./run.sh goose run -t "Create hello.py that prints the first 10 Fibonacci
   numbers, run it, and show the output."` — tool calls execute and
   `workspace/hello.py` appears on the host.
3. `git init` inside `workspace/`, ask goose to commit — proves git + passwd
   (getpwuid) wiring.
