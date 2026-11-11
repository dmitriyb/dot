---
name: go-expert
description: "Go expert for CLI tools and system orchestration: error handling, os/exec, slog, concurrency, testing, and interfaces. Covers naming, struct patterns, validation, and performance. Load when writing or reviewing Go code."
---

# Go Expert — Conductor Project

## 1. Core Philosophy

- **Standard library first** — only add external deps when stdlib has no viable solution
- **No global state** — config, loggers, and stores passed explicitly as function parameters
- **Errors are values** — wrap with context, aggregate when validating, never ignore
- **Simplicity over abstraction** — a few duplicated lines beat a premature helper
- **Explicit over implicit** — no init() functions, no package-level vars, no hidden side effects

## 2. Naming Conventions

| Kind | Convention | Example |
|------|-----------|---------|
| Exported types | `PascalCase` | `Config`, `StepDef`, `AgentDef` |
| Unexported types | `camelCase` | `rbwStore`, `envStore` |
| Functions, methods | `PascalCase` (exported) / `camelCase` (unexported) | `Load`, `Validate`, `buildArgs` |
| Variables, params | `camelCase` | `cfgPath`, `logLevel`, `repoPath` |
| Constants | `PascalCase` (exported) / `camelCase` (unexported) | `DefaultTimeout`, `pipelineMarker` |
| Packages | `lowercase`, single word | `config`, `infra`, `agent`, `pipeline` |
| Files | `snake_case.go` | `creds_rbw.go`, `config_test.go` |
| Test functions | `TestREQ_Description` | `TestFR1_LoadConfig`, `TestNFR2_NoEnvReads` |

## 3. Error Handling

### Wrapping — always add context with %w

```go
// Module prefix + operation + original error
return nil, fmt.Errorf("config: read %s: %w", path, err)
return nil, fmt.Errorf("rbw get %q: %w", name, err)
return nil, fmt.Errorf("docker build: %w", err)
```

### Multi-error aggregation — for validation

```go
func Validate(cfg *Config) error {
    var errs []error
    check := func(cond bool, path, msg string) {
        if !cond {
            errs = append(errs, fmt.Errorf("%s: %s", path, msg))
        }
    }
    check(cfg.Project.Name != "", "project.name", "required")
    check(cfg.Project.Repository != "", "project.repository", "required")
    // ... more checks ...
    return errors.Join(errs...)
}
```

### Rules

- Wrap every error at the call site — never return a bare `err`
- Use `%w` verb for wrapping (enables `errors.Is`, `errors.As` upstream)
- Use `errors.Join` to aggregate multiple validation errors before returning
- Include field paths in validation errors: `"project.name: required"`
- Module prefix goes on the outermost wrap: `"config: ..."`, `"infra: ..."`
- Never use `log.Fatal` or `os.Exit` outside of `main()`

## 4. Struct Patterns

### YAML-mapped structs

```go
type Config struct {
    Project     Project              `yaml:"project"`
    Credentials Credentials          `yaml:"credentials"`
    Docker      Docker               `yaml:"docker"`
    Agents      map[string]AgentDef  `yaml:"agents"`
    Pipeline    []StepDef            `yaml:"pipeline"`
}
```

### Rules

- Use `yaml:"field_name"` tags — lowercase, underscore-separated
- Maps for named collections (`map[string]AgentDef`), slices for ordered lists (`[]StepDef`)
- No constructor functions unless initialization logic is required — plain struct literals suffice
- Keep all types for a module in the same package (no `types/` sub-package)

### Method receivers

| Receiver | When |
|----------|------|
| `(c *Config)` | Mutating methods, or struct is large |
| `(c Config)` | Small value types, no mutation needed |

Be consistent within a type — if any method needs a pointer receiver, use pointer receivers for all methods on that type.

## 5. Interface Patterns

### Keep interfaces small

```go
type CredentialStore interface {
    Get(ctx context.Context, name string) (string, error)
}
```

### Factory function with switch

