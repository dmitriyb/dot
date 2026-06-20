# Custom Allocator Patterns

## When to use which allocator

| Allocator | Use case | Lifetime |
|-----------|----------|----------|
| `GeneralPurposeAllocator` | Default, debugging, tests | Process lifetime |
| `std.testing.allocator` | Tests only (leak detection) | Test scope |
| `ArenaAllocator` | Batch alloc, free all at once | Phase/scope |
| `FixedBufferAllocator` | Stack-based, no heap | Function scope |
| `MemoryPool` | Same-size objects, reuse | Container lifetime |
| `page_allocator` | Large aligned allocations | Process lifetime |

## Arena allocator

Free everything at once — ideal for forward pass temporary allocations.

```zig
const std = @import("std");

pub fn forwardPass(base_allocator: Allocator, graph: *const Graph) ![]Tensor {
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit(); // frees ALL arena allocations at once

    const alloc = arena.allocator();

    // All temporaries use arena — no individual frees needed
    const intermediates = try alloc.alloc(Tensor, graph.node_count);
    const workspace = try alloc.alloc(f32, graph.max_workspace_size);
    _ = workspace;

    for (graph.nodes, 0..) |node, i| {
        intermediates[i] = try evaluateNode(alloc, node);
    }

    // Only the final output needs to outlive the arena
    const result = try base_allocator.dupe(Tensor, intermediates[graph.output_indices]);
    return result;
}
```

### Nested arenas

```zig
// Per-layer arena inside per-pass arena
var pass_arena = std.heap.ArenaAllocator.init(base_alloc);
defer pass_arena.deinit();

for (layers) |layer| {
    var layer_arena = std.heap.ArenaAllocator.init(pass_arena.allocator());
    defer layer_arena.deinit(); // free layer temps each iteration

    try processLayer(layer_arena.allocator(), layer);
}
```

## FixedBufferAllocator — stack-based allocation

No heap allocation at all. Useful for small, bounded work.

```zig
pub fn formatTensorInfo(tensor: *const Tensor) []const u8 {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    // All allocations come from the stack buffer
    var list = std.ArrayList(u8).init(alloc);
    const writer = list.writer();
    writer.print("Tensor({d}d, {s})", .{ tensor.ndim, @tagName(tensor.dtype) }) catch {};
    return list.items;
}
```

**Caution:** `FixedBufferAllocator` returns `error.OutOfMemory` when the buffer is exhausted. Size the buffer for the worst case.

## Memory pool pattern

Pre-allocate a pool of same-size objects. Mark as dead and reuse instead of free/alloc.

```zig
pub fn MemoryPool(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        free_list: std.ArrayList(usize),
        allocator: Allocator,

        pub fn init(allocator: Allocator, capacity: usize) !Self {
            const items = try allocator.alloc(T, capacity);
            var free_list = std.ArrayList(usize).init(allocator);
            try free_list.ensureTotalCapacity(capacity);

            // All slots start as free
            var i: usize = capacity;
            while (i > 0) {
                i -= 1;
                free_list.appendAssumeCapacity(i);
            }

            return .{
                .items = items,
                .free_list = free_list,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.free_list.deinit();
            self.allocator.free(self.items);
            self.* = undefined;
        }

        pub fn acquire(self: *Self) ?*T {
            const idx = self.free_list.popOrNull() orelse return null;
            return &self.items[idx];
        }

        pub fn release(self: *Self, ptr: *T) void {
            const idx = (@intFromPtr(ptr) - @intFromPtr(self.items.ptr)) / @sizeOf(T);
            self.free_list.append(idx) catch unreachable; // capacity pre-allocated
        }
    };
}
```

### Usage for tensor nodes

```zig
var node_pool = try MemoryPool(GraphNode).init(allocator, 1024);
defer node_pool.deinit();

// Acquire from pool instead of allocator.create
const node = node_pool.acquire() orelse return error.PoolExhausted;
node.* = .{ .op = .add, .inputs = .{ a, b } };

// Return to pool instead of allocator.destroy
node_pool.release(node);
```

## Custom allocator interface

Implement the `Allocator` interface for specialized allocation strategies.

```zig
const TrackingAllocator = struct {
    backing: Allocator,
    total_allocated: usize = 0,
    total_freed: usize = 0,
    active_allocations: usize = 0,

    pub fn allocator(self: *TrackingAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.backing.rawAlloc(len, ptr_align, ret_addr) orelse return null;
        self.total_allocated += len;
        self.active_allocations += 1;
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        if (self.backing.rawResize(buf, buf_align, new_len, ret_addr)) {
            if (new_len > buf.len) {
                self.total_allocated += new_len - buf.len;
            } else {
                self.total_freed += buf.len - new_len;
            }
            return true;
        }
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        self.total_freed += buf.len;
        self.active_allocations -= 1;
        self.backing.rawFree(buf, buf_align, ret_addr);
    }

    pub fn report(self: *const TrackingAllocator) void {
        std.debug.print("Allocated: {d}, Freed: {d}, Active: {d}\n", .{
            self.total_allocated, self.total_freed, self.active_allocations,
        });
    }
};
```

## Tracking allocator for debugging leaks

Zig's `GeneralPurposeAllocator` has built-in leak detection:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{
    .stack_trace_frames = 8, // capture stack traces for leak reports
}){};
defer {
    const check = gpa.deinit();
    if (check == .leak) {
        std.debug.print("Memory leak detected!\n", .{});
    }
}
const allocator = gpa.allocator();
```

In tests, `std.testing.allocator` does this automatically — any unfreed allocation fails the test.
