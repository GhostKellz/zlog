const std = @import("std");
const testing = std.testing;
const zlog = @import("zlog");
const build_options = @import("build_options");

// Memory profiling and optimization tools for zlog

pub const MemoryProfile = struct {
    initial_memory: usize,
    peak_memory: usize,
    final_memory: usize,
    allocations: u64,
    deallocations: u64,
    bytes_allocated: u64,
    bytes_freed: u64,

    pub fn print(self: MemoryProfile) void {
        std.debug.print("\n📊 Memory Profile\n");
        std.debug.print("================\n");
        std.debug.print("Initial memory: {d} bytes\n", .{self.initial_memory});
        std.debug.print("Peak memory: {d} bytes\n", .{self.peak_memory});
        std.debug.print("Final memory: {d} bytes\n", .{self.final_memory});
        std.debug.print("Memory growth: {d} bytes\n", .{self.final_memory - self.initial_memory});
        std.debug.print("Allocations: {d}\n", .{self.allocations});
        std.debug.print("Deallocations: {d}\n", .{self.deallocations});
        std.debug.print("Bytes allocated: {d}\n", .{self.bytes_allocated});
        std.debug.print("Bytes freed: {d}\n", .{self.bytes_freed});
        std.debug.print("Potential leaks: {d} bytes\n", .{self.bytes_allocated - self.bytes_freed});
    }
};

pub const ProfiledAllocator = struct {
    backing_allocator: std.mem.Allocator,
    allocations: std.atomic.Value(u64),
    deallocations: std.atomic.Value(u64),
    bytes_allocated: std.atomic.Value(u64),
    bytes_freed: std.atomic.Value(u64),
    peak_memory: std.atomic.Value(usize),
    current_memory: std.atomic.Value(usize),

    const Self = @This();

    pub fn init(backing_allocator: std.mem.Allocator) Self {
        return Self{
            .backing_allocator = backing_allocator,
            .allocations = std.atomic.Value(u64).init(0),
            .deallocations = std.atomic.Value(u64).init(0),
            .bytes_allocated = std.atomic.Value(u64).init(0),
            .bytes_freed = std.atomic.Value(u64).init(0),
            .peak_memory = std.atomic.Value(usize).init(0),
            .current_memory = std.atomic.Value(usize).init(0),
        };
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
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
        const self: *Self = @ptrCast(@alignCast(ctx));
        const result = self.backing_allocator.rawAlloc(len, ptr_align, ret_addr);

        if (result != null) {
            _ = self.allocations.fetchAdd(1, .monotonic);
            _ = self.bytes_allocated.fetchAdd(len, .monotonic);

            const current = self.current_memory.fetchAdd(len, .monotonic) + len;
            const peak = self.peak_memory.load(.monotonic);
            if (current > peak) {
                self.peak_memory.store(current, .monotonic);
            }
        }

        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const result = self.backing_allocator.rawResize(buf, buf_align, new_len, ret_addr);

        if (result) {
            if (new_len > buf.len) {
                _ = self.bytes_allocated.fetchAdd(new_len - buf.len, .monotonic);
                _ = self.current_memory.fetchAdd(new_len - buf.len, .monotonic);
            } else {
                _ = self.bytes_freed.fetchAdd(buf.len - new_len, .monotonic);
                _ = self.current_memory.fetchSub(buf.len - new_len, .monotonic);
            }
        }

        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        _ = self.deallocations.fetchAdd(1, .monotonic);
        _ = self.bytes_freed.fetchAdd(buf.len, .monotonic);
        _ = self.current_memory.fetchSub(buf.len, .monotonic);

        self.backing_allocator.rawFree(buf, buf_align, ret_addr);
    }

    pub fn getProfile(self: *Self, initial_memory: usize) MemoryProfile {
        return MemoryProfile{
            .initial_memory = initial_memory,
            .peak_memory = self.peak_memory.load(.monotonic),
            .final_memory = self.current_memory.load(.monotonic),
            .allocations = self.allocations.load(.monotonic),
            .deallocations = self.deallocations.load(.monotonic),
            .bytes_allocated = self.bytes_allocated.load(.monotonic),
            .bytes_freed = self.bytes_freed.load(.monotonic),
        };
    }
};

pub fn profileBasicLogging(backing_allocator: std.mem.Allocator) !MemoryProfile {
    var profiled = ProfiledAllocator.init(backing_allocator);
    const allocator = profiled.allocator();

    const initial_memory = profiled.current_memory.load(.monotonic);

    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
        .output_target = .stderr,
        .buffer_size = 4096,
    });
    defer logger.deinit();

    // Basic logging operations
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        logger.info("Memory profiling test {d}", .{i});
    }

    return profiled.getProfile(initial_memory);
}

pub fn profileStructuredLogging(backing_allocator: std.mem.Allocator) !MemoryProfile {
    var profiled = ProfiledAllocator.init(backing_allocator);
    const allocator = profiled.allocator();

    const initial_memory = profiled.current_memory.load(.monotonic);

    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
        .output_target = .stderr,
        .buffer_size = 4096,
    });
    defer logger.deinit();

    // Structured logging operations
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const fields = [_]zlog.Field{
            .{ .key = "iteration", .value = .{ .uint = i } },
            .{ .key = "test_type", .value = .{ .string = "structured_memory" } },
            .{ .key = "memory_test", .value = .{ .boolean = true } },
        };
        logger.logWithFields(.info, "Structured memory test", &fields);
    }

    return profiled.getProfile(initial_memory);
}

