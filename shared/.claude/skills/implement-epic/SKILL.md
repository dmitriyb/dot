---
name: implement-epic
description: Implement a whole epic in one round — every bead as a signed commit on one branch, via per-bead subagents
disable-model-invocation: true
---

Implement the entire epic described in your bundle, **bead by bead, on one branch**, dispatching each bead to a subagent so no single context ever holds the whole epic. Use `@~/.claude/skills/implement/SKILL.md` for the per-bead TDD methodology and `@~/.claude/skills/go-expert/SKILL.md` for Go.

## Preconditions (already done for you)

`start-epic <epic-id>` has run (the dca entrypoint runs it automatically). It has:

- created the epic branch (`BRANCH` in `$HARNESS_DIR/bundle.env`) off `origin/<default>`,
- resolved the epic's member beads, **dependency-ordered** them, and **pre-baked each bead's spec slice** into `$HARNESS_DIR/beads/<NN-id>/` (`spec-files.txt` + `meta.env`),
- written `epic.json` (the ordered list), `epic-map.md` (the thin shared map), and `order.txt`.

The beads are **`open`** and stay open — you do **not** claim or close anything; the reviewer closes them in a batch at the end. If no bundle exists, run `start-epic <epic-id>` first.

## Workflow

1. Read `$HARNESS_DIR/epic-map.md` (shared map) and `epic.json` (the ordered beads). **Do not re-run triage.**
2. Keep a **ledger** in memory: as each bead is finished, record a ~5-line summary (key files, exported functions/types, interfaces) so its dependents can build on it.
3. Walk the beads **in `order.txt` order**. For each `beads/<NN-id>/`:
   - read its `meta.env` (`BEAD_ID`, `RECORD_ID`, `DEPS`) and `spec-files.txt`;
   - **spawn a subagent** (Task tool) whose context is **only**: the contents of `epic-map.md`, this bead's spec slice (the files in its `spec-files.txt`), and the **ledger summaries of this bead's `DEPS`**. Tell the subagent its dependencies' code is already committed on the branch, so it may read the working tree for detail — but do **not** hand it the whole epic.
   - the subagent follows the standard implement TDD flow + completion gate (`@~/.claude/skills/implement/SKILL.md`), scoped to **this bead's component only** (respect the file-ownership + test-section-scope rules), then makes **exactly one signed commit** with subject `"<bead-id>: <summary>"`. It must **not** change bead status, **not** close anything, **not** create a PR, **not** push.
   - when the subagent returns, append its ~5-line result to your ledger and continue.
4. **Cross-bead breakage**: if a bead's change breaks a file owned by a later bead, leave a `// TODO(bead:<later-id>): …` marker (as in the normal implement flow) — the later bead (or the fix phase) resolves it.
5. After **all** beads are committed: **push once**, capturing the PR number portitor prints on the push, and record the handoff for the orchestrator:
   ```bash
   git push -u origin "$BRANCH" 2>&1 | tee /tmp/push.log
   PR=$(grep -oE 'PR #[0-9]+' /tmp/push.log | grep -oE '[0-9]+' | head -1)
   jq -n --arg epic "$EPIC_ID" --arg branch "$BRANCH" --arg pr "$PR" \
     '{skill:"implement-epic", epic:$epic, branch:$branch, pr:($pr|select(.!="")|tonumber), status:"pushed"}' \
     > "${DCA_RESULT_DIR:-$HARNESS_DIR}/result.json"
   ```
   portitor gates each commit (signed + role) and opens **one PR** for the epic. Do **not** push to the default branch; commits must stay signed (no `--no-gpg-sign`). (`EPIC_ID`/`BRANCH` are in `$HARNESS_DIR/bundle.env`.)

Report the PR number and the per-bead ledger. The review phase takes it from here.
