---
name: zig-expert
description: "Zig systems programming expert for high-performance code: tensors, autodiff, GPU backends, C ABI, memory pools, and comptime. Covers naming, error handling, memory safety, pointer patterns, testing, and performance. Load when writing or reviewing Zig code."
---

# Zig Expert — Differentia Project

## 1. Core Philosophy

- **Explicitness over implicitness** — no hidden control flow, no hidden allocations
- **Safety within performance** — use Zig's safety checks (bounds, overflow) in debug; rely on `@setRuntimeSafety(false)` only in proven hot paths with release builds
- **Numerical correctness** — epsilon guards, bias correction, NaN/inf checks where math demands it
- **Zero-cost abstractions** — comptime generics and inline functions replace runtime polymorphism
- **Simplicity** — prefer straightforward code; a few duplicated lines beat a premature abstraction

## 2. Naming Conventions

| Kind | Convention | Example |
|------|-----------|---------|
| Types, structs, enums | `PascalCase` | `Tensor`, `DType`, `Device` |
| Functions, methods | `camelCase` | `init`, `deinit`, `numelFromShape` |
| Local variables, params | `snake_case` | `byte_size`, `num_elements` |
| Constants (`comptime`) | `snake_case` | `max_dims`, `epsilon` |
| Global/module constants | `SCREAMING_SNAKE_CASE` only for truly global config | Rare — prefer `snake_case` |
| Files | `snake_case.zig` | `tensor.zig`, `build.zig` |
| Test names | `"frN: descriptive name"` | `test "fr5: create 1d tensor"` |

## 3. Error Handling

### Error sets — keep them domain-specific and composable

```zig
// Compose domain errors with allocator errors using ||
pub const InitError = error{ InvalidShape } || Allocator.Error;
```

### Patterns

- Always pair `errdefer` with fallible allocations to prevent leaks on error paths
- Place `defer` immediately after successful acquisition of a resource
- Define named error sets as `pub const` on the struct/namespace that owns them
- Avoid `anyerror` — compose with named sets instead

```zig
// Wrapping arithmetic — use *% and +% only when overflow is mathematically expected
stride *%= shape[i]; // known-safe overflow in stride computation
```

### C ABI boundary — no error unions

Export functions cannot return error unions. Instead:

```zig
// Return nullable pointer — null signals failure
export fn create(...) ?*Tensor { ... }
// Return bool — false signals failure
export fn reshape(...) bool { ... }
// Or set error via out-parameter / thread-local for detail
```

See `references/c-interop.md` for full patterns.

## 4. Memory Ownership

### The allocator pattern

The **caller provides the allocator**. Structs that need to free memory in `deinit` must store the allocator:

```zig
pub fn init(allocator: Allocator, ...) !Self {
    const buf = try allocator.alloc(u8, size);
    errdefer allocator.free(buf); // clean up if later steps fail
    return .{ .data = buf.ptr, ... };
}

pub fn deinit(self: *Self, allocator: Allocator) void {
    allocator.free(self.data[0..self.byte_size]);
    self.* = undefined; // poison after free
}
```

### Rules

- Place `defer` immediately — write the cleanup on the line after successful init
- Use `errdefer` for partial init — if init can fail after allocation, errdefer frees
- Poison after free — set struct to undefined in deinit to catch use-after-free in debug
- No hidden allocations — if a function allocates, it takes an Allocator parameter

```zig
// Raw pointer ownership: [*]u8 owns the data, reconstruct slice with known length to free
allocator.free(self.data[0..byte_size]);
```

For arena, pool, and custom allocator patterns see `references/custom-allocators.md`.

## 5. Concurrency & I/O — the `Io` interface (Zig 0.16)

Zig 0.16 reintroduces async via `std.Io`: a **caller-provided interface, exactly like `Allocator` (§4)**. Any function that does I/O or spawns work takes an `io: std.Io` param, and the *caller* picks the execution model. No `async`/`await` keywords color your functions — the same function runs sync or async depending on the `Io` it's handed (stackful fibers, "colorblind").

### Obtaining and passing `Io`

```zig
// Set up once in main(), like an allocator. Options default sensibly.
var threaded: std.Io.Threaded = .init(gpa, .{});
defer threaded.deinit();
const io = threaded.io();

// Reusable code takes io as a parameter — same rule as Allocator
fn fetch(io: std.Io, url: []const u8) !Response { ... }
```

Implementations live under `std.Io.*`: `Threaded` (thread pool), `Uring` (Linux io_uring), `Kqueue` / `Dispatch` (macOS).

### Spawning — `async` vs `concurrent`

| Call | Returns | Guarantee |
|------|---------|-----------|
| `io.async(fn, args)` | `Future(R)` | May run inline/later; allows single-threaded blocking impls |
| `io.concurrent(fn, args)` | `ConcurrentError!Future(R)` | Real parallelism, or `error.ConcurrencyUnavailable` |

Default to `async`. Reach for `concurrent` only when correctness *requires* parallel progress (e.g. a producer the current task will block on).

