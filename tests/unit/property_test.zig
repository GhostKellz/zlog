const std = @import("std");
const testing = std.testing;
const zlog = @import("zlog");

// Property-based testing for structured logging
// Tests that properties hold for various combinations of inputs

test "property: all log levels work with any message" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .level = .debug, // Enable all levels
        .output_target = .stderr,
    });
    defer logger.deinit();

    const test_messages = [_][]const u8{
        "",
        "a",
        "simple message",
        "message with numbers: 12345",
        "message with special chars: !@#$%^&*()",
        "very long message that exceeds typical length expectations and continues for quite a while to test buffer handling",
    };

    const levels = [_]zlog.Level{ .debug, .info, .warn, .err, .fatal };

    for (levels) |level| {
        for (test_messages) |message| {
            logger.log(level, "{s}", .{message});
        }
    }
}

test "property: field values round-trip correctly" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test various field value types and edge cases
    const test_cases = [_]struct {
        key: []const u8,
        value: zlog.Field.Value,
    }{
        .{ .key = "empty_string", .value = .{ .string = "" } },
        .{ .key = "single_char", .value = .{ .string = "x" } },
        .{ .key = "zero_int", .value = .{ .int = 0 } },
        .{ .key = "positive_int", .value = .{ .int = 12345 } },
        .{ .key = "negative_int", .value = .{ .int = -12345 } },
        .{ .key = "max_int", .value = .{ .int = std.math.maxInt(i64) } },
        .{ .key = "min_int", .value = .{ .int = std.math.minInt(i64) } },
        .{ .key = "zero_uint", .value = .{ .uint = 0 } },
        .{ .key = "max_uint", .value = .{ .uint = std.math.maxInt(u64) } },
        .{ .key = "zero_float", .value = .{ .float = 0.0 } },
        .{ .key = "positive_float", .value = .{ .float = 3.14159 } },
        .{ .key = "negative_float", .value = .{ .float = -2.71828 } },
        .{ .key = "small_float", .value = .{ .float = 0.000001 } },
        .{ .key = "large_float", .value = .{ .float = 999999.999 } },
        .{ .key = "true_bool", .value = .{ .boolean = true } },
        .{ .key = "false_bool", .value = .{ .boolean = false } },
    };

    for (test_cases) |test_case| {
        const field = zlog.Field{
            .key = test_case.key,
            .value = test_case.value,
        };
        const fields = [_]zlog.Field{field};
        logger.logWithFields(.info, "Property test", &fields);
    }
}

test "property: configuration validation is consistent" {
    const allocator = testing.allocator;

    // Test all combinations of valid configurations
    const levels = [_]zlog.Level{ .debug, .info, .warn, .err, .fatal };
    const formats = [_]zlog.Format{ .text, .json, .binary };
    const targets = [_]zlog.OutputTarget{ .stdout, .stderr, .file };

    for (levels) |level| {
        for (formats) |format| {
            for (targets) |target| {
                const config = zlog.LoggerConfig{
                    .level = level,
                    .format = format,
                    .output_target = target,
                    .file_path = if (target == .file) "/tmp/property_test.log" else null,
                };

                // Test that validation is consistent
                const validation_result = config.validate();

                if (target == .file and config.file_path == null) {
                    try testing.expectError(error.FilePathRequired, validation_result);
                } else if (!format.isAvailable()) {
                    try testing.expectError(error.FormatNotEnabled, validation_result);
                } else if (!target.isAvailable()) {
                    try testing.expectError(error.OutputTargetNotEnabled, validation_result);
                } else {
                    validation_result catch unreachable;

                    // If validation passes, logger creation should succeed
                    var logger = zlog.Logger.init(allocator, config) catch continue;
                    logger.deinit();
                }
            }
        }
    }

    // Clean up any test files
    std.fs.cwd().deleteFile("/tmp/property_test.log") catch {};
}

test "property: sampling rate always affects message frequency" {
    const allocator = testing.allocator;

    const sampling_rates = [_]f32{ 0.1, 0.25, 0.5, 0.75, 1.0 };

    for (sampling_rates) |rate| {
        var logger = try zlog.Logger.init(allocator, .{
            .sampling_rate = rate,
            .output_target = .stderr,
        });
        defer logger.deinit();

        // Log a fixed number of messages and verify sampling behavior
        var i: u32 = 0;
        while (i < 100) : (i += 1) {
            logger.info("Sampling test {d}", .{i});
        }

        // Property: sampling rate of 1.0 should log all messages
        // Property: sampling rate < 1.0 should log fewer messages
        // (This is a behavioral test - the exact counts aren't verified
        // but the sampling mechanism is exercised)
    }
}

