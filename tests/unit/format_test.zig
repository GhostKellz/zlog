const std = @import("std");
const testing = std.testing;
const zlog = @import("zlog");
const build_options = @import("build_options");

// Helper function for getting Unix timestamp (Zig 0.16+ compatibility)
inline fn getUnixTimestamp() i64 {
    const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch unreachable;
    return ts.sec;
}

test "text format basic functionality" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
        .output_target = .stderr,
    });
    defer logger.deinit();

    logger.info("Text format test message", .{});

    const fields = [_]zlog.Field{
        .{ .key = "user", .value = .{ .string = "test_user" } },
        .{ .key = "count", .value = .{ .uint = 42 } },
    };
    logger.logWithFields(.warn, "Text format with fields", &fields);
}

test "json format functionality" {
    if (!build_options.enable_json) return;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .format = .json,
        .output_target = .stderr,
    });
    defer logger.deinit();

    logger.info("JSON format test message", .{});

    const fields = [_]zlog.Field{
        .{ .key = "request_id", .value = .{ .string = "abc-123" } },
        .{ .key = "status_code", .value = .{ .uint = 200 } },
        .{ .key = "latency", .value = .{ .float = 15.7 } },
        .{ .key = "success", .value = .{ .boolean = true } },
    };
    logger.logWithFields(.info, "JSON format with all field types", &fields);
}

test "binary format functionality" {
    if (!build_options.enable_binary_format) return;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .format = .binary,
        .output_target = .stderr,
    });
    defer logger.deinit();

    logger.info("Binary format test message", .{});

    const fields = [_]zlog.Field{
        .{ .key = "binary_field", .value = .{ .boolean = true } },
        .{ .key = "size", .value = .{ .uint = 1024 } },
        .{ .key = "ratio", .value = .{ .float = 0.75 } },
    };
    logger.logWithFields(.warn, "Binary format with fields", &fields);
}

test "format fallback behavior" {
    const allocator = testing.allocator;

    // Test that requesting disabled formats falls back gracefully
    if (!build_options.enable_json) {
        // When JSON is disabled, should fall back to text
        var logger = try zlog.Logger.init(allocator, .{
            .format = .json,
            .output_target = .stderr,
        });
        defer logger.deinit();

        logger.info("This should use text format fallback", .{});
    }

    if (!build_options.enable_binary_format) {
        // When binary is disabled, should fall back to text
        var logger = try zlog.Logger.init(allocator, .{
            .format = .binary,
            .output_target = .stderr,
        });
        defer logger.deinit();

        logger.info("This should use text format fallback", .{});
    }
}

test "field value type serialization" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test edge cases for different value types
    const edge_case_fields = [_]zlog.Field{
        .{ .key = "zero_int", .value = .{ .int = 0 } },
        .{ .key = "negative_int", .value = .{ .int = -2147483648 } },
        .{ .key = "max_uint", .value = .{ .uint = std.math.maxInt(u64) } },
        .{ .key = "small_float", .value = .{ .float = 0.000001 } },
        .{ .key = "large_float", .value = .{ .float = 999999.999999 } },
        .{ .key = "false_bool", .value = .{ .boolean = false } },
        .{ .key = "true_bool", .value = .{ .boolean = true } },
    };

    logger.logWithFields(.info, "Edge case field values", &edge_case_fields);
}

test "special character handling in fields" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
        .output_target = .stderr,
    });
    defer logger.deinit();

    const special_char_fields = [_]zlog.Field{
        .{ .key = "quotes", .value = .{ .string = "string with \"quotes\"" } },
        .{ .key = "newlines", .value = .{ .string = "string\nwith\nnewlines" } },
        .{ .key = "unicode", .value = .{ .string = "unicode: 🚀✨🔥" } },
        .{ .key = "backslashes", .value = .{ .string = "path\\to\\file" } },
    };

    logger.logWithFields(.info, "Special characters test", &special_char_fields);

    // Test with JSON format if available
    if (build_options.enable_json) {
        var json_logger = try zlog.Logger.init(allocator, .{
            .format = .json,
            .output_target = .stderr,
        });
        defer json_logger.deinit();

        json_logger.logWithFields(.info, "JSON special characters", &special_char_fields);
    }
}

test "format performance comparison" {
    const allocator = testing.allocator;
    const iterations = 1000;

    // Text format timing
    {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .text,
            .output_target = .stderr,
        });
        defer logger.deinit();

        var timer = std.time.Timer.start() catch unreachable;
        var i: u32 = 0;
        while (i < iterations) : (i += 1) {
            logger.info("Performance test message {d}", .{i});
        }
        const text_duration = timer.read();
        std.debug.print("Text format: {d} messages in {d}ns\n", .{ iterations, text_duration });
    }

    // JSON format timing (if available)
    if (build_options.enable_json) {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .json,
            .output_target = .stderr,
        });
        defer logger.deinit();

        var timer = std.time.Timer.start() catch unreachable;
        var i: u32 = 0;
        while (i < iterations) : (i += 1) {
            logger.info("Performance test message {d}", .{i});
        }
        const json_duration = timer.read();
        std.debug.print("JSON format: {d} messages in {d}ns\n", .{ iterations, json_duration });
    }

    // Binary format timing (if available)
    if (build_options.enable_binary_format) {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .binary,
            .output_target = .stderr,
        });
        defer logger.deinit();

        var timer = std.time.Timer.start() catch unreachable;
        var i: u32 = 0;
        while (i < iterations) : (i += 1) {
            logger.info("Performance test message {d}", .{i});
        }
        const binary_duration = timer.read();
        std.debug.print("Binary format: {d} messages in {d}ns\n", .{ iterations, binary_duration });
    }
}

test "format with very long keys and values" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test with very long field key and value
    const long_key = "very_long_field_key_that_exceeds_normal_length_expectations";
    const long_value = "very_long_field_value_that_also_exceeds_normal_length_expectations_and_continues_for_quite_a_while";

    const long_fields = [_]zlog.Field{
        .{ .key = long_key, .value = .{ .string = long_value } },
    };

    logger.logWithFields(.info, "Test with long field names and values", &long_fields);
}

test "format with empty message" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test with empty message
    logger.logWithFields(.info, "", &[_]zlog.Field{});

    // Test with only fields, no message content
    const fields_only = [_]zlog.Field{
        .{ .key = "only_field", .value = .{ .string = "only_value" } },
    };
    logger.logWithFields(.warn, "", &fields_only);
}