```zig
var f = io.async(compute, .{ io, input });
const result = f.await(io);          // await is idempotent, not threadsafe
```

### Cleanup & cancellation discipline

A `Future` owns resources until awaited or canceled; `cancel` is `await` plus a cancellation request.

```zig
var task = io.async(work, .{ io, args });
defer _ = task.cancel(io);           // guarantees cleanup on early return
const r = task.await(io);            // normal path
```

- A **cancellation point** is any `Io` call that can return `error.Canceled` (`Cancelable = error{Canceled}`). After a cancel request, only the *next* point returns it — **never silently swallow `error.Canceled`**.
- Awaiting siblings: **await all first, then `try`** — an early `try` leaks the un-awaited tasks.

  ```zig
  const ra = a.await(io);
  const rb = b.await(io);
  try ra;  try rb;                   // handle errors only after both awaited
  ```
- Guard a critical region with `io.swapCancelProtection(.blocked)` (+ `defer` restore); re-arm with `io.recancel()`; poll a long CPU loop with `io.checkCancel()`.

### Fan-out & racing

- **`std.Io.Group`** — spawn N tasks (`g.async` / `g.concurrent`), then `g.await(io)` / `g.cancel(io)`. Per-task resources free as each finishes, so a long-lived group is fine.
- **`std.Io.Select(U)`** — race tasks whose results land in tagged union `U`; `s.await()` returns the first to finish, `s.awaitMany(buf, min)` for several.

See `references/async-io.md` for impl choice, io-threaded file ops, full `Select`, and cancellation edge cases.

## 6. Struct Patterns

### Init/deinit convention

Every struct that owns resources implements init (fallible) and deinit:

```zig
pub const Tensor = struct {
    data: [*]u8,
    // ...

    pub fn init(allocator: Allocator, ...) InitError!Tensor { ... }
    pub fn deinit(self: *Tensor, allocator: Allocator) void { ... }
};
```

### Method receiver rules

| Receiver | When |
|----------|------|
| `self: *const Self` | Read-only access (getters, queries) |
| `self: *Self` | Mutating access (setters, deinit) |
| `self: Self` | Small value types, comptime operations |

### Type-erased storage

Use optional anyopaque pointers when you need to store arbitrary typed data (e.g., tape entries in autodiff):

```zig
context: ?*anyopaque = null, // stores *GradInfo, cast back with @ptrCast(@alignCast(...))
```

### Storing allocator in struct

When deinit needs to free but the caller shouldn't re-pass the allocator:

```zig
allocator: Allocator,
pub fn deinit(self: *Self) void {
    self.allocator.free(...);
    self.* = undefined;
}
```

Use this only when ownership lifetime is clear and the allocator must outlive the struct.

## 7. Pointer Safety

### Pointer types — when to use each

| Type | Meaning | Use case |
|------|---------|----------|
| `*T` | Single-item pointer | Mutable reference to one value |
| `*const T` | Single-item const pointer | Read-only reference |
| `[]T` | Slice (pointer + length) | Bounded, safe iteration |
| `[]const T` | Const slice | Read-only bounded data |
| `[*]T` | Multi-pointer (no length) | Raw buffer, C interop, manual indexing |
| `[*:0]const u8` | Sentinel-terminated | C strings |
| `?*T` | Optional pointer | Nullable (C interop returns, optional fields) |
| `?*anyopaque` | Type-erased optional | Context pointers, callbacks |

### Casting rules

```zig
// Multi-pointer to typed pointer (e.g., raw u8 buffer to f32 array)
const floats: [*]f32 = @ptrCast(@alignCast(raw_u8_ptr));

// anyopaque back to concrete type
const info: *GradInfo = @ptrCast(@alignCast(ctx.?));

// Pointer to/from integer (GPU handles, device addresses)
const addr = @intFromPtr(ptr);
const ptr2: *T = @ptrFromInt(addr);
```

### Safety rules

```zig
// Always @alignCast with @ptrCast when alignment changes
const floats: [*]f32 = @ptrCast(@alignCast(byte_ptr));

// Reconstruct slices from [*]T using known length before passing to safe code
const slice = ptr[0..len];

// Check optional pointers before dereferencing
if (opt_ptr) |ptr| {
    // safe to use ptr
}

// @intFromPtr/@ptrFromInt — only for GPU device handles and C interop
```

See `references/pointers-unsafe.md` for advanced patterns.

## 8. Type Safety

- Prefer `const` by default — make everything const unless mutation is required
- Use explicit integer casts with care — compiler checks narrowing in debug
- Prefer tagged unions over type-erased alternatives when variants are known
- Avoid `anytype` in public APIs — use explicit comptime parameters for clarity

```zig
// Tagged union instead of type erasure
pub const Value = union(enum) { int: i64, float: f64 };

// Comptime type parameters for generic containers
fn Tensor(comptime T: type) type { ... }

// Explicit widening with @as
const wide: usize = @as(usize, some_u32);

// Explicit narrowing with @intCast
const narrow: u8 = @intCast(some_u32);
```