pub fn profileAsyncLogging(backing_allocator: std.mem.Allocator) !MemoryProfile {
    if (!build_options.enable_async) {
        return MemoryProfile{
            .initial_memory = 0,
            .peak_memory = 0,
            .final_memory = 0,
            .allocations = 0,
            .deallocations = 0,
            .bytes_allocated = 0,
            .bytes_freed = 0,
        };
    }

    var profiled = ProfiledAllocator.init(backing_allocator);
    const allocator = profiled.allocator();

    const initial_memory = profiled.current_memory.load(.monotonic);

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .format = .text,
        .output_target = .stderr,
        .buffer_size = 4096,
    });
    defer logger.deinit();

    // Async logging operations
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        logger.info("Async memory profiling test {d}", .{i});
    }

    // Wait for async processing
    std.time.sleep(50_000_000); // 50ms

    return profiled.getProfile(initial_memory);
}

pub fn profileFileLogging(backing_allocator: std.mem.Allocator) !MemoryProfile {
    if (!build_options.enable_file_targets) {
        return MemoryProfile{
            .initial_memory = 0,
            .peak_memory = 0,
            .final_memory = 0,
            .allocations = 0,
            .deallocations = 0,
            .bytes_allocated = 0,
            .bytes_freed = 0,
        };
    }

    var profiled = ProfiledAllocator.init(backing_allocator);
    const allocator = profiled.allocator();

    const initial_memory = profiled.current_memory.load(.monotonic);
    const test_file = "/tmp/memory_profile_test.log";

    // Clean up
    std.fs.cwd().deleteFile(test_file) catch {};

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .file,
        .file_path = test_file,
        .format = .text,
        .buffer_size = 4096,
    });
    defer logger.deinit();

    // File logging operations
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        logger.info("File memory profiling test {d}", .{i});
    }

    // Clean up
    std.fs.cwd().deleteFile(test_file) catch {};

    return profiled.getProfile(initial_memory);
}

pub fn runMemoryProfilingTests(backing_allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔍 Memory Profiling Tests\n");
    std.debug.print("=========================\n");

    {
        const profile = try profileBasicLogging(backing_allocator);
        std.debug.print("\n--- Basic Logging ---");
        profile.print();
    }

    {
        const profile = try profileStructuredLogging(backing_allocator);
        std.debug.print("\n--- Structured Logging ---");
        profile.print();
    }

    {
        const profile = try profileAsyncLogging(backing_allocator);
        if (build_options.enable_async) {
            std.debug.print("\n--- Async Logging ---");
            profile.print();
        } else {
            std.debug.print("\n--- Async Logging (Disabled) ---\n");
        }
    }

    {
        const profile = try profileFileLogging(backing_allocator);
        if (build_options.enable_file_targets) {
            std.debug.print("\n--- File Logging ---");
            profile.print();
        } else {
            std.debug.print("\n--- File Logging (Disabled) ---\n");
        }
    }
}

// Optimization suggestions based on profiling
pub fn analyzeMemoryUsage(profiles: []const MemoryProfile) void {
    std.debug.print("\n💡 Memory Usage Analysis\n");
    std.debug.print("========================\n");

    var total_allocations: u64 = 0;
    var total_peak_memory: usize = 0;

    for (profiles) |profile| {
        total_allocations += profile.allocations;
        total_peak_memory += profile.peak_memory;
    }

    std.debug.print("Total allocations across tests: {d}\n", .{total_allocations});
    std.debug.print("Total peak memory: {d} bytes\n", .{total_peak_memory});

    // Provide optimization suggestions
    std.debug.print("\n🚀 Optimization Suggestions:\n");

    if (total_allocations > 10000) {
        std.debug.print("- Consider increasing buffer sizes to reduce allocations\n");
    }

    if (total_peak_memory > 1024 * 1024) { // 1MB
        std.debug.print("- Memory usage is high, consider optimizing data structures\n");
    }

    std.debug.print("- Use appropriate buffer sizes for your workload\n");
    std.debug.print("- Consider async I/O for high-throughput scenarios\n");
    std.debug.print("- Monitor memory growth in long-running applications\n");
}

// Test functions
test "memory profiling: basic logging" {
    const profile = try profileBasicLogging(testing.allocator);
    profile.print();
    try testing.expect(profile.allocations > 0);
}

test "memory profiling: structured logging" {
    const profile = try profileStructuredLogging(testing.allocator);
    profile.print();
    try testing.expect(profile.allocations > 0);
}

test "memory profiling: async logging" {
    const profile = try profileAsyncLogging(testing.allocator);
    if (build_options.enable_async) {
        profile.print();
        try testing.expect(profile.allocations > 0);
    }
}

test "memory profiling: file logging" {
    const profile = try profileFileLogging(testing.allocator);
    if (build_options.enable_file_targets) {
        profile.print();
        try testing.expect(profile.allocations > 0);
    }
}

test "memory profiling: comprehensive analysis" {
    try runMemoryProfilingTests(testing.allocator);
}