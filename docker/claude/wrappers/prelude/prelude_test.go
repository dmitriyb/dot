package prelude

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestImplementPrelude runs the full implement prelude against a real git repo
// with stubbed br/spex on PATH and an ephemeral SSH signing key.
func TestImplementPrelude(t *testing.T) {
	requireBins(t, "git", "ssh-keygen")
	work := setupRepo(t, `[{"id":"test-1","title":"Add Widget Thing","status":"open","labels":["spex:1"],"dependencies":[]}]`)

	// The agent's signing-key check needs a running ssh-agent; stub it here.
	orig := checkSigningKey
	checkSigningKey = func() error { return nil }
	defer func() { checkSigningKey = orig }()

	if err := Run(Implement, []string{"test-1", "--repo", work}); err != nil {
		t.Fatalf("Run: %v", err)
	}

	// On the derived feature branch.
	branch := strings.TrimSpace(mustGit(t, work, "rev-parse", "--abbrev-ref", "HEAD"))
	if want := "test-1-add-widget-thing"; branch != want {
		t.Fatalf("branch = %q, want %q", branch, want)
	}
	// HEAD is the signed claim commit.
	msg := strings.TrimSpace(mustGit(t, work, "log", "-1", "--format=%s"))
	if !strings.Contains(msg, "claim in_progress") {
		t.Fatalf("HEAD subject = %q, want the claim commit", msg)
	}
	if sig := strings.TrimSpace(mustGit(t, work, "log", "-1", "--format=%G?")); sig == "N" || sig == "" {
		t.Fatalf("claim commit is unsigned (%q)", sig)
	}
	// Bundle written and correct.
	raw, err := os.ReadFile(filepath.Join(work, ".harness", "bundle.json"))
	if err != nil {
		t.Fatalf("read bundle: %v", err)
	}
	var b Bundle
	if err := json.Unmarshal(raw, &b); err != nil {
		t.Fatalf("parse bundle: %v", err)
	}
	if b.Skill != "implement" || b.BeadID != "test-1" || b.RecordID != "1" {
		t.Fatalf("bundle = %+v", b)
	}
	if len(b.SpecFiles) != 1 || b.SpecFiles[0] != "spec/widget/module.json" {
		t.Fatalf("spec files = %v, want [spec/widget/module.json]", b.SpecFiles)
	}
	// .harness is git-excluded, so the tree is clean apart from the claim.
	if out := strings.TrimSpace(mustGit(t, work, "status", "--porcelain")); out != "" {
		t.Fatalf("working tree not clean after prelude: %q", out)
	}
}

// TestGuards covers the dispatch + status guards (no mutation needed).
func TestGuards(t *testing.T) {
	requireBins(t, "git", "ssh-keygen")
	orig := checkSigningKey
	checkSigningKey = func() error { return nil }
	defer func() { checkSigningKey = orig }()

	t.Run("cleanup bead rejected by implement", func(t *testing.T) {
		work := setupRepo(t, `[{"id":"c-1","title":"Cleanup X","status":"open","labels":["spex:cleanup"],"dependencies":[]}]`)
		err := Run(Implement, []string{"c-1", "--repo", work})
		if err == nil || !strings.Contains(err.Error(), "cleanup bead") {
			t.Fatalf("err = %v, want cleanup-dispatch rejection", err)
		}
	})

	t.Run("in_progress bead rejected", func(t *testing.T) {
		work := setupRepo(t, `[{"id":"i-1","title":"Busy","status":"in_progress","labels":["spex:1"],"dependencies":[]}]`)
		err := Run(Implement, []string{"i-1", "--repo", work})
		if err == nil || !strings.Contains(err.Error(), "expected open or ready") {
			t.Fatalf("err = %v, want status rejection", err)
		}
	})
}

// ---- test harness ----

func setupRepo(t *testing.T, beadJSON string) string {
	t.Helper()
	dir := t.TempDir()
	stub := filepath.Join(dir, "stub")
	if err := os.MkdirAll(stub, 0o755); err != nil {
		t.Fatal(err)
	}
	writeStub(t, filepath.Join(stub, "br"), brStub(beadJSON))
	writeStub(t, filepath.Join(stub, "spex"), spexStub)
	t.Setenv("PATH", stub+string(os.PathListSeparator)+os.Getenv("PATH"))

	// Ephemeral signing key (no passphrase, no touch).
	key := filepath.Join(dir, "id_ed25519")
	mustRun(t, dir, "ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "dev@test", "-f", key)

	origin := filepath.Join(dir, "origin.git")
	mustRun(t, dir, "git", "init", "-q", "--bare", "--initial-branch=main", origin)

	seed := filepath.Join(dir, "seed")
	mustRun(t, dir, "git", "init", "-q", "--initial-branch=main", seed)
	configSigning(t, seed, key)
	if err := os.MkdirAll(filepath.Join(seed, ".beads"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(seed, ".beads", "issues.jsonl"), []byte("{\"seed\":true}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	mustRun(t, seed, "git", "add", "-A")
	mustRun(t, seed, "git", "commit", "-q", "-m", "seed")
	mustRun(t, seed, "git", "remote", "add", "origin", origin)
	mustRun(t, seed, "git", "push", "-q", "origin", "main")

	work := filepath.Join(dir, "work")
	mustRun(t, dir, "git", "clone", "-q", origin, work)
	configSigning(t, work, key)
	return work
}

func configSigning(t *testing.T, repo, key string) {
	t.Helper()
	for _, kv := range [][2]string{
		{"user.name", "dev"}, {"user.email", "dev@test"},
		{"gpg.format", "ssh"}, {"user.signingkey", key}, {"commit.gpgsign", "true"},
	} {
		mustRun(t, repo, "git", "config", kv[0], kv[1])
	}
}

func brStub(beadJSON string) string {
	// `br show ... --json` echoes the canned bead; `br update` mutates the jsonl
	// so there is a claim to commit; `br sync` is a no-op.
	return `#!/usr/bin/env bash
case "$1" in
  show) cat <<'JSON'
` + beadJSON + `
JSON
  ;;
  update) echo '{"claim":true}' >> .beads/issues.jsonl ;;
  *) : ;;
esac
`
}

const spexStub = `#!/usr/bin/env bash
# spex map context <n>
cat <<'JSON'
{"record":{"id":1},"arch_file":"","impl_files":null,"test_files":null,"flow_files":null,"module_file":"spec/widget/module.json"}
JSON
`

func writeStub(t *testing.T, path, body string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
}

func requireBins(t *testing.T, bins ...string) {
	t.Helper()
	for _, b := range bins {
		if _, err := exec.LookPath(b); err != nil {
			t.Skipf("%s not available", b)
		}
	}
}

func mustGit(t *testing.T, repo string, args ...string) string {
	t.Helper()
	return mustRun(t, repo, "git", args...)
}

func mustRun(t *testing.T, dir, name string, args ...string) string {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %s: %v\n%s", name, strings.Join(args, " "), err, out)
	}
	return string(out)
}
