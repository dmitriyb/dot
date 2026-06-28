# prelude-common.sh — shared helpers for the start-<skill> prelude scripts.
#
# Sourced, not executed (no shebang, not +x). The start-implement / start-cleanup
# scripts are the entry points: each is a short, readable list of the commands it
# runs over git/br/spex. This file holds only the logic common to all of them.
# Nothing here is enforcement — the proxy (portitor) re-verifies the pushed
# result; these scripts are convenience that make the right thing easy.
#
# Output bundle (out of the repo tree, ephemeral, recreated each run) lives in
# $HARNESS_DIR (default ${XDG_RUNTIME_DIR:-/tmp}/harness):
#   CONTEXT.md      markdown context for the agent (becomes its prompt)
#   bundle.env      scalar machine values for the entrypoint to `source`
#   spec-files.txt  resolved spec file paths, one per line

HARNESS_DIR="${HARNESS_DIR:-${XDG_RUNTIME_DIR:-/tmp}/harness}"
DRY=0
ID=""

die()  { echo "prelude: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

# prelude_parse_args <skill> "$@" — sets ID and DRY; usage error if no bead id.
prelude_parse_args() {
	local skill="$1"; shift
	local a
	for a in "$@"; do
		case "$a" in
			--dry-run | -n) DRY=1 ;;
			-*) die "unknown flag: $a" ;;
			*) ID="$a" ;;
		esac
	done
	[ -n "$ID" ] || { echo "usage: start-$skill <arg> [--dry-run]" >&2; exit 2; }
	need git; need jq; need br
}

# pr_fetch <pr> -> prints the PR's review state JSON, fetched proxy-side via
# `portitor pr fetch` (the agent has no gh). Overridable in tests with
# PORTITOR_FETCH_CMD (a command prefix that takes the PR number as its last arg).
pr_fetch() {
	local pr="$1"
	if [ -n "${PORTITOR_FETCH_CMD:-}" ]; then
		$PORTITOR_FETCH_CMD "$pr"
	else
		pr fetch --pr "$pr" # backend-agnostic: portitor in dca, gh in dcp
	fi
}

# checkout_pr_branch <branch> -> fetch the PR branch from the proxy and check it
# out so the agent works against the PR's code (review/fix), not the default.
checkout_pr_branch() {
	local branch="$1"
	git fetch -q origin "$branch" || die "fetch PR branch $branch from origin failed"
	git checkout -q "$branch" || die "checkout PR branch $branch failed"
}

# slugify: stdin -> git-ref-safe kebab token, max 40 chars.
slugify() {
	tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40 | sed -E 's/-+$//'
}

default_branch() {
	local ref b
	if ref=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null); then
		echo "${ref#origin/}"; return
	fi
	for b in main master; do
		git rev-parse --verify --quiet "refs/remotes/origin/$b^{commit}" >/dev/null 2>&1 && { echo "$b"; return; }
	done
	echo main
}

preflight() {
	[ -z "$(git status --porcelain)" ] || die "working tree is not clean; commit or stash first"
	ssh-add -l >/dev/null 2>&1 || die "no SSH signing key loaded (ssh-add -l) — load the role key first"
	git fetch -q origin
	if [ -f .beads/issues.jsonl ]; then
		br sync --import-only >/dev/null 2>&1 || echo "prelude: warning: beads import failed" >&2
	fi
}

# resolve_spec <record-id> -> prints spec file paths (one per line).
resolve_spec() {
	local record="$1" mapjson
	[ -n "$record" ] || return 0
	if ! mapjson=$(spex map context "$record" 2>/dev/null); then
		echo "prelude: warning: spex map context $record failed" >&2; return 0
	fi
	jq -r '[.arch_file] + (.impl_files//[]) + (.test_files//[]) + (.flow_files//[]) + [.module_file]
	        | .[] | select(. != null and . != "")' <<<"$mapjson"
}

write_bundle() {
	local skill="$1" branch="$2" base="$3" id="$4" title="$5" predecessor="$6" record="$7" specs="$8"
	rm -rf "$HARNESS_DIR"; mkdir -p "$HARNESS_DIR"
	printf '%s\n' "$specs" | sed '/^$/d' >"$HARNESS_DIR/spec-files.txt"
	{
		echo "SKILL=$skill"
		echo "BEAD_ID=$id"
		echo "BRANCH=$branch"
		echo "BASE=$base"
		[ -n "$record" ] && echo "RECORD_ID=$record"
		[ -n "$predecessor" ] && echo "PREDECESSOR=$predecessor"
	} >"$HARNESS_DIR/bundle.env"
	{
		echo "# Prelude bundle — $skill"
		echo
		echo "The deterministic prelude is complete. You are on branch \`$branch\` (off \`$base\`), and bead \`$id\` is claimed (in_progress, committed)."
		echo
		echo "## Bead"
		echo "- id: $id"
		echo "- title: $title"
		echo "- status: in_progress (claimed)"
		[ -n "$predecessor" ] && echo "- cleans up after: $predecessor (closed)"
		echo
		echo "## Spec context (read these)"
		if [ -s "$HARNESS_DIR/spec-files.txt" ]; then
			sed 's/^/- /' "$HARNESS_DIR/spec-files.txt"
		else
			echo "- (none resolved; consult the bead description / proposal for spec references)"
		fi
		echo
		echo "## Your job"
		if [ "$skill" = cleanup ]; then
			echo "Remove the predecessor's code and its now-orphaned spec per the proposal. Do not implement new behavior."
		else
			echo "Implement against the spec + bead, write/adjust tests, run the completion gate, and prepare the PR body."
		fi
		echo "Do NOT close the bead (review-only) and do NOT push to the default branch."
	} >"$HARNESS_DIR/CONTEXT.md"
}

