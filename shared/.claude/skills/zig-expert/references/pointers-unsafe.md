# Pointer Patterns & Unsafe Operations

## Multi-pointer `[*]T` — indexing and slicing

`[*]T` is a pointer without length information. You must track the length separately.

```zig
// Indexing — no bounds checking in release
const val = multi_ptr[i];

// Convert to slice when you know the length (enables bounds checking)
const slice: []T = multi_ptr[0..known_len];

// Pointer arithmetic
const offset_ptr = multi_ptr + offset;
```

**Rule:** Convert `[*]T` to `[]T` as early as possible. Pass slices to internal functions; use multi-pointers only at storage and FFI boundaries.

## Casting chains

### `@ptrCast` + `@alignCast` — always together when alignment changes

```zig
// Raw bytes → typed pointer (e.g., tensor data buffer)
const data: [*]u8 = tensor.data;
const floats: [*]f32 = @ptrCast(@alignCast(data));
const slice: []f32 = floats[0..tensor.numel()];

// Back to bytes
const raw: [*]u8 = @ptrCast(floats);
```

### Why `@alignCast` is required

`[*]u8` has alignment 1. `[*]f32` has alignment 4. Casting without `@alignCast` is a compile error. In debug mode, `@alignCast` verifies the pointer is actually aligned and traps if not.

## Working with `?*anyopaque`

Type-erased pointers for callbacks, context storage, and tape entries.

```zig
// Store typed data as opaque
const info: *GradInfo = try allocator.create(GradInfo);
const opaque: ?*anyopaque = info;

// Recover typed data
const recovered: *GradInfo = @ptrCast(@alignCast(opaque.?));

// Optional check
if (opaque) |ptr| {
    const typed: *GradInfo = @ptrCast(@alignCast(ptr));
    // use typed...
}
```

**Common pattern in autodiff tape:**
```zig
const TapeEntry = struct {
    op: OpType,
    context: ?*anyopaque = null,
    parents: [2]?u32 = .{ null, null },
};
```

## Alignment requirements

```zig
// SIMD-friendly alignment
var buffer: [1024]f32 align(16) = undefined;

// Allocate with specific alignment
const aligned_mem = try allocator.alignedAlloc(u8, 64, size);
defer allocator.free(aligned_mem);

// Struct field alignment
const SimdVec = struct {
    data: [4]f32 align(16),
};
```

### GPU alignment

GPU coalesced access typically requires 128-byte or 256-byte alignment. Use `align(128)` or allocate via GPU-specific allocators that guarantee alignment.

## Converting between pointer types safely

### Pattern: byte buffer → typed access

```zig
pub fn getDataSlice(self: *const Tensor, comptime T: type) []T {
    const byte_ptr = self.data;
    const typed_ptr: [*]T = @ptrCast(@alignCast(byte_ptr));
    return typed_ptr[0..self.numel()];
}
```

### Pattern: pointer to integer and back (GPU handles)

```zig
// Store GPU device pointer as integer
const device_addr: usize = @intFromPtr(device_ptr);

// Reconstruct when needed
const recovered: *DeviceBuffer = @ptrFromInt(device_addr);
```

**Only use `@intFromPtr`/`@ptrFromInt` for:**
- GPU device addresses that are not real host pointers
- C interop where handles are passed as `uintptr_t`
- Never for general pointer manipulation

## Common pointer bugs

### 1. Dangling pointer after free
```zig
// BAD — data is dangling after deinit
var t = try Tensor.init(alloc, &.{10}, .f32, .cpu);
const data = t.data; // pointer to t's buffer
t.deinit(alloc);     // buffer freed
_ = data[0];         // undefined behavior!

// GOOD — use self.* = undefined to poison
pub fn deinit(self: *Tensor, alloc: Allocator) void {
    alloc.free(self.data[0..self.byteSize()]);
    self.* = undefined; // all fields become undefined, debug catches use
}
```

### 2. Forgetting `@alignCast`
```zig
// COMPILE ERROR — alignment mismatch
const f: [*]f32 = @ptrCast(byte_ptr);

// CORRECT
const f: [*]f32 = @ptrCast(@alignCast(byte_ptr));
```

### 3. Slice from multi-pointer with wrong length
```zig
// BUG — using byte count instead of element count
const floats: [*]f32 = @ptrCast(@alignCast(data));
const bad_slice = floats[0..byte_size]; // wrong! byte_size != numel

// CORRECT
const good_slice = floats[0..numel]; // element count, not byte count
```

### 4. Optional pointer not checked
```zig
// CRASH — dereferencing null
const val = opaque.?; // panics if null in debug, UB in release

// SAFE
if (opaque) |ptr| {
    // use ptr
} else {
    // handle null case
}
```
