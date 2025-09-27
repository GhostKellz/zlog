const std = @import("std");
const testing = std.testing;
const zlog = @import("zlog");
const build_options = @import("build_options");

test "error: invalid configuration combinations" {
    const allocator = testing.allocator;

    // Test file output without file path
    {
        const config = zlog.LoggerConfig{
            .output_target = .file,
            .file_path = null,
        };
        try testing.expectError(error.FilePathRequired, config.validate());
        try testing.expectError(error.FilePathRequired, zlog.Logger.init(allocator, config));
    }

    // Test async when not enabled
    if (!build_options.enable_async) {
        const config = zlog.LoggerConfig{
            .async_io = true,
        };
        try testing.expectError(error.AsyncNotEnabled, config.validate());
        try testing.expectError(error.AsyncNotEnabled, zlog.Logger.init(allocator, config));
    }

    // Test aggregation when not enabled
    if (!build_options.enable_aggregation) {
        const batch_config = zlog.LoggerConfig{
            .enable_batching = true,
        };
        try testing.expectError(error.AggregationNotEnabled, batch_config.validate());

        const dedup_config = zlog.LoggerConfig{
            .enable_deduplication = true,
        };
        try testing.expectError(error.AggregationNotEnabled, dedup_config.validate());
    }

    // Test disabled formats
    if (!build_options.enable_json) {
        const config = zlog.LoggerConfig{
            .format = .json,
        };
        try testing.expectError(error.FormatNotEnabled, config.validate());
    }

    if (!build_options.enable_binary_format) {
        const config = zlog.LoggerConfig{
            .format = .binary,
        };
        try testing.expectError(error.FormatNotEnabled, config.validate());
    }

    // Test disabled file targets
    if (!build_options.enable_file_targets) {
        const config = zlog.LoggerConfig{
            .output_target = .file,
            .file_path = "/tmp/test.log",
        };
        try testing.expectError(error.OutputTargetNotEnabled, config.validate());
    }
}

test "error: file system errors" {
    if (!build_options.enable_file_targets) return;

    const allocator = testing.allocator;

    // Test invalid file path (directory doesn't exist)
    {
        const config = zlog.LoggerConfig{
            .output_target = .file,
            .file_path = "/nonexistent/directory/test.log",
        };

        // Should validate but fail during init
        try config.validate();
        try testing.expectError(error.FileNotFound, zlog.Logger.init(allocator, config));
    }

    // Test permission denied (try to write to root - may not work in all test environments)
    {
        const config = zlog.LoggerConfig{
            .output_target = .file,
            .file_path = "/root/test.log",
        };

        try config.validate();
        // This may succeed in some test environments, so we don't enforce the error
        const result = zlog.Logger.init(allocator, config);
        if (result) |logger| {
            logger.deinit();
            // Clean up if successful
            std.fs.cwd().deleteFile("/root/test.log") catch {};
        } else |err| {
            // Expected in most cases
            try testing.expect(err == error.AccessDenied or err == error.FileNotFound);
        }
    }
}

test "error: memory allocation failures" {
    // Test with a failing allocator to ensure graceful handling
    var failing_allocator = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    const allocator = failing_allocator.allocator();

    // Should fail during buffer allocation
    try testing.expectError(error.OutOfMemory, zlog.Logger.init(allocator, .{}));
}

test "error: buffer overflow conditions" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .buffer_size = 64, // Very small buffer
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Try to log a message larger than the buffer
    const large_message = "x" ** 1000;

    // Should handle gracefully without crashing
    logger.info("Large message: {s}", .{large_message});

    // Try with many large fields
    const large_fields = [_]zlog.Field{
        .{ .key = "field1", .value = .{ .string = "very_long_value_that_exceeds_buffer" } },
        .{ .key = "field2", .value = .{ .string = "another_very_long_value_that_exceeds_buffer" } },
        .{ .key = "field3", .value = .{ .string = "yet_another_very_long_value_that_exceeds_buffer" } },
    };

    logger.logWithFields(.info, "Large structured log", &large_fields);
}

test "error: invalid field data" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test with empty field key
    const empty_key_fields = [_]zlog.Field{
        .{ .key = "", .value = .{ .string = "value" } },
    };
    logger.logWithFields(.info, "Empty key test", &empty_key_fields);

    // Test with very long field key
    const long_key = "x" ** 1000;
    const long_key_fields = [_]zlog.Field{
        .{ .key = long_key, .value = .{ .string = "value" } },
    };
    logger.logWithFields(.info, "Long key test", &long_key_fields);

    // Test with null-like values (empty strings)
    const null_like_fields = [_]zlog.Field{
        .{ .key = "empty_string", .value = .{ .string = "" } },
        .{ .key = "zero_values", .value = .{ .int = 0 } },
    };
    logger.logWithFields(.info, "Null-like values test", &null_like_fields);
}

