---
name: merge
description: Land an approved PR through the portitor gate
---

Merge the approved PR in your bundle. This step runs only after review reached `approved` and closed the bead, so your job is narrow: land the PR. You are the **merger** identity — portitor's action policy permits the merge for this role only.

## Preconditions

The PR number is `${FABER_INPUT_PR}` in your environment. No context hook runs for this template; the synthesized bundle enumerates your inputs. You do not author commits here — a plain landing identity.

## Workflow

1. Merge the PR through the portitor-mediated client (you have no `gh`):
   ```bash
   portitor pr merge --pr "$FABER_INPUT_PR"
   ```
   Use your portitor client's merge verb/flags (e.g. squash) as configured. If the merge is refused (not up to date, checks pending, gate rejection), do NOT force it — report the reason via the result below with `merged=false`.
2. Confirm the merge succeeded (the client's exit status / a follow-up `pr fetch --pr "$FABER_INPUT_PR"` showing merged).

## Emit your result (required)

```bash
printf '{"merged":%s}\n' "<true|false>" > "$FABER_RESULT_DIR/output.json"
```

`true` iff portitor reports the PR merged; `false` (with the reason noted in your final message) otherwise.