```go
func NewCredentialStore(backend string) (CredentialStore, error) {
    switch backend {
    case "rbw":  return &rbwStore{}, nil
    case "env":  return &envStore{}, nil
    case "file": return &fileStore{}, nil
    default:     return nil, fmt.Errorf("unknown credential backend: %q", backend)
    }
}
```

### Rules

- Interfaces should have 1–3 methods — split larger interfaces
- Accept interfaces, return concrete types
- Define interfaces where they are consumed, not where they are implemented
- One file per backend implementation (`creds_rbw.go`, `creds_env.go`, `creds_file.go`)
- Private implementation structs (`rbwStore`, not `RbwStore`)

## 6. Concurrency

### Context propagation

```go
// context.Context always first parameter
func RunAgent(ctx context.Context, name string, def AgentDef, logger *slog.Logger) (*StepResult, error) {
    cmd := exec.CommandContext(ctx, "docker", args...)
    // ...
}
```

### Parallel execution pattern

```go
var mu sync.Mutex
var wg sync.WaitGroup
ready := make(chan *Node, len(nodes))

// Seed roots
for _, n := range roots {
    ready <- n
}

// Process nodes from ready channel
for remaining > 0 {
    select {
    case node := <-ready:
        wg.Add(1)
        go func(n *Node) {
            defer wg.Done()
            result := execute(ctx, n)
            mu.Lock()
            results[n.Name] = result
            mu.Unlock()
            // Enqueue newly unblocked dependents
        }(node)
    case <-ctx.Done():
        return ctx.Err()
    }
}
wg.Wait()
```

### Rules

- Always pass `context.Context` — enables timeout and cancellation
- Use `sync.Mutex` to protect shared maps/state
- Use `sync.WaitGroup` to wait for goroutine completion
- Use channels for coordination (ready queues, results)
- Always handle `ctx.Done()` in select statements
- Never launch goroutines without a clear ownership and shutdown path

## 7. os/exec Patterns

### Capture output

```go
// Capture stdout only
out, err := exec.CommandContext(ctx, "rbw", "get", name).Output()
if err != nil {
    return "", fmt.Errorf("rbw get %q: %w", name, err)
}
return strings.TrimRight(string(out), "\n"), nil
```

### Capture stdout + stderr on failure

```go
out, err := exec.CommandContext(ctx, "git", "clone", "--quiet", url, dest).CombinedOutput()
if err != nil {
    return fmt.Errorf("git clone: %w\n%s", err, out)
}
```

### Stream to terminal

```go
cmd := exec.CommandContext(ctx, "docker", "build", "-t", tag, ".")
cmd.Stdout = os.Stdout
cmd.Stderr = os.Stderr
if err := cmd.Run(); err != nil {
    return fmt.Errorf("docker build: %w", err)
}
```

### Rules

- Always use `exec.CommandContext` (not `exec.Command`) — propagate context
- Use `.Output()` when you need captured stdout
- Use `.CombinedOutput()` when you need stdout+stderr (especially for error messages)
- Use `.Run()` with `cmd.Stdout/Stderr = os.Stdout/Stderr` for interactive/streaming output
- Always `strings.TrimRight(string(out), "\n")` on captured output
- Include command output in error messages for debuggability
- Never shell out via `sh -c` — always use explicit argument lists

## 8. Logging

### Logger creation — TTY-aware

```go
func InitLogging(level string) *slog.Logger {
    lvl := parseLevel(level) // debug, info, warn, error
    opts := &slog.HandlerOptions{Level: lvl}
    var h slog.Handler
    if term.IsTerminal(int(os.Stderr.Fd())) {
        h = slog.NewTextHandler(os.Stderr, opts)
    } else {
        h = slog.NewJSONHandler(os.Stderr, opts)
    }
    return slog.New(h)
}
```

### Child loggers with component context

```go
logger := rootLogger.With("component", "agent")
logger.InfoContext(ctx, "step completed", "step", name, "status", status)
```

### Rules

