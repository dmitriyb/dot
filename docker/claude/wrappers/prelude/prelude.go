// Package prelude runs the deterministic, non-LLM prelude of the execution
// skills (implement, cleanup) outside the agent: sync from origin, guard the
// bead, resolve spec context, branch off the default, claim the bead, and write
// a bundle the agent then works from. None of this needs LLM judgment, so doing
// it here saves tokens and makes the guards correct-by-construction. The proxy
// (portitor) still re-verifies the result, so these wrappers stay untrusted.
package prelude

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Skill selects which prelude to run.
type Skill int

const (
	Implement Skill = iota
	Cleanup
)

// Options are the parsed command-line inputs.
type Options struct {
	BeadID string
	Repo   string
	DryRun bool
}

// checkSigningKey verifies a signing key is available to the agent. It is a
// package var so tests can stub it (the real check needs a running ssh-agent).
var checkSigningKey = func() error {
	out, err := exec.Command("ssh-add", "-l").CombinedOutput()
	if err != nil || strings.TrimSpace(string(out)) == "" || strings.Contains(string(out), "no identities") {
		return errors.New("no SSH signing key loaded (ssh-add -l) — load the role key before running")
	}
	return nil
}

// Run parses args and dispatches to the chosen skill's prelude.
func Run(skill Skill, args []string) error {
	opts, err := parseArgs(args)
	if err != nil {
		return err
	}
	repo, err := resolveRepo(opts.Repo)
	if err != nil {
		return err
	}
	switch skill {
	case Implement:
		return runImplement(repo, opts)
	case Cleanup:
		return runCleanup(repo, opts)
	default:
		return fmt.Errorf("unknown skill")
	}
}

func parseArgs(args []string) (Options, error) {
	var o Options
	var positional []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--dry-run":
			o.DryRun = true
		case a == "--repo":
			if i+1 >= len(args) {
				return o, errors.New("--repo needs a value")
			}
			o.Repo = args[i+1]
			i++
		case strings.HasPrefix(a, "--repo="):
			o.Repo = a[len("--repo="):]
		case strings.HasPrefix(a, "-"):
			return o, fmt.Errorf("unknown flag %q", a)
		default:
			positional = append(positional, a)
		}
	}
	if len(positional) != 1 {
		return o, errors.New("expected exactly one bead id")
	}
	o.BeadID = positional[0]
	return o, nil
}

// ---- the two preludes ----

func runImplement(repo string, opts Options) error {
	if err := preflight(repo); err != nil {
		return err
	}
	def, err := defaultBranch(repo)
	if err != nil {
		return err
	}
	bead, err := showBead(repo, opts.BeadID)
	if err != nil {
		return err
	}
	if bead.isCleanup() {
		return fmt.Errorf("bead %s is a cleanup bead (spex:cleanup) — use `prelude cleanup %s`", bead.ID, bead.ID)
	}
	if !statusReady(bead.Status) {
		return fmt.Errorf("bead %s status is %q, expected open or ready", bead.ID, bead.Status)
	}

	specFiles := resolveSpec(repo, bead)
	branch := implementBranch(bead)
	base := "origin/" + def

	b := Bundle{Skill: "implement", BeadID: bead.ID, Title: bead.Title, Branch: branch, Base: base, RecordID: bead.recordID(), SpecFiles: specFiles}
	if opts.DryRun {
		return printPlan(b, bead)
	}
	if err := land(repo, branch, base, bead, b); err != nil {
		return err
	}
	printSummary(b)
	return nil
}

func runCleanup(repo string, opts Options) error {
	if err := preflight(repo); err != nil {
		return err
	}
	def, err := defaultBranch(repo)
	if err != nil {
		return err
	}
	bead, err := showBead(repo, opts.BeadID)
	if err != nil {
		return err
	}
	if !bead.isCleanup() {
		return fmt.Errorf("bead %s is not a cleanup bead (no spex:cleanup label) — use `prelude implement %s`", bead.ID, bead.ID)
	}
	if !statusReady(bead.Status) {
		return fmt.Errorf("bead %s status is %q, expected open or ready", bead.ID, bead.Status)
	}

	pred := bead.blocksDep()
	if pred == "" {
		return fmt.Errorf("cleanup bead %s has no blocks: dependency identifying the predecessor", bead.ID)
	}
	predBead, err := showBead(repo, pred)
	if err != nil {
		return fmt.Errorf("read predecessor %s: %w", pred, err)
	}
	if predBead.Status != "closed" {
		return fmt.Errorf("predecessor %s status is %q, expected closed before cleanup", pred, predBead.Status)
	}

	branch := "cleanup/" + truncate(slug(predBead.Title), 40)
	base := "origin/" + def

	b := Bundle{Skill: "cleanup", BeadID: bead.ID, Title: bead.Title, Branch: branch, Base: base, Predecessor: pred, SpecFiles: resolveSpec(repo, bead)}
	if opts.DryRun {
		return printPlan(b, bead)
	}
	if err := land(repo, branch, base, bead, b); err != nil {
		return err
	}
	printSummary(b)
	return nil
}

