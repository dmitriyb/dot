---
name: summarize
description: Summarize the given topic in one line and write it to the result file.
disable-model-invocation: true
---

This is faber's round-trip smoke skill. Its only job is to prove the full spine
works — real Claude authenticates, runs a turn, and produces a schema-valid
`output.json`. Do exactly the following and nothing else:

1. Read the topic from the prompt (the `topic` input; also available in your
   shell as the `FABER_INPUT_TOPIC` environment variable).
2. Compose a concise **one-line** summary of that topic.
3. Write the result as JSON to the file at `$FABER_RESULT_DIR/output.json`
   (that environment variable is already set in your shell), in exactly this
   shape:

   ```json
   {"summary": "<your one-line summary>"}
   ```

   For example:

   ```bash
   printf '{"summary": "%s"}\n' "your one-line summary" > "$FABER_RESULT_DIR/output.json"
   ```

Do not open a PR, do not touch git, do not print anything else. The single
required output is that `output.json` file containing a non-empty `summary`
string — the box validates it against the template's output schema.
