# Build System Patterns

## Multi-module build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core tensor module
    const dpc_mod = b.addModule("differentia", .{
        .root_source_file = b.path("src/dpc/tensor.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Shared library for C/Python FFI
    const lib = b.addSharedLibrary(.{
        .name = "differentia",
        .root_source_file = b.path("src/ffi/exports.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("differentia", dpc_mod);
    b.installArtifact(lib);

    // Tests
    const mod_tests = b.addTest(.{ .root_module = dpc_mod });
    const run_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
```

## Conditional compilation

```zig
const builtin = @import("builtin");

pub fn selectBackend() Backend {
    return switch (builtin.os.tag) {
        .linux, .macos => .opencl,
        .windows => .directml,
        else => .cpu_only,
    };
}

// Comptime feature detection
const has_opencl = @hasDecl(@import("build_options"), "enable_opencl");
```

### Build options

```zig
// In build.zig
const options = b.addOptions();
options.addOption(bool, "enable_opencl", enable_opencl);
exe.root_module.addOptions("build_options", options);

// In source
const build_options = @import("build_options");
if (build_options.enable_opencl) {
    // ... GPU code path
}
```

## Linking C libraries

### System library (e.g., OpenCL)

```zig
// In build.zig
const lib = b.addSharedLibrary(.{ ... });
lib.linkSystemLibrary("OpenCL");
lib.linkLibC(); // needed for C standard library

// Add include paths if non-standard location
lib.addSystemIncludePath(.{ .cwd_relative = "/opt/cuda/include" });
lib.addLibraryPath(.{ .cwd_relative = "/opt/cuda/lib64" });
```

### Vendored C library

```zig
lib.addCSourceFiles(.{
    .files = &.{ "vendor/foo/foo.c", "vendor/foo/bar.c" },
    .flags = &.{ "-std=c11", "-O2" },
});
lib.addIncludePath(b.path("vendor/foo/include"));
```

## Cross-compilation

```zig
// Command line:
// zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseFast

// In build.zig — target is handled automatically via standardTargetOptions
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});
```

### Platform-specific source files

```zig
const root_source = if (target.result.os.tag == .windows)
    b.path("src/backend_win.zig")
else
    b.path("src/backend_posix.zig");
```

## Build options for GPU backend selection

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gpu_backend = b.option(
        enum { none, opencl, cuda },
        "gpu",
        "GPU backend to use",
    ) orelse .none;

    const options = b.addOptions();
    options.addOption(@TypeOf(gpu_backend), "gpu_backend", gpu_backend);

    const mod = b.addModule("differentia", .{
        .root_source_file = b.path("src/dpc/tensor.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("build_options", options);

    if (gpu_backend == .opencl) {
        mod.linkSystemLibrary("OpenCL", .{});
        mod.linkLibC(.{});
    }
}
```

## Test step configuration

### Multiple test targets

```zig
const test_step = b.step("test", "Run all tests");

// Unit tests
const unit_tests = b.addTest(.{ .root_module = dpc_mod });
test_step.dependOn(&b.addRunArtifact(unit_tests).step);

// Integration tests
const integration_tests = b.addTest(.{
    .root_source_file = b.path("tests/integration.zig"),
    .target = target,
    .optimize = optimize,
});
integration_tests.root_module.addImport("differentia", dpc_mod);
test_step.dependOn(&b.addRunArtifact(integration_tests).step);
```

### Test filter

```bash
# Run only tests matching pattern
zig build test -- --test-filter "fr5"
```

### Debug vs release tests

```zig
// Safety checks active in debug
const safety_tests = b.addTest(.{
    .root_source_file = b.path("tests/safety.zig"),
    .optimize = .Debug, // force debug mode for safety checks
});
```
