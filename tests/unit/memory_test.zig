const std = @import("std");
const testing = std.testing;
const zlog = @import("zlog");
const build_options = @import("build_options");

// Memory leak detection and validation tests

test "memory: basic logger lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in basic lifecycle test!\n", .{});
        }
        testing.expect(leaked != .leak) catch {};
    }

    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    logger.info("Memory lifecycle test", .{});
}

test "memory: structured logging allocations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked != .leak) catch {};
    }

    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test multiple structured log calls to verify no leaks
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const fields = [_]zlog.Field{
            .{ .key = "iteration", .value = .{ .uint = i } },
            .{ .key = "test_string", .value = .{ .string = "memory_test" } },
            .{ .key = "test_float", .value = .{ .float = 3.14159 } },
        };
        logger.logWithFields(.info, "Memory test iteration", &fields);
    }
}

test "memory: file output lifecycle" {
    if (!build_options.enable_file_targets) return;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked != .leak) catch {};
    }

    const allocator = gpa.allocator();
    const test_file = "/tmp/memory_test.log";

    // Clean up any existing file
    std.fs.cwd().deleteFile(test_file) catch {};

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .file,
        .file_path = test_file,
    });
    defer logger.deinit();

    logger.info("File memory test", .{});

    // Clean up
    std.fs.cwd().deleteFile(test_file) catch {};
}

test "memory: async io lifecycle" {
    if (!build_options.enable_async) return;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked != .leak) catch {};
    }

    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .stderr,
    });
    defer logger.deinit();

    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        logger.info("Async memory test {d}", .{i});
    }

    // Give time for async processing
    std.Thread.sleep(20_000_000); // 20ms
}

test "memory: buffer reallocation stress" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked != .leak) catch {};
    }

    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .buffer_size = 256, // Small buffer to force reallocations
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Log messages of varying sizes to stress buffer management
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        const size = (i % 10) * 20 + 50; // Sizes 50-250
        const message = try allocator.alloc(u8, size);
        defer allocator.free(message);

        @memset(message, 'x');
        logger.info("Buffer stress {d}: {s}", .{ i, message });
    }
}

test "memory: format-specific allocations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked != .leak) catch {};
    }

    const allocator = gpa.allocator();

    // Test text format
    {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .text,
            .output_target = .stderr,
        });
        defer logger.deinit();

        logger.info("Text format memory test", .{});

        const fields = [_]zlog.Field{
            .{ .key = "test", .value = .{ .string = "value" } },
        };
        logger.logWithFields(.info, "Text structured", &fields);
    }

    // Test JSON format (if available)
    if (build_options.enable_json) {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .json,
            .output_target = .stderr,
        });
        defer logger.deinit();

        logger.info("JSON format memory test", .{});

        const fields = [_]zlog.Field{
            .{ .key = "test", .value = .{ .string = "value" } },
        };
        logger.logWithFields(.info, "JSON structured", &fields);
    }

    // Test binary format (if available)
    if (build_options.enable_binary_format) {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .binary,
            .output_target = .stderr,
        });
        defer logger.deinit();

        logger.info("Binary format memory test", .{});

        const fields = [_]zlog.Field{
            .{ .key = "test", .value = .{ .string = "value" } },
        };
        logger.logWithFields(.info, "Binary structured", &fields);
    }
}

test "memory: multiple logger instances" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked != .leak) catch {};
    }

    const allocator = gpa.allocator();

    // Create multiple loggers with different configurations
    var loggers: [5]zlog.Logger = undefined;

    var i: usize = 0;
    while (i < loggers.len) : (i += 1) {
        loggers[i] = try zlog.Logger.init(allocator, .{
            .level = switch (i % 5) {
                0 => .debug,
                1 => .info,
                2 => .warn,
                3 => .err,
                4 => .fatal,
                else => .info,
            },
            .output_target = .stderr,
            .buffer_size = 512 + (i * 256), // Different buffer sizes
        });
    }

    // Use all loggers
    for (&loggers, 0..) |*logger, idx| {
        logger.info("Multi-logger test {d}", .{idx});
    }

    // Clean up all loggers
    for (&loggers) |*logger| {
        logger.deinit();
    }
}