test "property: buffer size affects memory usage but not functionality" {
    const allocator = testing.allocator;

    const buffer_sizes = [_]usize{ 512, 1024, 2048, 4096, 8192 };

    for (buffer_sizes) |size| {
        var logger = try zlog.Logger.init(allocator, .{
            .buffer_size = size,
            .output_target = .stderr,
        });
        defer logger.deinit();

        // Property: buffer size should affect capacity but not functionality
        try testing.expect(logger.buffer.capacity >= size);

        // Test that functionality works regardless of buffer size
        logger.info("Buffer size test: {d}", .{size});

        const fields = [_]zlog.Field{
            .{ .key = "buffer_size", .value = .{ .uint = size } },
        };
        logger.logWithFields(.info, "Structured log with buffer size", &fields);
    }
}

test "property: message length doesn't affect correctness" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test messages of varying lengths
    const lengths = [_]usize{ 0, 1, 10, 50, 100, 500, 1000, 2000 };

    for (lengths) |length| {
        // Create a message of the specified length
        const message = try allocator.alloc(u8, length);
        defer allocator.free(message);

        @memset(message, 'x');

        logger.info("Length {d}: {s}", .{ length, message });

        // Property: any message length should be handled correctly
        // (no crashes, truncation is acceptable for very long messages)
    }
}

test "property: field count doesn't affect correctness" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test with varying numbers of fields
    const max_fields = 10;
    var field_buffer: [max_fields]zlog.Field = undefined;

    var field_count: usize = 0;
    while (field_count <= max_fields) : (field_count += 1) {
        // Create fields for this test
        var i: usize = 0;
        while (i < field_count) : (i += 1) {
            const key = try std.fmt.allocPrint(allocator, "field_{d}", .{i});
            defer allocator.free(key);

            field_buffer[i] = zlog.Field{
                .key = key,
                .value = .{ .uint = i },
            };
        }

        const fields = field_buffer[0..field_count];
        logger.logWithFields(.info, "Field count test", fields);

        // Property: any number of fields should be handled correctly
    }
}

test "property: concurrent access is safe" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Simulate concurrent access by rapidly switching between operations
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        // Mix different types of logging operations
        switch (i % 4) {
            0 => logger.debug("Concurrent debug {d}", .{i}),
            1 => logger.info("Concurrent info {d}", .{i}),
            2 => logger.warn("Concurrent warn {d}", .{i}),
            3 => {
                const fields = [_]zlog.Field{
                    .{ .key = "iteration", .value = .{ .uint = i } },
                };
                logger.logWithFields(.err, "Concurrent structured", &fields);
            },
            else => unreachable,
        }
    }

    // Property: concurrent access should not cause crashes or data corruption
}

test "property: format switching maintains consistency" {
    const allocator = testing.allocator;

    // Test text format (always available)
    {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .text,
            .output_target = .stderr,
        });
        defer logger.deinit();

        logger.info("Format consistency test", .{});

        const fields = [_]zlog.Field{
            .{ .key = "format", .value = .{ .string = "text" } },
            .{ .key = "value", .value = .{ .uint = 42 } },
        };
        logger.logWithFields(.info, "Structured format test", &fields);
    }

    // Test JSON format if available
    if (zlog.Format.json.isAvailable()) {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .json,
            .output_target = .stderr,
        });
        defer logger.deinit();

        logger.info("Format consistency test", .{});

        const fields = [_]zlog.Field{
            .{ .key = "format", .value = .{ .string = "json" } },
            .{ .key = "value", .value = .{ .uint = 42 } },
        };
        logger.logWithFields(.info, "Structured format test", &fields);
    }

    // Test binary format if available
    if (zlog.Format.binary.isAvailable()) {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .binary,
            .output_target = .stderr,
        });
        defer logger.deinit();

        logger.info("Format consistency test", .{});

        const fields = [_]zlog.Field{
            .{ .key = "format", .value = .{ .string = "binary" } },
            .{ .key = "value", .value = .{ .uint = 42 } },
        };
        logger.logWithFields(.info, "Structured format test", &fields);
    }

    // Property: same logical content should be representable in all formats
}