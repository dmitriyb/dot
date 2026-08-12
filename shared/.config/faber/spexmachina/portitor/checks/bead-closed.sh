#!/bin/sh
# merge_gate predicate — "this PR is allowed to land".
#
# WHERE THIS RUNS: inside the gate container, in the repo's BARE mirror
# (/srv/git/<repo>.git), invoked by portitor before every merge. It is referenced
# from policy.json as ["/bin/sh", "/etc/portitor/checks/bead-closed.sh"];
# faber-stack installs this project's portitor/checks/ into the gate's config dir,
# which is bind-mounted read-only at /etc/portitor. Invoked via `sh <path>`, so it
# needs no exec bit — the mount is read-only.
#
# ARGUMENTS: portitor appends the PR number and the head SHA to the configured
# argv, so $1 = PR number, $2 = head SHA (GitHub's headRefOid, re-derived by the
# gate — never taken from the caller).
#
# CONTRACT: exit 0 = precondition met, non-zero = unmet (portitor names it in the
# refusal). ONLY the exit code is consulted; stdout/stderr are not parsed.
#
# AVAILABLE TOOLS: the gate image is deliberately minimal — sh, git, awk,
# coreutils, br, portitor. There is NO grep, sed or jq. Use br for bead data (it
# owns the format) and awk for path matching.
#
# ---------------------------------------------------------------------------
# THE RULE: a PR may land if it closed a bead, OR if it is a drift-only PR.
#
# 1. NORMAL CYCLE — the reviewer closed this PR's bead. Only the reviewer may
#    close one (the semantic content rule bead-close-reviewer-only denies a
#    transition to "closed" for every other role), so a closed bead in this PR is
#    proof a reviewer signed off. Counted with br against the merge-base rather
#    than the whole file: an earlier version grepped the corpus for any
#    "status":"closed" and passed unconditionally, since hundreds of beads from
#    previous epics are closed. It was vacuous and enforced nothing.
#
# 2. DRIFT-ONLY PR — the sanctioned exception. When a bead's own contract is
#    defective, the drift protocol has the box discard its work, file
#    drifts/drift-<bead>.json, return the bead to "open", and land THAT — the
#    report must reach main so the next cycle halts the epic for triage. Such a
#    PR closes nothing by design, so branch 1 can never admit it.
#
#    SHAPE IS THE QUALIFIER: this checks that nothing outside drifts/ and
#    .beads/ changed, and does NOT parse "blocking": true. A NON-blocking drift
#    rides along with the code it was raised against (the skills say: commit the
#    report alongside your changes and continue), so it can never be drift-only.
#    Parsing the flag would need jq, which the gate does not carry, and
#    text-matching JSON is brittle — the claim field is free text that could
#    contain the literal string.
#
#    Known anomaly: a box that files a non-blocking drift and does no work would
#    produce a drift-only PR and land without closing its bead. The bead stays
#    open, the next cycle re-picks it, and the cycles loop bound caps it.
set -eu

# Closed-bead count at a rev. br is the format owner, so this asks the tracker
# rather than pattern-matching JSON. The bare repo has no worktree, hence the
# materialisation into a temp .beads/ that br can discover.
closed_at() {
	d=$(mktemp -d)
	mkdir -p "$d/.beads"
	if git show "$1":.beads/issues.jsonl > "$d/.beads/issues.jsonl" 2>/dev/null; then
		(cd "$d" && br --no-db count --status closed)
	else
		echo 0   # no bead file at that rev — count it as zero, never as an error
	fi
	rm -rf "$d"
}

head=$2
base=$(git merge-base "$(git symbolic-ref --short HEAD)" "$head")

# --- 1. did this PR close a bead? -------------------------------------------
# Against the merge-base, not the current default branch: main advances while an
# epic runs, and the fork point is what isolates THIS PR's contribution.
if [ "$(closed_at "$head")" -gt "$(closed_at "$base")" ]; then
	exit 0
fi

# --- 2. is it a well-formed drift-only PR? ----------------------------------
changed=$(git diff --name-only "$base" "$head")
[ -n "$changed" ] || exit 1        # a PR that changed nothing lands nothing

printf '%s\n' "$changed" | awk '
	!/^drifts\// && !/^\.beads\// { outside = 1 }
	/^drifts\/.*\.json$/          { report  = 1 }
	END { exit (report && !outside) ? 0 : 1 }
'