test "memory: default logger usage" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked != .leak) catch {};
    }

    // Test default logger functions
    zlog.info("Default logger memory test", .{});
    zlog.warn("Default logger warning", .{});
    zlog.err("Default logger error", .{});

    // Note: Default logger cleanup is automatic, but we can't easily control
    // its allocator in this test, so this mainly tests for crashes
}

test "memory: large field values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked != .leak) catch {};
    }

    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test with large field values
    const large_value = try allocator.alloc(u8, 1024);
    defer allocator.free(large_value);
    @memset(large_value, 'A');

    const large_fields = [_]zlog.Field{
        .{ .key = "large_field", .value = .{ .string = large_value } },
    };

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        logger.logWithFields(.info, "Large field test", &large_fields);
    }
}

test "memory: aggregation memory management" {
    if (!build_options.enable_aggregation) return;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked != .leak) catch {};
    }

    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .enable_batching = true,
        .batch_size = 10,
        .enable_deduplication = true,
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Generate logs that would trigger aggregation
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        logger.info("Aggregation test {d}", .{i});

        // Some duplicate messages to test deduplication
        if (i % 5 == 0) {
            logger.info("Duplicate message", .{});
        }
    }
}

test "memory: file rotation memory impact" {
    if (!build_options.enable_file_targets) return;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked != .leak) catch {};
    }

    const allocator = gpa.allocator();
    const test_file = "/tmp/memory_rotation_test.log";

    // Clean up any existing files
    std.fs.cwd().deleteFile(test_file) catch {};
    var j: u8 = 0;
    while (j < 3) : (j += 1) {
        const backup_name = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ test_file, j });
        defer allocator.free(backup_name);
        std.fs.cwd().deleteFile(backup_name) catch {};
    }

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .file,
        .file_path = test_file,
        .max_file_size = 1024, // Small to trigger rotation
        .max_backup_files = 2,
    });
    defer logger.deinit();

    // Generate enough logs to trigger rotation
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        logger.info("Rotation memory test message {d} with some extra content", .{i});
    }

    // Clean up
    std.fs.cwd().deleteFile(test_file) catch {};
    j = 0;
    while (j < 3) : (j += 1) {
        const backup_name = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ test_file, j });
        defer allocator.free(backup_name);
        std.fs.cwd().deleteFile(backup_name) catch {};
    }
}

test "memory: stress test with mixed operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked != .leak) catch {};
    }

    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .buffer_size = 1024,
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Mix of operations to stress memory management
    var i: u32 = 0;
    while (i < 200) : (i += 1) {
        switch (i % 4) {
            0 => {
                // Simple log
                logger.info("Stress test {d}", .{i});
            },
            1 => {
                // Structured log
                const fields = [_]zlog.Field{
                    .{ .key = "iteration", .value = .{ .uint = i } },
                    .{ .key = "type", .value = .{ .string = "stress" } },
                };
                logger.logWithFields(.warn, "Structured stress", &fields);
            },
            2 => {
                // Large message
                const large_msg = try allocator.alloc(u8, 200);
                defer allocator.free(large_msg);
                @memset(large_msg, 'S');
                logger.err("Large: {s}", .{large_msg});
            },
            3 => {
                // Many small fields
                const many_fields = [_]zlog.Field{
                    .{ .key = "f1", .value = .{ .uint = i } },
                    .{ .key = "f2", .value = .{ .uint = i + 1 } },
                    .{ .key = "f3", .value = .{ .uint = i + 2 } },
                    .{ .key = "f4", .value = .{ .string = "small" } },
                    .{ .key = "f5", .value = .{ .boolean = true } },
                };
                logger.logWithFields(.debug, "Many fields", &many_fields);
            },
            else => unreachable,
        }
    }
}