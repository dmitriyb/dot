# C Interop Patterns

## `export fn` patterns

### Basic export

```zig
// Zig side
export fn tensor_numel(t: *const Tensor) usize {
    return t.numel();
}

// C side
// size_t tensor_numel(const Tensor* t);
```

### Fallible export — nullable return

```zig
var global_alloc: Allocator = undefined; // set during library init

export fn tensor_create(ndim: u32, shape_ptr: [*]const u32, dtype_int: u32) ?*Tensor {
    const shape = shape_ptr[0..@as(usize, ndim)];
    const dtype: DType = @enumFromInt(dtype_int);
    const t = global_alloc.create(Tensor) catch return null;
    t.* = Tensor.init(global_alloc, shape, dtype, .cpu) catch {
        global_alloc.destroy(t);
        return null;
    };
    return t;
}

export fn tensor_destroy(t: *Tensor) void {
    t.deinit(global_alloc);
    global_alloc.destroy(t);
}
```

### Library init/deinit

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

export fn differentia_init() bool {
    global_alloc = gpa.allocator();
    return true;
}

export fn differentia_deinit() void {
    _ = gpa.deinit();
}
```

## C-compatible type mapping

| Zig type | C type | Notes |
|----------|--------|-------|
| `bool` | `bool` / `_Bool` | |
| `u8`, `i8` | `uint8_t`, `int8_t` | |
| `u32`, `i32` | `uint32_t`, `int32_t` | |
| `u64`, `i64` | `uint64_t`, `int64_t` | |
| `usize` | `size_t` | |
| `f32` | `float` | |
| `f64` | `double` | |
| `*T` | `T*` | Non-null pointer |
| `?*T` | `T*` | Nullable pointer (null = error) |
| `*const T` | `const T*` | |
| `[*]const u8` | `const uint8_t*` | No length |
| `[*:0]const u8` | `const char*` | Null-terminated string |
| `void` | `void` | |

**Not C-compatible:** slices (`[]T`), error unions, optionals (except `?*T`), Zig strings, tagged unions.

## Memory ownership across FFI boundary

### Rule: document who frees

```zig
/// Creates a tensor. Caller must call tensor_destroy() to free.
export fn tensor_create(...) ?*Tensor { ... }

/// Frees a tensor created by tensor_create().
export fn tensor_destroy(t: *Tensor) void { ... }

/// Copies data into tensor. Caller retains ownership of src_data.
export fn tensor_set_data(t: *Tensor, src_data: [*]const u8, len: usize) bool {
    if (len != t.byteSize()) return false;
    @memcpy(t.data[0..len], src_data[0..len]);
    return true;
}
```

### Pattern: borrowed vs owned pointers

- **Borrowed:** C passes pointer, Zig reads/writes it, C still owns it
- **Owned:** Zig allocates, returns pointer to C, C must call Zig's destroy

Never let C `free()` Zig-allocated memory or vice versa — allocators are incompatible.

## Python ctypes integration

```python
import ctypes

lib = ctypes.CDLL("./zig-out/lib/libdifferentia.so")

# Setup function signatures
lib.differentia_init.restype = ctypes.c_bool
lib.tensor_create.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32), ctypes.c_uint32]
lib.tensor_create.restype = ctypes.c_void_p  # ?*Tensor → void* (NULL on error)
lib.tensor_destroy.argtypes = [ctypes.c_void_p]
lib.tensor_numel.argtypes = [ctypes.c_void_p]
lib.tensor_numel.restype = ctypes.c_size_t

# Usage
assert lib.differentia_init()
shape = (ctypes.c_uint32 * 2)(3, 4)
t = lib.tensor_create(2, shape, 0)  # 0 = f32
assert t is not None
print(lib.tensor_numel(t))  # 12
lib.tensor_destroy(t)
```

## Error reporting without error unions

### Nullable return pattern (preferred)

```zig
export fn operation(args: ...) ?*Result {
    return internal_operation(args) catch return null;
}
```

### Bool + out-parameter pattern

```zig
export fn tensor_reshape(t: *Tensor, ndim: u32, shape_ptr: [*]const u32) bool {
    const shape = shape_ptr[0..@as(usize, ndim)];
    t.reshape(shape) catch return false;
    return true;
}
```

### Thread-local error string (for detailed errors)

```zig
threadlocal var last_error: [256]u8 = undefined;
threadlocal var last_error_len: usize = 0;

fn setError(comptime fmt: []const u8, args: anytype) void {
    last_error_len = (std.fmt.bufPrint(&last_error, fmt, args) catch &last_error).len;
}

export fn get_last_error() [*:0]const u8 {
    last_error[last_error_len] = 0;
    return @ptrCast(&last_error);
}
```

## `@cImport` for consuming C headers

```zig
const c = @cImport({
    @cInclude("CL/cl.h");
});

// Use C types and functions
const ctx: c.cl_context = c.clCreateContext(...);
```

In `build.zig`, link the C library:

```zig
exe.linkSystemLibrary("OpenCL");
exe.addIncludePath(.{ .path = "/usr/include" });
```