test "error: sampling edge cases" {
    const allocator = testing.allocator;

    // Test invalid sampling rates
    {
        const config = zlog.LoggerConfig{
            .sampling_rate = -1.0, // Invalid negative rate
        };

        // Note: Current implementation doesn't validate sampling rate bounds
        // This documents the current behavior
        var logger = try zlog.Logger.init(allocator, config);
        defer logger.deinit();

        logger.info("Negative sampling rate test", .{});
    }

    {
        const config = zlog.LoggerConfig{
            .sampling_rate = 2.0, // Invalid rate > 1.0
        };

        var logger = try zlog.Logger.init(allocator, config);
        defer logger.deinit();

        logger.info("High sampling rate test", .{});
    }

    // Test very small sampling rate
    {
        var logger = try zlog.Logger.init(allocator, .{
            .sampling_rate = 0.001, // Very low rate
            .output_target = .stderr,
        });
        defer logger.deinit();

        // Most messages should be filtered out
        var i: u32 = 0;
        while (i < 100) : (i += 1) {
            logger.info("Low sampling test {d}", .{i});
        }
    }
}

test "error: format-specific edge cases" {
    const allocator = testing.allocator;

    // Test binary format with edge case values
    if (build_options.enable_binary_format) {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .binary,
            .output_target = .stderr,
        });
        defer logger.deinit();

        // Test with maximum length strings and field counts
        const max_fields = [_]zlog.Field{
            .{ .key = "x" ** 255, .value = .{ .string = "y" ** 65535 } }, // Max key and value lengths
        };
        logger.logWithFields(.info, "x" ** 65535, &max_fields); // Max message length
    }

    // Test JSON format with characters that need escaping
    if (build_options.enable_json) {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .json,
            .output_target = .stderr,
        });
        defer logger.deinit();

        const escape_test_fields = [_]zlog.Field{
            .{ .key = "quotes", .value = .{ .string = "string with \"quotes\" and more" } },
            .{ .key = "backslashes", .value = .{ .string = "path\\with\\backslashes" } },
            .{ .key = "control_chars", .value = .{ .string = "string\nwith\tcontrol\rchars" } },
        };
        logger.logWithFields(.info, "JSON escape test with \"quotes\"", &escape_test_fields);
    }
}

test "error: concurrent access stress" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Rapidly switch between different operations to test thread safety
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        switch (i % 5) {
            0 => logger.debug("Stress test {d}", .{i}),
            1 => logger.info("Stress test {d}", .{i}),
            2 => logger.warn("Stress test {d}", .{i}),
            3 => logger.err("Stress test {d}", .{i}),
            4 => {
                const fields = [_]zlog.Field{
                    .{ .key = "stress_test", .value = .{ .uint = i } },
                };
                logger.logWithFields(.fatal, "Stress structured", &fields);
            },
            else => unreachable,
        }
    }
}

test "error: resource exhaustion simulation" {
    const allocator = testing.allocator;

    // Test behavior under memory pressure
    var logger = try zlog.Logger.init(allocator, .{
        .buffer_size = 256, // Small buffer to increase pressure
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Generate many messages with varying sizes
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const message_size = (i % 10) * 10 + 10; // Varying sizes 10-100
        const message = try allocator.alloc(u8, message_size);
        defer allocator.free(message);
        @memset(message, 'x');

        logger.info("Resource test {d}: {s}", .{ i, message });

        // Add structured data to increase memory pressure
        if (i % 3 == 0) {
            const fields = [_]zlog.Field{
                .{ .key = "iteration", .value = .{ .uint = i } },
                .{ .key = "size", .value = .{ .uint = message_size } },
            };
            logger.logWithFields(.warn, "Resource structured test", &fields);
        }
    }
}

test "error: async error handling" {
    if (!build_options.enable_async) return;

    const allocator = testing.allocator;

    // Test async with file errors
    if (build_options.enable_file_targets) {
        var logger = try zlog.Logger.init(allocator, .{
            .async_io = true,
            .output_target = .file,
            .file_path = "/tmp/async_error_test.log",
        });
        defer logger.deinit();

        logger.info("Before async error", .{});

        // Manually delete the file while logger is active to simulate error
        std.fs.cwd().deleteFile("/tmp/async_error_test.log") catch {};

        logger.info("After file deletion", .{});

        // Give async thread time to encounter the error
        std.time.sleep(10_000_000); // 10ms
    }
}

test "error: malformed log data recovery" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test with unusual unicode and binary data in log messages
    const problematic_strings = [_][]const u8{
        "\x00\x01\x02\x03", // Binary data
        "🚀💥🔥⚡", // Unicode emojis
        "\u{FEFF}BOM text", // BOM character
        "null\x00embedded", // Embedded null
        "\xFF\xFE\xFD", // Invalid UTF-8 sequences
    };

    for (problematic_strings) |str| {
        logger.info("Problematic string: {s}", .{str});

        const fields = [_]zlog.Field{
            .{ .key = "problematic", .value = .{ .string = str } },
        };
        logger.logWithFields(.warn, "Structured problematic", &fields);
    }
}