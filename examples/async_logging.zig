// Async logging example
// Shows non-blocking high-performance logging

const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Async Logging Benchmark\n", .{});
    std.debug.print("========================\n\n", .{});

    // Synchronous logging benchmark
    {
        var logger = try zlog.Logger.init(allocator, .{
            .level = .info,
            .format = .text,
            .output_target = .file,
            .file_path = "sync.log",
            .async_io = false,
        });
        defer logger.deinit();

        const iterations = 50000;
        const start = std.time.nanoTimestamp();

        var i: u32 = 0;
        while (i < iterations) : (i += 1) {
            logger.info("Synchronous log message {d}", .{i});
        }

        const end = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
        const messages_per_second = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

        std.debug.print("Synchronous Logging:\n", .{});
        std.debug.print("  Messages: {d}\n", .{iterations});
        std.debug.print("  Duration: {d:.2}ms\n", .{duration_ms});
        std.debug.print("  Throughput: {d:.0} msg/s\n\n", .{messages_per_second});
    }

    // Asynchronous logging benchmark
    {
        var logger = try zlog.Logger.init(allocator, .{
            .level = .info,
            .format = .text,
            .output_target = .file,
            .file_path = "async.log",
            .async_io = true,
            .buffer_size = 16384,
        });
        defer logger.deinit();

        const iterations = 50000;
        const start = std.time.nanoTimestamp();

        var i: u32 = 0;
        while (i < iterations) : (i += 1) {
            logger.info("Asynchronous log message {d}", .{i});
        }

        const end = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
        const messages_per_second = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

        std.debug.print("Asynchronous Logging:\n", .{});
        std.debug.print("  Messages: {d}\n", .{iterations});
        std.debug.print("  Duration: {d:.2}ms\n", .{duration_ms});
        std.debug.print("  Throughput: {d:.0} msg/s\n\n", .{messages_per_second});

        // Give async thread time to flush
        std.time.sleep(500 * std.time.ns_per_ms);
    }

    std.debug.print("Compare sync.log and async.log to see the results!\n", .{});
}
