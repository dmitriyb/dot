package prelude

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Bead is the subset of `br show <id> --json` (a one-element array) we use.
type Bead struct {
	ID           string `json:"id"`
	Title        string `json:"title"`
	Status       string `json:"status"`
	Description  string `json:"description"`
	Labels       []string `json:"labels"`
	Parent       string `json:"parent"`
	Dependencies []Dep  `json:"dependencies"`
}

// Dep is a bead dependency entry.
type Dep struct {
	ID             string `json:"id"`
	Title          string `json:"title"`
	Status         string `json:"status"`
	DependencyType string `json:"dependency_type"`
}

// recordID returns the spex map record id from a "spex:<n>" label, or "".
// "spex:cleanup" is a dispatch marker, not a record id.
func (b Bead) recordID() string {
	for _, l := range b.Labels {
		if rest, ok := strings.CutPrefix(l, "spex:"); ok && rest != "cleanup" {
			return rest
		}
	}
	return ""
}

// isCleanup reports whether the bead carries the spex:cleanup dispatch label.
func (b Bead) isCleanup() bool {
	for _, l := range b.Labels {
		if l == "spex:cleanup" {
			return true
		}
	}
	return false
}

// blocksDep returns the id of the predecessor this bead's cleanup blocks, or "".
func (b Bead) blocksDep() string {
	for _, d := range b.Dependencies {
		if d.DependencyType == "blocks" {
			return d.ID
		}
	}
	return ""
}

// SpexMap is `spex map context <n>` output; file fields may be "" or null.
type SpexMap struct {
	Record     json.RawMessage `json:"record"`
	ArchFile   string          `json:"arch_file"`
	ImplFiles  []string        `json:"impl_files"`
	TestFiles  []string        `json:"test_files"`
	FlowFiles  []string        `json:"flow_files"`
	ModuleFile string          `json:"module_file"`
}

// Files returns every non-empty spec file path the map resolves to.
func (m SpexMap) Files() []string {
	var fs []string
	add := func(p string) {
		if strings.TrimSpace(p) != "" {
			fs = append(fs, p)
		}
	}
	add(m.ArchFile)
	for _, p := range m.ImplFiles {
		add(p)
	}
	for _, p := range m.TestFiles {
		add(p)
	}
	for _, p := range m.FlowFiles {
		add(p)
	}
	add(m.ModuleFile)
	return fs
}

// Bundle is the structured context handed to the agent.
type Bundle struct {
	Skill       string   `json:"skill"`
	BeadID      string   `json:"bead_id"`
	Title       string   `json:"title"`
	Branch      string   `json:"branch"`
	Base        string   `json:"base"`
	RecordID    string   `json:"record_id,omitempty"`
	Predecessor string   `json:"predecessor,omitempty"`
	SpecFiles   []string `json:"spec_files"`
}

func statusReady(s string) bool { return s == "open" || s == "ready" }

func implementBranch(b Bead) string {
	id := slug(b.ID)
	title := truncate(slug(b.Title), 40)
	if title == "" {
		return id
	}
	return id + "-" + title
}

// slug lowercases and reduces s to a git-ref-safe [a-z0-9-] token.
func slug(s string) string {
	var b strings.Builder
	dash := false
	for _, r := range strings.ToLower(s) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
			dash = false
		} else if !dash {
			b.WriteByte('-')
			dash = true
		}
	}
	return strings.Trim(b.String(), "-")
}

func truncate(s string, n int) string {
	if len(s) > n {
		s = s[:n]
	}
	return strings.Trim(s, "-")
}

// writeBundle writes .harness/bundle.json + CONTEXT.md and excludes .harness/
// from git so the agent never accidentally commits it.
func writeBundle(repo string, b Bundle, bead Bead) error {
	dir := filepath.Join(repo, ".harness")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("create .harness: %w", err)
	}
	js, err := json.MarshalIndent(b, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, "bundle.json"), append(js, '\n'), 0o644); err != nil {
		return fmt.Errorf("write bundle.json: %w", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "CONTEXT.md"), []byte(contextMarkdown(b, bead)), 0o644); err != nil {
		return fmt.Errorf("write CONTEXT.md: %w", err)
	}
	excludeHarness(repo)
	return nil
}

func excludeHarness(repo string) {
	p := filepath.Join(repo, ".git", "info", "exclude")
	data, err := os.ReadFile(p)
	if err == nil && strings.Contains(string(data), ".harness/") {
		return
	}
	f, err := os.OpenFile(p, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	fmt.Fprintln(f, ".harness/")
}

func contextMarkdown(b Bundle, bead Bead) string {
	var sb strings.Builder
	fmt.Fprintf(&sb, "# Prelude bundle — %s\n\n", b.Skill)
	fmt.Fprintf(&sb, "The deterministic prelude is complete. You are on branch `%s` (off `%s`), and bead `%s` is claimed (in_progress, committed).\n\n", b.Branch, b.Base, b.BeadID)
	fmt.Fprintf(&sb, "## Bead\n- id: %s\n- title: %s\n- status: in_progress (claimed)\n", bead.ID, bead.Title)
	if len(bead.Labels) > 0 {
		fmt.Fprintf(&sb, "- labels: %s\n", strings.Join(bead.Labels, ", "))
	}
	if b.Predecessor != "" {
		fmt.Fprintf(&sb, "- cleans up after: %s (closed)\n", b.Predecessor)
	}
	if strings.TrimSpace(bead.Description) != "" {
		fmt.Fprintf(&sb, "\n%s\n", strings.TrimSpace(bead.Description))
	}
	sb.WriteString("\n## Spec context (read these)\n")
	if len(b.SpecFiles) == 0 {
		sb.WriteString("- (none resolved; consult the bead description for spec references)\n")
	}
	for _, f := range b.SpecFiles {
		fmt.Fprintf(&sb, "- %s\n", f)
	}
	sb.WriteString("\n## Your job\n")
	if b.Skill == "cleanup" {
		sb.WriteString("Remove the predecessor's code and its now-orphaned spec, per the proposal. ")
	} else {
		sb.WriteString("Implement against the spec + bead, write/adjust tests, run the completion gate, and prepare the PR body. ")
	}
	sb.WriteString("Do NOT close the bead (review-only) and do NOT push to the default branch.\n")
	return sb.String()
}

func printPlan(b Bundle, bead Bead) error {
	fmt.Printf("prelude %s (dry-run): bead %s %q\n", b.Skill, bead.ID, bead.Title)
	fmt.Printf("  branch:  %s (off %s)\n", b.Branch, b.Base)
	fmt.Printf("  status:  %s -> in_progress\n", bead.Status)
	if b.RecordID != "" {
		fmt.Printf("  record:  spex:%s\n", b.RecordID)
	}
	fmt.Printf("  spec files (%d):\n", len(b.SpecFiles))
	for _, f := range b.SpecFiles {
		fmt.Printf("    - %s\n", f)
	}
	return nil
}

func printSummary(b Bundle) {
	fmt.Printf("prelude %s: bead %s claimed; on branch %s (off %s)\n", b.Skill, b.BeadID, b.Branch, b.Base)
	fmt.Printf("bundle written to .harness/bundle.json + .harness/CONTEXT.md (%d spec files)\n", len(b.SpecFiles))
}
