# GPU Memory Patterns

## Device abstraction

```zig
pub const Device = enum {
    cpu,
    opencl,

    pub fn isGpu(self: Device) bool {
        return self != .cpu;
    }
};
```

Keep the device enum extensible. Operations dispatch on device:

```zig
pub fn add(self: *Tensor, other: *const Tensor) !void {
    switch (self.device) {
        .cpu => self.addCpu(other),
        .opencl => try self.addOpenCL(other),
    }
}
```

## CPU ↔ GPU transfer

### Copy to device

```zig
pub fn copyToDevice(self: *Tensor, device: Device) !Tensor {
    if (self.device == device) return self.*;

    var new = try Tensor.initOnDevice(self.allocator, self.getShape(), self.dtype, device);
    errdefer new.deinit();

    switch (device) {
        .opencl => {
            const cl_buf = try cl.createBuffer(self.byteSize());
            try cl.enqueueWriteBuffer(cl_buf, self.data[0..self.byteSize()]);
            new.device_handle = @intFromPtr(cl_buf);
        },
        .cpu => unreachable, // handled by early return
    }
    return new;
}
```

### Copy to host

```zig
pub fn copyToHost(self: *Tensor) !Tensor {
    if (self.device == .cpu) return self.*;

    var host = try Tensor.init(self.allocator, self.getShape(), self.dtype, .cpu);
    errdefer host.deinit();

    switch (self.device) {
        .opencl => {
            const cl_buf: cl.cl_mem = @ptrFromInt(self.device_handle);
            try cl.enqueueReadBuffer(cl_buf, host.data[0..host.byteSize()]);
        },
        .cpu => unreachable,
    }
    return host;
}
```

## OpenCL buffer management

### Buffer creation

```zig
pub fn createBuffer(context: cl.cl_context, size: usize, flags: cl.cl_mem_flags) !cl.cl_mem {
    var err: cl.cl_int = undefined;
    const buf = cl.clCreateBuffer(context, flags, size, null, &err);
    if (err != cl.CL_SUCCESS) return error.OpenCLBufferCreateFailed;
    return buf;
}
```

### Kernel dispatch

```zig
pub fn dispatchKernel(
    queue: cl.cl_command_queue,
    kernel: cl.cl_kernel,
    global_work_size: []const usize,
    local_work_size: ?[]const usize,
) !void {
    const ndim = global_work_size.len;
    const local = if (local_work_size) |l| l.ptr else null;
    const err = cl.clEnqueueNDRangeKernel(
        queue, kernel,
        @intCast(ndim),
        null,
        global_work_size.ptr,
        local,
        0, null, null,
    );
    if (err != cl.CL_SUCCESS) return error.OpenCLKernelFailed;
}
```

## Alignment for GPU coalesced access

GPU memory accesses are most efficient when threads in a warp access consecutive memory addresses.

```zig
// Ensure tensor data is aligned for GPU transfer
const gpu_alignment = 256; // bytes, typical for OpenCL
const aligned_buf = try allocator.alignedAlloc(u8, gpu_alignment, byte_size);
```

### Work-group size alignment

```zig
// Round up to work-group multiple for efficient dispatch
fn roundUpToMultiple(value: usize, multiple: usize) usize {
    return ((value + multiple - 1) / multiple) * multiple;
}

const padded_size = roundUpToMultiple(numel, work_group_size);
```

## Synchronization patterns

### Barrier after write

```zig
try cl.enqueueWriteBuffer(queue, buf, data);
const err = cl.clFinish(queue); // block until write completes
if (err != cl.CL_SUCCESS) return error.OpenCLSyncFailed;
```

### Event-based sync (non-blocking)

```zig
var event: cl.cl_event = undefined;
cl.clEnqueueNDRangeKernel(queue, kernel, ..., 1, &prev_event, &event);
// Later: wait on event
cl.clWaitForEvents(1, &event);
cl.clReleaseEvent(event);
```

### Double buffering

Overlap computation with data transfer:

```zig
// While GPU processes batch N, upload batch N+1
try cl.enqueueWriteBuffer(queue, buf_next, next_data); // async
try cl.enqueueNDRangeKernel(queue, kernel, buf_current); // compute
try cl.clFinish(queue);
std.mem.swap(cl.cl_mem, &buf_current, &buf_next);
```

## SoA layout for GPU

Structure of Arrays is critical for GPU coalesced memory access:

```zig
// BAD for GPU — AoS (Array of Structures)
const Particle = struct { x: f32, y: f32, z: f32, mass: f32 };
var particles: []Particle = ...; // x,y,z,mass,x,y,z,mass,...

// GOOD for GPU — SoA (Structure of Arrays)
const Particles = struct {
    x: []f32,     // x,x,x,x,...
    y: []f32,     // y,y,y,y,...
    z: []f32,     // z,z,z,z,...
    mass: []f32,  // m,m,m,m,...
    count: usize,
};
```

SoA ensures that when a GPU kernel reads `x` for all particles, those reads are contiguous in memory → maximum bandwidth utilization.
