# Advanced Comptime Patterns

## Type functions — `fn(comptime T: type) type`

The fundamental pattern for generic types in Zig:

```zig
pub fn Tensor(comptime T: type) type {
    return struct {
        const Self = @This();

        data: []T,
        shape: []const u32,
        allocator: Allocator,

        pub fn init(allocator: Allocator, shape: []const u32) !Self {
            const numel = computeNumel(shape);
            const data = try allocator.alloc(T, numel);
            @memset(data, std.mem.zeroes(T));
            return .{ .data = data, .shape = shape, .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
            self.* = undefined;
        }

        pub fn get(self: *const Self, idx: usize) T {
            return self.data[idx];
        }

        pub fn set(self: *Self, idx: usize, val: T) void {
            self.data[idx] = val;
        }
    };
}

// Usage
const FloatTensor = Tensor(f32);
var t = try FloatTensor.init(allocator, &.{ 3, 4 });
defer t.deinit();
```

## Comptime code generation for operation dispatch

Generate switch cases at compile time for operation types:

```zig
pub const Op = enum {
    add,
    mul,
    relu,
    sigmoid,
};

pub fn dispatch(comptime op: Op, a: []const f32, b: []const f32, out: []f32) void {
    for (a, b, out) |av, bv, *ov| {
        ov.* = switch (op) {
            .add => av + bv,
            .mul => av * bv,
            .relu => @max(av, 0),
            .sigmoid => 1.0 / (1.0 + @exp(-av)),
        };
        _ = bv;
    }
}

// Generates specialized code for each op — no runtime dispatch overhead
fn forwardAdd(a: []const f32, b: []const f32, out: []f32) void {
    dispatch(.add, a, b, out);
}
```

### Generating function tables

```zig
fn makeOpTable(comptime ops: []const Op) [ops.len]OpFn {
    var table: [ops.len]OpFn = undefined;
    for (ops, 0..) |op, i| {
        table[i] = struct {
            fn f(a: f32, b: f32) f32 {
                return switch (op) {
                    .add => a + b,
                    .mul => a * b,
                    .relu => @max(a, 0),
                    .sigmoid => 1.0 / (1.0 + @exp(-a)),
                };
                _ = b;
            }
        }.f;
    }
    return table;
}

const op_table = makeOpTable(&.{ .add, .mul, .relu, .sigmoid });
```

## Generic containers with comptime parameters

```zig
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buf: [capacity]T = undefined,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,

        pub fn push(self: *Self, item: T) !void {
            if (self.count == capacity) return error.BufferFull;
            self.buf[self.tail] = item;
            self.tail = (self.tail + 1) % capacity;
            self.count += 1;
        }

        pub fn pop(self: *Self) ?T {
            if (self.count == 0) return null;
            const item = self.buf[self.head];
            self.head = (self.head + 1) % capacity;
            self.count -= 1;
            return item;
        }
    };
}

// No heap allocation — entire buffer is in the struct
var ring = RingBuffer(f32, 64){};
try ring.push(1.0);
```

## `@This()` for self-referencing types

```zig
pub const Node = struct {
    const Self = @This();

    value: f32,
    children: std.ArrayList(*Self),

    pub fn init(allocator: Allocator, value: f32) Self {
        return .{
            .value = value,
            .children = std.ArrayList(*Self).init(allocator),
        };
    }
};
```

`@This()` resolves to the innermost struct/union type — essential inside type functions where the type name isn't known.

## `@hasDecl` / `@hasField` for feature detection

Compile-time duck typing:

```zig
pub fn maybeGradient(comptime T: type, tensor: *T) ?[]f32 {
    if (@hasField(T, "grad")) {
        return tensor.grad;
    }
    return null;
}

pub fn serialize(comptime T: type, value: T, writer: anytype) !void {
    if (@hasDecl(T, "serialize")) {
        // Type has custom serialization
        try value.serialize(writer);
    } else {
        // Fall back to raw bytes
        try writer.writeAll(std.mem.asBytes(&value));
    }
}
```

### Build option detection

```zig
const build_options = @import("build_options");

pub fn getBackend() Backend {
    if (@hasDecl(build_options, "gpu_backend")) {
        return build_options.gpu_backend;
    }
    return .cpu;
}
```

## Comptime string manipulation for kernel generation

Generate OpenCL kernel source at compile time:

```zig
fn generateElementwiseKernel(comptime op: []const u8, comptime dtype: []const u8) [:0]const u8 {
    return std.fmt.comptimePrint(
        \\__kernel void elementwise_{s}(
        \\    __global const {s}* a,
        \\    __global const {s}* b,
        \\    __global {s}* out,
        \\    const uint n
        \\) {{
        \\    uint i = get_global_id(0);
        \\    if (i < n) {{
        \\        out[i] = a[i] {s} b[i];
        \\    }}
        \\}}
    , .{ op, dtype, dtype, dtype, op });
}

// Generated at compile time — zero runtime cost
const add_kernel_src = generateElementwiseKernel("+", "float");
const mul_kernel_src = generateElementwiseKernel("*", "float");
```

### Comptime enum-to-string tables

```zig
fn dtypeToClType(comptime dtype: DType) [:0]const u8 {
    return switch (dtype) {
        .f32 => "float",
        .f64 => "double",
        .i32 => "int",
    };
}
```

## Comptime validation

Enforce constraints at compile time rather than runtime:

```zig
pub fn MatMul(comptime M: usize, comptime K: usize, comptime N: usize) type {
    comptime {
        if (M == 0 or K == 0 or N == 0) @compileError("Matrix dimensions must be non-zero");
        if (M * K > 1 << 24) @compileError("Matrix too large for stack allocation");
    }

    return struct {
        a: [M][K]f32,
        b: [K][N]f32,

        pub fn compute(self: *const @This()) [M][N]f32 {
            var result: [M][N]f32 = std.mem.zeroes([M][N]f32);
            for (0..M) |i| {
                for (0..K) |k| {
                    for (0..N) |j| {
                        result[i][j] += self.a[i][k] * self.b[k][j];
                    }
                }
            }
            return result;
        }
    };
}
```