# ---- whole-epic helpers (start-epic) -----------------------------------------
#
# Epic mode batches a whole epic's beads onto ONE branch, reviewed task-by-task,
# closed once at the end. The prelude here is deterministic + token-free: it
# resolves the epic's member beads, dependency-orders them, and pre-bakes each
# bead's spec context into its own dir — so the implement-epic agent dispatches
# pre-built per-bead contexts to subagents (never the whole epic at once).
# Beads are NOT claimed/committed here: they stay `open` until the reviewer
# closes them in a batch at the very end (see the plan's state machine).

# epic_members <epic-id> -> bead ids belonging to the epic, one per line (deduped).
# Membership = the epic's parent-child CHILDREN (how the spex pipeline links epics:
# `br create --parent` / `br dep add <child> <epic> --type parent-child`) UNION an
# explicit `epic:<id>` label (operator override). Only open work is listed (br list
# excludes closed), which is exactly the active set during the epic. The
# parent-child scan is one `br dep list` per open issue — fine at prototype scale.
epic_members() {
	local epic="$1" all id
	all=$(br list --json 2>/dev/null) || return 0
	{
		jq -r --arg e "epic:$epic" '(.issues // .) | .[]? | select((.labels // []) | index($e)) | .id' <<<"$all" 2>/dev/null
		while read -r id; do
			{ [ -n "$id" ] && [ "$id" != "$epic" ]; } || continue
			br dep list "$id" --json 2>/dev/null \
				| jq -e --arg e "$epic" 'any(.[]?; .depends_on_id==$e and ((.type // "") | test("parent")))' >/dev/null 2>&1 \
				&& echo "$id"
		done < <(jq -r '(.issues // .) | .[]?.id' <<<"$all")
	} | sort -u
}

# epic_deps <bead-id> -> that bead's dependency bead ids, one per line (best-effort
# across br output shapes; only edges to members are kept by the caller).
epic_deps() {
	local id="$1"
	br dep list "$id" --json 2>/dev/null \
		| jq -r '.[]? | .depends_on_id // .depends_on // empty' 2>/dev/null \
		| { grep -v "^$id$" || true; } | sort -u
}

# toposort: stdin = "node<TAB>dep" edges (dep before node) + "node" lines for
# nodes with no deps; stdout = a dependency-respecting order (Kahn, stable by
# input order). Cycles: leftovers are appended in input order (never drops work).
toposort() {
	awk '
		{ nodes[$1]=1; order[++n]=$1 }
		NF==2 { dep[$1 SUBSEP $2]=1; indeg[$1]++; if(!($2 in nodes)){nodes[$2]=1; order[++n]=$2} }
		END {
			# dedup order preserving first-seen
			m=0; for(i=1;i<=n;i++){ if(!(order[i] in seen)){seen[order[i]]=1; ord[++m]=order[i]} }
			done=0
			while(done<m){
				progress=0
				for(i=1;i<=m;i++){ u=ord[i]; if(u in placed) continue
					ready=1
					for(k in dep){ split(k,a,SUBSEP); if(a[1]==u && !(a[2] in placed)){ready=0; break} }
					if(ready){ print u; placed[u]=1; done++; progress=1 }
				}
				if(!progress){ for(i=1;i<=m;i++){ u=ord[i]; if(!(u in placed)){print u; placed[u]=1; done++} } }
			}
		}'
}

# land: create the branch, claim the bead, write the bundle, and commit the claim
# (signed) on the feature branch. Branch first so the claim never lands on the
# default branch. Honors --dry-run (skips all mutations).
land() {
	local skill="$1" branch="$2" base="$3" id="$4" title="$5" predecessor="$6" record="$7" specs="$8"
	if [ "$DRY" = 1 ]; then
		write_bundle "$skill" "$branch" "$base" "$id" "$title" "$predecessor" "$record" "$specs"
		echo "prelude $skill (dry-run): would branch $branch off $base, claim $id, commit the claim"
		echo "bundle written to $HARNESS_DIR"
		return 0
	fi
	git checkout -q -b "$branch" "$base"
	br update "$id" --status in_progress >/dev/null
	write_bundle "$skill" "$branch" "$base" "$id" "$title" "$predecessor" "$record" "$specs"
	git add .beads/issues.jsonl
	git commit -qS -m "$id: start $skill (claim in_progress)"
	echo "prelude $skill: bead $id claimed; on branch $branch (off $base)"
	echo "bundle: $HARNESS_DIR (CONTEXT.md, bundle.env, spec-files.txt)"
}
