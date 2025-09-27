const std = @import("std");
const testing = std.testing;
const zlog = @import("zlog");
const build_options = @import("build_options");

// Comprehensive benchmarking suite for zlog

pub const BenchmarkResult = struct {
    name: []const u8,
    iterations: u32,
    total_time_ns: u64,
    messages_per_second: f64,
    bytes_per_second: f64,
    memory_used: usize,

    pub fn print(self: BenchmarkResult) void {
        std.debug.print("\n=== {s} ===\n", .{self.name});
        std.debug.print("Iterations: {d}\n", .{self.iterations});
        std.debug.print("Total time: {d:.2}ms\n", .{@as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000.0});
        std.debug.print("Messages/sec: {d:.0}\n", .{self.messages_per_second});
        std.debug.print("Bytes/sec: {d:.0}\n", .{self.bytes_per_second});
        std.debug.print("Memory used: {d} bytes\n", .{self.memory_used});
    }
};

pub fn benchmarkTextFormat(allocator: std.mem.Allocator, iterations: u32) !BenchmarkResult {
    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
        .output_target = .stderr,
        .buffer_size = 8192,
    });
    defer logger.deinit();

    const message = "Benchmark test message with moderate length and some structure";
    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        logger.info("{s} {d}", .{ message, i });
    }

    const end = std.time.nanoTimestamp();
    const total_time = end - start;
    const seconds = @as(f64, @floatFromInt(total_time)) / 1_000_000_000.0;
    const messages_per_sec = @as(f64, @floatFromInt(iterations)) / seconds;

    // Estimate bytes written
    const avg_message_size = message.len + 20; // Approximate with timestamp and formatting
    const total_bytes = avg_message_size * iterations;
    const bytes_per_sec = @as(f64, @floatFromInt(total_bytes)) / seconds;

    return BenchmarkResult{
        .name = "Text Format",
        .iterations = iterations,
        .total_time_ns = total_time,
        .messages_per_second = messages_per_sec,
        .bytes_per_second = bytes_per_sec,
        .memory_used = logger.buffer.capacity,
    };
}

pub fn benchmarkJsonFormat(allocator: std.mem.Allocator, iterations: u32) !BenchmarkResult {
    if (!build_options.enable_json) {
        return BenchmarkResult{
            .name = "JSON Format (Disabled)",
            .iterations = 0,
            .total_time_ns = 0,
            .messages_per_second = 0,
            .bytes_per_second = 0,
            .memory_used = 0,
        };
    }

    var logger = try zlog.Logger.init(allocator, .{
        .format = .json,
        .output_target = .stderr,
        .buffer_size = 8192,
    });
    defer logger.deinit();

    const message = "Benchmark test message with moderate length";
    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        logger.info("{s} {d}", .{ message, i });
    }

    const end = std.time.nanoTimestamp();
    const total_time = end - start;
    const seconds = @as(f64, @floatFromInt(total_time)) / 1_000_000_000.0;
    const messages_per_sec = @as(f64, @floatFromInt(iterations)) / seconds;

    const avg_message_size = message.len + 80; // JSON overhead
    const total_bytes = avg_message_size * iterations;
    const bytes_per_sec = @as(f64, @floatFromInt(total_bytes)) / seconds;

    return BenchmarkResult{
        .name = "JSON Format",
        .iterations = iterations,
        .total_time_ns = total_time,
        .messages_per_second = messages_per_sec,
        .bytes_per_second = bytes_per_sec,
        .memory_used = logger.buffer.capacity,
    };
}

pub fn benchmarkBinaryFormat(allocator: std.mem.Allocator, iterations: u32) !BenchmarkResult {
    if (!build_options.enable_binary_format) {
        return BenchmarkResult{
            .name = "Binary Format (Disabled)",
            .iterations = 0,
            .total_time_ns = 0,
            .messages_per_second = 0,
            .bytes_per_second = 0,
            .memory_used = 0,
        };
    }

    var logger = try zlog.Logger.init(allocator, .{
        .format = .binary,
        .output_target = .stderr,
        .buffer_size = 8192,
    });
    defer logger.deinit();

    const message = "Benchmark test message with moderate length";
    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        logger.info("{s} {d}", .{ message, i });
    }

    const end = std.time.nanoTimestamp();
    const total_time = end - start;
    const seconds = @as(f64, @floatFromInt(total_time)) / 1_000_000_000.0;
    const messages_per_sec = @as(f64, @floatFromInt(iterations)) / seconds;

    const avg_message_size = message.len + 15; // Binary format is compact
    const total_bytes = avg_message_size * iterations;
    const bytes_per_sec = @as(f64, @floatFromInt(total_bytes)) / seconds;

    return BenchmarkResult{
        .name = "Binary Format",
        .iterations = iterations,
        .total_time_ns = total_time,
        .messages_per_second = messages_per_sec,
        .bytes_per_second = bytes_per_sec,
        .memory_used = logger.buffer.capacity,
    };
}