// preflight runs the guards common to both preludes and refreshes from origin.
func preflight(repo string) error {
	if err := ensureClean(repo); err != nil {
		return err
	}
	if err := checkSigningKey(); err != nil {
		return err
	}
	if _, err := git(repo, "fetch", "origin"); err != nil {
		return fmt.Errorf("git fetch origin: %w", err)
	}
	beadsRebuild(repo)
	return nil
}

// land creates the branch, claims the bead, writes the bundle, and commits the
// claim with a signed commit (the role's key). Order matters: branch first so
// the claim lands on the feature branch, never the default.
func land(repo, branch, base string, bead Bead, b Bundle) error {
	if _, err := git(repo, "checkout", "-b", branch, base); err != nil {
		return fmt.Errorf("create branch %s off %s: %w", branch, base, err)
	}
	if _, err := brc(repo, "update", bead.ID, "--status", "in_progress"); err != nil {
		return fmt.Errorf("claim bead %s: %w", bead.ID, err)
	}
	if err := writeBundle(repo, b, bead); err != nil {
		return err
	}
	if _, err := git(repo, "add", ".beads/issues.jsonl"); err != nil {
		return fmt.Errorf("stage claim: %w", err)
	}
	msg := fmt.Sprintf("%s: start %s (claim in_progress)", bead.ID, b.Skill)
	if _, err := git(repo, "commit", "-S", "-m", msg); err != nil {
		return fmt.Errorf("commit claim (signing required): %w", err)
	}
	return nil
}

// ---- git / br / spex helpers ----

func resolveRepo(repo string) (string, error) {
	if repo != "" {
		return repo, nil
	}
	out, err := git("", "rev-parse", "--show-toplevel")
	if err != nil {
		return "", fmt.Errorf("not inside a git repo (pass --repo): %w", err)
	}
	return strings.TrimSpace(out), nil
}

func ensureClean(repo string) error {
	out, err := git(repo, "status", "--porcelain")
	if err != nil {
		return fmt.Errorf("git status: %w", err)
	}
	if strings.TrimSpace(out) != "" {
		return errors.New("working tree is not clean; commit or stash before running the prelude")
	}
	return nil
}

func defaultBranch(repo string) (string, error) {
	if out, err := git(repo, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"); err == nil {
		return strings.TrimPrefix(strings.TrimSpace(out), "origin/"), nil
	}
	for _, b := range []string{"main", "master"} {
		if _, err := git(repo, "rev-parse", "--verify", "--quiet", "refs/remotes/origin/"+b+"^{commit}"); err == nil {
			return b, nil
		}
	}
	return "main", nil
}

func beadsRebuild(repo string) {
	if _, err := os.Stat(filepath.Join(repo, ".beads")); err != nil {
		return // no beads workspace; nothing to rebuild
	}
	_, _ = brc(repo, "sync", "--import-only") // best-effort idempotent rebuild from JSONL
}

func showBead(repo, id string) (Bead, error) {
	out, err := brc(repo, "show", id, "--json")
	if err != nil {
		return Bead{}, fmt.Errorf("br show %s: %w", id, err)
	}
	var beads []Bead
	if err := json.Unmarshal([]byte(out), &beads); err != nil {
		return Bead{}, fmt.Errorf("parse br show %s: %w", id, err)
	}
	if len(beads) == 0 {
		return Bead{}, fmt.Errorf("bead %s not found", id)
	}
	return beads[0], nil
}

func resolveSpec(repo string, bead Bead) []string {
	rec := bead.recordID()
	if rec == "" {
		return nil
	}
	out, err := spx(repo, "map", "context", rec)
	if err != nil {
		fmt.Fprintf(os.Stderr, "prelude: warning: spex map context %s: %v\n", rec, err)
		return nil
	}
	var m SpexMap
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		fmt.Fprintf(os.Stderr, "prelude: warning: parse spex map context %s: %v\n", rec, err)
		return nil
	}
	return m.Files()
}

func git(repo string, args ...string) (string, error) { return run(repo, "git", args...) }
func brc(repo string, args ...string) (string, error) { return run(repo, "br", args...) }
func spx(repo string, args ...string) (string, error) { return run(repo, "spex", args...) }

func run(repo, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	if repo != "" {
		cmd.Dir = repo
	}
	var out, errb strings.Builder
	cmd.Stdout = &out
	cmd.Stderr = &errb
	if err := cmd.Run(); err != nil {
		return out.String(), fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(errb.String()))
	}
	return out.String(), nil
}