## 9. Performance

### General patterns

- Inline hot functions — use `inline fn` or inline on for-loop bodies in critical paths
- Preallocate — call `ensureTotalCapacity` before batch inserts
- Early exit — check failure conditions first to avoid unnecessary work
- Fast path / slow path — check common case first, branch to complex logic only when needed

```zig
// Reuse buffers instead of free+alloc
buffer.clearRetainingCapacity();
```

### Numerical computing

- **SoA (Structure of Arrays)** — separate arrays per field for cache-friendly/GPU-friendly access
- **Bias correction** — Adam/moment updates need 1 - pow(beta, step) correction
- **NaN guards** — assert or check `std.math.isNan` in debug builds for numerical operations
- **Buffer reuse** — accumulate gradients into pre-zeroed buffers rather than allocating per-op

```zig
// Epsilon constants for division guards
const epsilon: f32 = 1e-8;
const safe = value / (divisor + epsilon);
```

### Alignment

```zig
// SIMD-friendly data
var buffer: [1024]f32 align(16) = undefined;

// Cache-line alignment for hot data
var hot_data: [64]u8 align(64) = undefined;

// GPU backends may require specific alignment — see references/gpu-memory.md
```

## 10. Testing

### Convention

- Use `std.testing.allocator` — it detects leaks automatically
- **Arrange-Act-Assert** structure
- **Requirement-traced names** — prefix with feature requirement ID

### Patterns

```zig
test "fr5: create 2d tensor with row-major strides" {
    const allocator = testing.allocator;
    var t = try Tensor.init(allocator, &.{ 3, 4 }, .f32, .cpu);
    defer t.deinit(allocator);

    try testing.expectEqual(@as(u8, 2), t.ndim);
    try testing.expectEqualSlices(u32, &.{ 3, 4 }, t.getShape());
    try testing.expectEqualSlices(u32, &.{ 4, 1 }, t.getStrides());
}
```

### Numerical accuracy

```zig
// Tolerance-based comparison for floating point
try testing.expectApproxEqAbs(expected, actual, 1e-6);
try testing.expectApproxEqRel(expected, actual, 1e-6);
```

### Error testing

```zig
try testing.expectError(error.InvalidShape, Tensor.init(allocator, &.{}, .f32, .cpu));
```

## 11. Documentation

- Focus on **why** and **invariants**, not restating what the code does
- Document **ownership** in doc comments: who allocates, who frees

```zig
/// Doc comment for public declarations (functions, types, fields)
//! Module-level doc comment at top of file
// Implementation comment only where logic is non-obvious
```

## 12. C ABI

### Rules

- Only C-compatible types: integers, floats, pointers, bool, void
- No error unions, no slices, no optionals (except nullable pointers which map to C)
- Use null-terminated sentinel pointers for C strings
- callconv(.C) is implicit with export fn

### Pattern

```zig
export fn tensor_create(ndim: u32, shape_ptr: [*]const u32, dtype: u32) ?*Tensor {
    const shape = shape_ptr[0..ndim];
    const t = allocator.create(Tensor) catch return null;
    t.* = Tensor.init(allocator, shape, @enumFromInt(dtype), .cpu) catch {
        allocator.destroy(t);
        return null;
    };
    return t;
}

export fn tensor_destroy(t: *Tensor) void {
    t.deinit(allocator);
    allocator.destroy(t);
}
```

See `references/c-interop.md` for full patterns including Python ctypes integration.

## 13. Quick Checklists

### Per-function

- [ ] `const` on every binding that doesn't need mutation
- [ ] `errdefer` for every fallible allocation
- [ ] No `anyerror` — use named error sets
- [ ] Early return on invalid input
- [ ] Doc comment with ownership semantics

### Per-struct

- [ ] init returns error union, deinit takes mutable self
- [ ] Struct set to undefined at end of deinit
- [ ] All resources freed in deinit (paired with init allocations)
- [ ] Allocator stored if needed for deinit
- [ ] Methods use correct receiver (const self vs mutable self)

### Per-C-export

- [ ] Export fn with C-compatible types only
- [ ] Nullable return instead of error union
- [ ] Slice reconstructed from pointer + length parameters
- [ ] Memory ownership documented (who frees?)

### Performance

- [ ] SoA layout considered for array-heavy structs
- [ ] Buffer reuse over repeated alloc/free
- [ ] Epsilon guard on all divisions in numerical code
- [ ] Retain capacity for reusable containers
- [ ] Alignment specified for SIMD/GPU data

### Async / Io

- [ ] I/O-performing functions take an `io: std.Io` param (like Allocator)
- [ ] `io.async` by default; `io.concurrent` only when parallel progress is required
- [ ] Every `Future` is awaited or `defer`-canceled
- [ ] `error.Canceled` never silently ignored
- [ ] All sibling futures awaited before any `try`
