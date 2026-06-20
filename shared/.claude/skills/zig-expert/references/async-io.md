# Async & I/O — `std.Io` (Zig 0.16)

The `Io` interface decouples *what* I/O you do from *how* it runs. You write
ordinary, straight-line functions that take an `io: std.Io`; the caller picks the
backend. The same code runs blocking, threaded, or evented — no function coloring
(stackful fibers).

## Choosing an implementation

| Impl | Backend | Use when |
|------|---------|----------|
| `std.Io.Threaded` | OS thread pool | Default; portable, simple |
| `std.Io.Uring` | Linux `io_uring` | High-throughput evented I/O on Linux |
| `std.Io.Kqueue` | BSD / macOS kqueue | Evented I/O on macOS/BSD |
| `std.Io.Dispatch` | Grand Central Dispatch | macOS; integrate with libdispatch |

All expose the same `Io` via `.io()`, so application code is identical across them.
Pick the impl once in `main`; nothing downstream changes.

## Setup in `main`

```zig
pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{}); // .{} = default limits
    defer threaded.deinit();
    const io = threaded.io();

    try run(io, gpa);
}
```

`Threaded.init(gpa, options)`: the allocator is used only for spawning machinery;
`options` (`.{}`) defaults `stack_size` and the async/concurrent limits — override
`concurrent_limit` / `stack_size` to tune.

## `async` vs `concurrent`

```zig
// async: asynchrony WITHOUT a concurrency guarantee. May be scheduled later or
// run inline. Works even on single-threaded blocking impls.
var f = io.async(compute, .{ io, input });
const r = f.await(io);

// concurrent: REQUIRES real parallel progress, else error.ConcurrencyUnavailable.
// Use when the current task will block waiting on the spawned one.
var p = io.concurrent(producer, .{ io, &queue }) catch |e| switch (e) {
    error.ConcurrencyUnavailable => return e,
};
defer _ = p.cancel(io);
```

Rule of thumb: `async` by default; `concurrent` only when a deadlock would
otherwise be possible under single-threaded execution (e.g. an unbuffered queue
where the consumer blocks until the producer runs).

## Futures: await, cancel, defer-cancel

A `Future(R)` owns its task's resources until `await` or `cancel` is called. Both
are idempotent and not threadsafe.

```zig
var task = io.async(work, .{ io, args });
// Guarantees the task is reaped even if we return early on an error below.
defer _ = task.cancel(io);
const result = task.await(io);
```

If the task's result owns memory, reclaim it from `cancel` too:

```zig
var task = io.async(load, .{ gpa, io });           // returns ![]u8
defer if (task.cancel(io)) |buf| gpa.free(buf) else |_| {};
const buf = try task.await(io);
```

## Cancellation model

- `Cancelable = error{Canceled}`.
- A **cancellation point** is any `Io` call whose error set contains
  `error.Canceled` (most blocking ops). A cancel request is delivered at the
  *next* point only — it does not re-signal afterward.
- **Do not swallow `error.Canceled`.** Propagate it; ignoring it usually leaks or
  hangs.
- Await siblings before handling errors, so an early `try` can't skip reaping:

  ```zig
  const ra = a.await(io);
  const rb = b.await(io);
  try ra;
  try rb;
  ```

- Protect a region that must complete atomically:

  ```zig
  const prev = io.swapCancelProtection(.blocked);
  defer _ = io.swapCancelProtection(prev);
  // no Io call in here will observe error.Canceled
  ```

- `io.recancel()` re-arms a deferred cancellation; `io.checkCancel()` is a bare
  cancellation point for long CPU-bound loops that make no other `Io` calls.

## Fan-out with `Group`

```zig
var g: std.Io.Group = .init;
defer g.cancel(io);                  // reaps anything still running
for (jobs) |job| g.async(io, handle, .{ io, job });
try g.await(io);                     // waits for all; propagates cancellation
```

Group task functions must return something coercible to `Cancelable!void`.
Per-task resources are freed as each finishes, so a long-lived group that you keep
adding `concurrent` tasks to is not a leak.

## Racing with `Select`

`Select(U)` collects results into a tagged union; await the first to finish.

```zig
const Winner = union(enum) { primary: Response, fallback: Response };
var buf: [2]Winner = undefined;
var sel = std.Io.Select(Winner).init(io, &buf);
sel.async(.primary, fetchPrimary, .{io});
sel.async(.fallback, fetchFallback, .{io});

switch (try sel.await()) {           // first arrival wins
    .primary => |r| use(r),
    .fallback => |r| use(r),
}
sel.cancel();                        // cancel the loser(s)
```

Size the buffer for *all* spawned tasks — `cancel` deadlocks if there is not
enough room for every remaining task to deposit its result. `sel.awaitMany(buffer,
min)` waits for several results at once.

## I/O threads `io` too

File and socket ops also take `io`. Open/create and close are direct; reads and
writes go through a buffered Reader/Writer obtained from the file (the 0.15+
Reader/Writer split):

```zig
var file = try std.Io.Dir.cwd().createFile(io, "out.bin", .{});
defer file.close(io);

var wbuf: [4096]u8 = undefined;
var fw = file.writer(io, &wbuf);     // File.Writer bound to this io + buffer
try fw.interface.writeAll(data);     // .interface is the std.Io.Writer
try fw.interface.flush();
```

Reads mirror this via `file.reader(io, &buf)` → `fr.interface`. `std.Io.File.stdout()`
/ `std.Io.File.stdin()` give the standard streams.
