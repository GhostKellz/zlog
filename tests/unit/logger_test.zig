const std = @import("std");
const testing = std.testing;
const zlog = @import("zlog");

// Test basic logger initialization and destruction
test "logger init and deinit" {
    const allocator = testing.allocator;

    // Test default configuration
    var logger = try zlog.Logger.init(allocator, .{});
    defer logger.deinit();

    try testing.expect(logger.config.level == .info);
    try testing.expect(logger.config.format == .text);
    try testing.expect(logger.config.output_target == .stdout);
}

test "logger configuration validation" {
    const allocator = testing.allocator;

    // Test invalid file configuration
    const invalid_config = zlog.LoggerConfig{
        .output_target = .file,
        .file_path = null, // Should cause validation error
    };

    try testing.expectError(error.FilePathRequired, zlog.Logger.init(allocator, invalid_config));
}

test "log level filtering" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .level = .warn,
        .output_target = .stderr, // Use stderr to avoid interfering with test output
    });
    defer logger.deinit();

    // These should not log (below threshold)
    logger.debug("debug message", .{});
    logger.info("info message", .{});

    // These should log (at or above threshold)
    logger.warn("warning message", .{});
    logger.err("error message", .{});
    logger.fatal("fatal message", .{});
}

test "structured logging with all field types" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .level = .debug,
        .output_target = .stderr,
    });
    defer logger.deinit();

    const fields = [_]zlog.Field{
        .{ .key = "string_field", .value = .{ .string = "test_string" } },
        .{ .key = "int_field", .value = .{ .int = -42 } },
        .{ .key = "uint_field", .value = .{ .uint = 42 } },
        .{ .key = "float_field", .value = .{ .float = 3.14159 } },
        .{ .key = "bool_field", .value = .{ .boolean = true } },
    };

    logger.logWithFields(.info, "Test message with all field types", &fields);
}

test "sampling configuration" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .sampling_rate = 0.5,
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test multiple messages to verify sampling
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        logger.info("Sample test {d}", .{i});
    }
}

test "format availability checking" {
    // Test format availability based on build options
    try testing.expect(zlog.Format.text.isAvailable());

    // JSON availability depends on build options
    const json_available = zlog.Format.json.isAvailable();
    if (json_available) {
        std.debug.print("JSON format is available\n", .{});
    }

    // Binary availability depends on build options
    const binary_available = zlog.Format.binary.isAvailable();
    if (binary_available) {
        std.debug.print("Binary format is available\n", .{});
    }
}

test "output target availability checking" {
    // These should always be available
    try testing.expect(zlog.OutputTarget.stdout.isAvailable());
    try testing.expect(zlog.OutputTarget.stderr.isAvailable());

    // File availability depends on build options
    const file_available = zlog.OutputTarget.file.isAvailable();
    if (file_available) {
        std.debug.print("File output is available\n", .{});
    }
}

test "level string conversion" {
    try testing.expectEqualStrings("DEBUG", zlog.Level.debug.toString());
    try testing.expectEqualStrings("INFO", zlog.Level.info.toString());
    try testing.expectEqualStrings("WARN", zlog.Level.warn.toString());
    try testing.expectEqualStrings("ERROR", zlog.Level.err.toString());
    try testing.expectEqualStrings("FATAL", zlog.Level.fatal.toString());
}

test "default logger functionality" {
    // Test global default logger functions
    zlog.info("Default logger test", .{});
    zlog.warn("Warning from default logger", .{});
    zlog.err("Error from default logger", .{});
}

test "buffer size configuration" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .buffer_size = 1024,
        .output_target = .stderr,
    });
    defer logger.deinit();

    try testing.expect(logger.buffer.capacity >= 1024);

    logger.info("Buffer size test message", .{});
}

test "concurrent logging safety" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test thread safety by logging from multiple simulated contexts
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        logger.info("Concurrent test message {d}", .{i});

        const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch unreachable;
        const fields = [_]zlog.Field{
            .{ .key = "thread_id", .value = .{ .uint = i } },
            .{ .key = "timestamp", .value = .{ .int = ts.sec } },
        };
        logger.logWithFields(.debug, "Concurrent structured message", &fields);
    }
}

test "large message handling" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test with a large message
    const large_message = "x" ** 1000;
    logger.info("Large message: {s}", .{large_message});

    // Test with many fields
    const many_fields = [_]zlog.Field{
        .{ .key = "field1", .value = .{ .string = "value1" } },
        .{ .key = "field2", .value = .{ .string = "value2" } },
        .{ .key = "field3", .value = .{ .string = "value3" } },
        .{ .key = "field4", .value = .{ .string = "value4" } },
        .{ .key = "field5", .value = .{ .string = "value5" } },
    };
    logger.logWithFields(.info, "Message with many fields", &many_fields);
}

test "empty and null field handling" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test with empty fields array
    const empty_fields = [_]zlog.Field{};
    logger.logWithFields(.info, "Message with no fields", &empty_fields);

    // Test with empty strings
    const empty_string_fields = [_]zlog.Field{
        .{ .key = "", .value = .{ .string = "" } },
        .{ .key = "empty_key", .value = .{ .string = "" } },
    };
    logger.logWithFields(.info, "Message with empty strings", &empty_string_fields);
}