- Never call `slog.SetDefault()` — no global logger
- Create one root logger in `main()`, pass it explicitly to all modules
- Use `.With()` to create child loggers with component/module context
- Always use `InfoContext`/`ErrorContext` (context-aware variants)
- Log to stderr, never stdout (stdout is for program output)
- Structured key-value pairs, not formatted strings

## 9. Configuration & Validation

### Separate Load and Validate

```go
// Load — reads and parses, no validation
func Load(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("config: read %s: %w", path, err)
    }
    var cfg Config
    if err := yaml.Unmarshal(data, &cfg); err != nil {
        return nil, fmt.Errorf("config: parse %s: %w", path, err)
    }
    return &cfg, nil
}

// Validate — checks all rules, returns aggregated errors
func Validate(cfg *Config) error { ... }
```

### Rules

- Load and Validate are separate — allows partial error reporting
- Config loaded once at startup, passed explicitly (no hot-reload)
- Validate returns all errors at once (via `errors.Join`), not just the first
- No environment variable reads during config loading — explicit file path only

## 10. Testing

### Requirement-traced names

```go
func TestFR1_LoadConfig(t *testing.T) { ... }
func TestNFR2_NoEnvReads(t *testing.T) { ... }
```

### Table-driven tests with subtests

```go
func TestFR3_ValidateRequired(t *testing.T) {
    tests := []struct {
        name    string
        cfg     Config
        wantErr string
    }{
        {"missing project name", Config{}, "project.name: required"},
        {"missing repository", Config{Project: Project{Name: "x"}}, "project.repository: required"},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := Validate(&tt.cfg)
            if tt.wantErr == "" {
                if err != nil {
                    t.Fatalf("unexpected error: %v", err)
                }
                return
            }
            if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
                t.Fatalf("want error containing %q, got %v", tt.wantErr, err)
            }
        })
    }
}
```

### Rules

- Test names must include requirement IDs: `TestFR1_...`, `TestNFR1_...`
- Use table-driven tests for validation and parsing edge cases
- Use `testdata/` directory for YAML fixtures
- Tests verify requirements are met, not just code coverage
- Arrange-Act-Assert structure within each test
- Use `t.Helper()` in test helper functions
- Use `t.Cleanup()` for teardown instead of defer when possible
- Run `go test ./...` — all tests must pass before committing

## 11. Security

### Secret hygiene

```go
f, err := os.CreateTemp("/dev/shm", ".conductor-env-")
if err != nil {
    return nil, fmt.Errorf("create env file: %w", err)
}
defer f.Close()
if err := f.Chmod(0600); err != nil {
    os.Remove(f.Name())
    return nil, err
}
```

### Rules

- Credentials never written to disk — only to `/dev/shm` (RAM-backed tmpfs)
- File permissions `0600` for secret files
- Clean up secret files via defer or explicit Remove
- Never log secret values — log the key name, not the value

## 12. Quick Checklists

### Per-function

- [ ] Error wrapped with `fmt.Errorf("context: %w", err)` at every return
- [ ] `context.Context` as first param for any I/O or exec operation
- [ ] No global state accessed — all deps passed as parameters
- [ ] Early return on invalid input

### Per-struct

- [ ] YAML tags present and correct (`yaml:"field_name"`)
- [ ] Pointer receiver consistency (all pointer or all value)
- [ ] Types defined in the owning package, not a separate `types/` package

### Per-interface

- [ ] 1–3 methods maximum
- [ ] Defined where consumed, not where implemented
- [ ] Factory function returns concrete type, accepts interface params
- [ ] Private implementation structs

### Per-test

- [ ] Name includes requirement ID (`TestFR1_...`, `TestNFR1_...`)
- [ ] Table-driven where 2+ cases exist
- [ ] Verifies requirement, not implementation detail
- [ ] Error messages include both want and got values
- [ ] `t.Helper()` on all helper functions

### Per-os/exec

- [ ] `exec.CommandContext` (not `exec.Command`)
- [ ] Output trimmed of trailing newlines
- [ ] Error wrapped with command context and output
- [ ] No `sh -c` — explicit argument list