pub fn benchmarkStructuredLogging(allocator: std.mem.Allocator, iterations: u32) !BenchmarkResult {
    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
        .output_target = .stderr,
        .buffer_size = 8192,
    });
    defer logger.deinit();

    const fields = [_]zlog.Field{
        .{ .key = "user_id", .value = .{ .uint = 12345 } },
        .{ .key = "action", .value = .{ .string = "benchmark" } },
        .{ .key = "success", .value = .{ .boolean = true } },
        .{ .key = "latency", .value = .{ .float = 15.7 } },
    };

    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        logger.logWithFields(.info, "Structured benchmark message", &fields);
    }

    const end = std.time.nanoTimestamp();
    const total_time = end - start;
    const seconds = @as(f64, @floatFromInt(total_time)) / 1_000_000_000.0;
    const messages_per_sec = @as(f64, @floatFromInt(iterations)) / seconds;

    const avg_message_size = 120; // Estimated with fields
    const total_bytes = avg_message_size * iterations;
    const bytes_per_sec = @as(f64, @floatFromInt(total_bytes)) / seconds;

    return BenchmarkResult{
        .name = "Structured Logging",
        .iterations = iterations,
        .total_time_ns = total_time,
        .messages_per_second = messages_per_sec,
        .bytes_per_second = bytes_per_sec,
        .memory_used = logger.buffer.capacity,
    };
}

pub fn benchmarkAsyncLogging(allocator: std.mem.Allocator, iterations: u32) !BenchmarkResult {
    if (!build_options.enable_async) {
        return BenchmarkResult{
            .name = "Async Logging (Disabled)",
            .iterations = 0,
            .total_time_ns = 0,
            .messages_per_second = 0,
            .bytes_per_second = 0,
            .memory_used = 0,
        };
    }

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .format = .text,
        .output_target = .stderr,
        .buffer_size = 8192,
    });
    defer logger.deinit();

    const message = "Async benchmark test message";
    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        logger.info("{s} {d}", .{ message, i });
    }

    const end = std.time.nanoTimestamp();

    // Give time for async processing
    std.time.sleep(50_000_000); // 50ms

    const total_time = end - start;
    const seconds = @as(f64, @floatFromInt(total_time)) / 1_000_000_000.0;
    const messages_per_sec = @as(f64, @floatFromInt(iterations)) / seconds;

    const avg_message_size = message.len + 20;
    const total_bytes = avg_message_size * iterations;
    const bytes_per_sec = @as(f64, @floatFromInt(total_bytes)) / seconds;

    return BenchmarkResult{
        .name = "Async Logging",
        .iterations = iterations,
        .total_time_ns = total_time,
        .messages_per_second = messages_per_sec,
        .bytes_per_second = bytes_per_sec,
        .memory_used = logger.buffer.capacity,
    };
}

pub fn benchmarkSampledLogging(allocator: std.mem.Allocator, iterations: u32) !BenchmarkResult {
    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
        .output_target = .stderr,
        .sampling_rate = 0.1, // Sample 10% of messages
        .buffer_size = 8192,
    });
    defer logger.deinit();

    const message = "Sampled benchmark test message";
    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        logger.info("{s} {d}", .{ message, i });
    }

    const end = std.time.nanoTimestamp();
    const total_time = end - start;
    const seconds = @as(f64, @floatFromInt(total_time)) / 1_000_000_000.0;
    const messages_per_sec = @as(f64, @floatFromInt(iterations)) / seconds;

    // Note: Actual logged messages are ~10% due to sampling
    const avg_message_size = message.len + 20;
    const total_bytes = avg_message_size * iterations;
    const bytes_per_sec = @as(f64, @floatFromInt(total_bytes)) / seconds;

    return BenchmarkResult{
        .name = "Sampled Logging (10%)",
        .iterations = iterations,
        .total_time_ns = total_time,
        .messages_per_second = messages_per_sec,
        .bytes_per_second = bytes_per_sec,
        .memory_used = logger.buffer.capacity,
    };
}

