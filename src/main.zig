const std = @import("std");
const zlog = @import("zlog");
const build_options = @import("build_options");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .level = .debug,
        .format = .text,
    });
    defer logger.deinit();

    logger.info("zlog logger initialized", .{});
    logger.debug("Debug level logging enabled", .{});

    const fields = [_]zlog.Field{
        .{ .key = "version", .value = .{ .string = "0.1.0" } },
        .{ .key = "pid", .value = .{ .uint = @intCast(std.os.linux.getpid()) } },
        .{ .key = "features", .value = .{ .uint = 4 } },
    };
    logger.logWithFields(.info, "Application started", &fields);

    logger.info("Processing request with id: {d}", .{42});
    logger.warn("High memory usage detected: {d}MB", .{512});

    if (build_options.enable_json) {
        var json_logger = try zlog.Logger.init(allocator, .{
            .level = .info,
            .format = .json,
        });
        defer json_logger.deinit();

        json_logger.info("JSON formatted log", .{});

        const json_fields = [_]zlog.Field{
            .{ .key = "request_id", .value = .{ .string = "abc-123" } },
            .{ .key = "status", .value = .{ .uint = 200 } },
            .{ .key = "latency_ms", .value = .{ .float = 15.7 } },
            .{ .key = "cached", .value = .{ .boolean = false } },
        };
        json_logger.logWithFields(.info, "Request completed", &json_fields);
    } else {
        logger.info("JSON format disabled in this build", .{});
    }

    zlog.info("Using default logger", .{});
    zlog.warn("This is a warning from default logger", .{});

    // Test file output
    if (build_options.enable_file_targets) {
        std.debug.print("\nTesting file output:\n", .{});
        var file_logger = try zlog.Logger.init(allocator, .{
            .level = .info,
            .format = .text,
            .output_target = .file,
            .file_path = "test.log",
            .max_file_size = 1024, // Small size for testing rotation
        });
        defer file_logger.deinit();

        file_logger.info("This goes to file", .{});
        file_logger.warn("File logging test", .{});
    }

    // Test binary format
    if (build_options.enable_binary_format) {
        std.debug.print("\nTesting binary format (output will be binary):\n", .{});
        var binary_logger = try zlog.Logger.init(allocator, .{
            .level = .info,
            .format = .binary,
        });
        defer binary_logger.deinit();

        const binary_fields = [_]zlog.Field{
            .{ .key = "binary", .value = .{ .boolean = true } },
            .{ .key = "size", .value = .{ .uint = 42 } },
        };
        binary_logger.logWithFields(.info, "Binary format test", &binary_fields);
    }

    var sampled_logger = try zlog.Logger.init(allocator, .{
        .level = .debug,
        .format = .text,
        .sampling_rate = 0.3,
    });
    defer sampled_logger.deinit();

    std.debug.print("\nSampled logging (30% rate):\n", .{});
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        sampled_logger.info("Sampled message #{d}", .{i});
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}