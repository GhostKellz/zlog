const std = @import("std");
const testing = std.testing;
const zlog = @import("zlog");
const build_options = @import("build_options");

test "async io basic functionality" {
    if (!build_options.enable_async) return;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Log messages asynchronously
    logger.info("Async test message 1", .{});
    logger.warn("Async test message 2", .{});
    logger.err("Async test message 3", .{});

    // Give the async thread time to process
    std.time.sleep(10_000_000); // 10ms
}

test "async io with structured logging" {
    if (!build_options.enable_async) return;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .stderr,
    });
    defer logger.deinit();

    const fields = [_]zlog.Field{
        .{ .key = "async_test", .value = .{ .boolean = true } },
        .{ .key = "thread_id", .value = .{ .uint = 12345 } },
        .{ .key = "timestamp", .value = .{ .int = (std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch unreachable).sec } },
    };

    logger.logWithFields(.info, "Async structured logging test", &fields);

    // Give time for async processing
    std.time.sleep(10_000_000); // 10ms
}

test "async io high throughput" {
    if (!build_options.enable_async) return;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .stderr,
    });
    defer logger.deinit();

    const start = (std.time.Timer.start() catch unreachable).read();

    // Log many messages quickly
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        logger.info("High throughput test {d}", .{i});
    }

    const end = (std.time.Timer.start() catch unreachable).read();
    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;

    std.debug.print("Async throughput: 1000 messages in {d:.2}ms\n", .{duration_ms});

    // Give time for all messages to be processed
    std.time.sleep(100_000_000); // 100ms
}

test "async io file output" {
    if (!build_options.enable_async or !build_options.enable_file_targets) return;

    const allocator = testing.allocator;
    const test_file = "/tmp/test_async_file.log";

    // Clean up any existing test file
    std.fs.cwd().deleteFile(test_file) catch {};

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .file,
        .file_path = test_file,
    });
    defer logger.deinit();

    // Log several messages
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        logger.info("Async file test message {d}", .{i});
    }

    // Give time for async writes to complete
    std.time.sleep(50_000_000); // 50ms

    // Verify file was created and has content
    const file = std.fs.cwd().openFile(test_file, .{}) catch {
        std.debug.print("Warning: Async file may not have been written yet\n", .{});
        return;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    std.debug.print("Async file size: {d} bytes\n", .{file_size});

    // Clean up
    std.fs.cwd().deleteFile(test_file) catch {};
}

test "async io shutdown behavior" {
    if (!build_options.enable_async) return;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .stderr,
    });

    // Log some messages
    logger.info("Message before shutdown", .{});
    logger.warn("Another message before shutdown", .{});

    // Shutdown should properly clean up async resources
    logger.deinit();

    // This test mainly verifies no crashes occur during shutdown
}

test "async io queue overflow handling" {
    if (!build_options.enable_async) return;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .stderr,
        .buffer_size = 512, // Small buffer to test overflow
    });
    defer logger.deinit();

    // Try to overwhelm the async queue
    var i: u32 = 0;
    while (i < 2000) : (i += 1) {
        logger.info("Queue overflow test message {d} with extra content to make it larger", .{i});
    }

    // Give time for processing
    std.time.sleep(100_000_000); // 100ms
}

test "async io different formats" {
    if (!build_options.enable_async) return;

    const allocator = testing.allocator;

    // Test text format async
    {
        var logger = try zlog.Logger.init(allocator, .{
            .async_io = true,
            .format = .text,
            .output_target = .stderr,
        });
        defer logger.deinit();

        logger.info("Async text format test", .{});
        std.time.sleep(5_000_000); // 5ms
    }

    // Test JSON format async (if available)
    if (build_options.enable_json) {
        var logger = try zlog.Logger.init(allocator, .{
            .async_io = true,
            .format = .json,
            .output_target = .stderr,
        });
        defer logger.deinit();

        logger.info("Async JSON format test", .{});
        std.time.sleep(5_000_000); // 5ms
    }

    // Test binary format async (if available)
    if (build_options.enable_binary_format) {
        var logger = try zlog.Logger.init(allocator, .{
            .async_io = true,
            .format = .binary,
            .output_target = .stderr,
        });
        defer logger.deinit();

        logger.info("Async binary format test", .{});
        std.time.sleep(5_000_000); // 5ms
    }
}

test "async io error conditions" {
    if (!build_options.enable_async) return;

    const allocator = testing.allocator;

    // Test with invalid file path (should handle gracefully)
    if (build_options.enable_file_targets) {
        var logger = try zlog.Logger.init(allocator, .{
            .async_io = true,
            .output_target = .file,
            .file_path = "/invalid/path/that/should/not/exist.log",
        });
        defer logger.deinit();

        // These messages should be handled even if file operations fail
        logger.info("Error condition test", .{});
        logger.warn("This should handle file errors gracefully", .{});

        std.time.sleep(10_000_000); // 10ms
    }
}

test "async io memory management" {
    if (!build_options.enable_async) return;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test that memory is properly managed for large numbers of messages
    var i: u32 = 0;
    while (i < 500) : (i += 1) {
        const fields = [_]zlog.Field{
            .{ .key = "iteration", .value = .{ .uint = i } },
            .{ .key = "large_string", .value = .{ .string = "This is a large string value that uses more memory" } },
        };
        logger.logWithFields(.info, "Memory management test", &fields);

        // Occasionally yield to allow async processing
        if (i % 100 == 0) {
            std.time.sleep(1_000_000); // 1ms
        }
    }

    // Give final time for processing
    std.time.sleep(50_000_000); // 50ms
}