pub fn benchmarkMemoryUsage(allocator: std.mem.Allocator) !BenchmarkResult {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const memory_allocator = gpa.allocator();

    const start_memory = try std.process.totalSystemMemory();

    var logger = try zlog.Logger.init(memory_allocator, .{
        .format = .text,
        .output_target = .stderr,
        .buffer_size = 4096,
    });
    defer logger.deinit();

    const iterations = 1000;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const fields = [_]zlog.Field{
            .{ .key = "memory_test", .value = .{ .uint = i } },
            .{ .key = "large_value", .value = .{ .string = "x" ** 100 } },
        };
        logger.logWithFields(.info, "Memory usage test", &fields);
    }

    const end_memory = try std.process.totalSystemMemory();
    const memory_used = if (end_memory > start_memory) end_memory - start_memory else 0;

    return BenchmarkResult{
        .name = "Memory Usage",
        .iterations = iterations,
        .total_time_ns = 0,
        .messages_per_second = 0,
        .bytes_per_second = 0,
        .memory_used = memory_used,
    };
}

pub fn runComprehensiveBenchmarks(allocator: std.mem.Allocator) !void {
    const iterations = 10000;

    std.debug.print("\n🚀 zlog Comprehensive Benchmark Suite\n");
    std.debug.print("=====================================\n");
    std.debug.print("Iterations per test: {d}\n", .{iterations});

    var results = std.ArrayList(BenchmarkResult).init(allocator);
    defer results.deinit();

    // Run all benchmarks
    try results.append(try benchmarkTextFormat(allocator, iterations));
    try results.append(try benchmarkJsonFormat(allocator, iterations));
    try results.append(try benchmarkBinaryFormat(allocator, iterations));
    try results.append(try benchmarkStructuredLogging(allocator, iterations));
    try results.append(try benchmarkAsyncLogging(allocator, iterations));
    try results.append(try benchmarkSampledLogging(allocator, iterations));
    try results.append(try benchmarkMemoryUsage(allocator));

    // Print all results
    for (results.items) |result| {
        result.print();
    }

    // Summary
    std.debug.print("\n📊 Performance Summary\n");
    std.debug.print("=====================\n");

    var best_throughput: f64 = 0;
    var best_format: []const u8 = "";

    for (results.items) |result| {
        if (result.messages_per_second > best_throughput) {
            best_throughput = result.messages_per_second;
            best_format = result.name;
        }
    }

    std.debug.print("Best throughput: {d:.0} msg/sec ({s})\n", .{ best_throughput, best_format });

    // Calculate messages per millisecond for comparison with targets
    const best_msg_per_ms = best_throughput / 1000.0;
    std.debug.print("Best rate: {d:.0} msg/ms\n", .{best_msg_per_ms});

    // Check against targets
    const text_target = 50000; // 50k msg/ms target
    const binary_target = 80000; // 80k msg/ms target

    std.debug.print("\n🎯 Target Comparison:\n");
    std.debug.print("Text format target: {d} msg/ms\n", .{text_target});
    std.debug.print("Binary format target: {d} msg/ms\n", .{binary_target});

    if (best_msg_per_ms >= text_target) {
        std.debug.print("✅ Performance targets met!\n");
    } else {
        std.debug.print("⚠️  Performance below targets\n");
    }
}

// Individual test functions for the test runner
test "benchmark: text format performance" {
    const result = try benchmarkTextFormat(testing.allocator, 1000);
    result.print();
    try testing.expect(result.messages_per_second > 0);
}

test "benchmark: json format performance" {
    const result = try benchmarkJsonFormat(testing.allocator, 1000);
    result.print();
    // Will show as disabled if JSON not enabled
}

test "benchmark: binary format performance" {
    const result = try benchmarkBinaryFormat(testing.allocator, 1000);
    result.print();
    // Will show as disabled if binary not enabled
}

test "benchmark: structured logging performance" {
    const result = try benchmarkStructuredLogging(testing.allocator, 1000);
    result.print();
    try testing.expect(result.messages_per_second > 0);
}

test "benchmark: async logging performance" {
    const result = try benchmarkAsyncLogging(testing.allocator, 1000);
    result.print();
    // Will show as disabled if async not enabled
}

test "benchmark: sampled logging performance" {
    const result = try benchmarkSampledLogging(testing.allocator, 1000);
    result.print();
    try testing.expect(result.messages_per_second > 0);
}

test "benchmark: comprehensive suite" {
    try runComprehensiveBenchmarks(testing.allocator);
}