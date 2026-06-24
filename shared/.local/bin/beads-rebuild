#!/usr/bin/env bash
# beads-rebuild.sh — make the beads SQLite db a disposable cache of the JSONL.
#
# .beads/issues.jsonl is the source of truth (it is what gets committed and
# gated by the proxy); the *.db is a derived index. Rebuilding it from the JSONL
# on every container boot means the db is never stale and "don't touch the db"
# stops being a rule the agent can break — the db is regenerated regardless.
#
# Idempotent and safe: no-op when there is no beads workspace, and `br sync
# --import-only` never runs git or writes outside .beads/, and its import guards
# (conflict markers, invalid JSON) cannot be bypassed.
#
# Usage: beads-rebuild.sh [repo-dir]   (defaults to the current directory)
set -eu

repo="${1:-$PWD}"

if [ ! -f "$repo/.beads/issues.jsonl" ]; then
	exit 0 # not a beads repo; nothing to rebuild
fi

if ! command -v br >/dev/null 2>&1; then
	echo "beads-rebuild: br not on PATH; skipping" >&2
	exit 0
fi

echo "beads-rebuild: importing $repo/.beads/issues.jsonl -> db"
( cd "$repo" && br sync --import-only )
