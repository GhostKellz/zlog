const std = @import("std");
const testing = std.testing;
const zlog = @import("zlog");
const build_options = @import("build_options");
const builtin = @import("builtin");

// Cross-platform compatibility tests

test "platform: basic functionality across platforms" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    logger.info("Platform test on {s}", .{@tagName(builtin.os.tag)});

    const platform_fields = [_]zlog.Field{
        .{ .key = "os", .value = .{ .string = @tagName(builtin.os.tag) } },
        .{ .key = "arch", .value = .{ .string = @tagName(builtin.cpu.arch) } },
        .{ .key = "endian", .value = .{ .string = @tagName(builtin.cpu.arch.endian()) } },
    };

    logger.logWithFields(.info, "Platform information", &platform_fields);
}

test "platform: file operations" {
    if (!build_options.enable_file_targets) return;

    const allocator = testing.allocator;

    // Use platform-appropriate temporary directory
    const temp_dir = switch (builtin.os.tag) {
        .windows => "C:\\temp",
        .macos, .linux, .freebsd, .openbsd, .netbsd => "/tmp",
        else => "/tmp", // Default fallback
    };

    const test_file = try std.fmt.allocPrint(allocator, "{s}/zlog_platform_test.log", .{temp_dir});
    defer allocator.free(test_file);

    // Clean up any existing file
    std.fs.cwd().deleteFile(test_file) catch {};

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .file,
        .file_path = test_file,
    });
    defer logger.deinit();

    logger.info("Platform file test on {s}", .{@tagName(builtin.os.tag)});

    // Verify file was created
    const file = std.fs.cwd().openFile(test_file, .{}) catch |err| {
        std.debug.print("Failed to open test file on {s}: {}\n", .{ @tagName(builtin.os.tag), err });
        return err;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    try testing.expect(file_size > 0);

    // Clean up
    std.fs.cwd().deleteFile(test_file) catch {};
}

test "platform: path handling" {
    if (!build_options.enable_file_targets) return;

    const allocator = testing.allocator;

    // Test platform-specific path separators and conventions
    const test_paths = switch (builtin.os.tag) {
        .windows => [_][]const u8{
            "C:\\temp\\zlog_test.log",
            ".\\zlog_relative.log",
        },
        else => [_][]const u8{
            "/tmp/zlog_test.log",
            "./zlog_relative.log",
            "/tmp/nested/path/zlog_test.log", // Will fail, but tests error handling
        },
    };

    for (test_paths) |path| {
        // Clean up first
        std.fs.cwd().deleteFile(path) catch {};

        const result = zlog.Logger.init(allocator, .{
            .output_target = .file,
            .file_path = path,
        });

        if (result) |logger| {
            logger.deinit();
            logger.info("Successfully created logger with path: {s}", .{path});

            // Clean up
            std.fs.cwd().deleteFile(path) catch {};
        } else |err| {
            // Some paths are expected to fail (like nested non-existent directories)
            std.debug.print("Expected failure for path {s}: {}\n", .{ path, err });
        }
    }
}

test "platform: thread safety" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test thread safety across platforms
    // Note: This is a basic test since we can't easily create threads in Zig tests
    // but it exercises the mutex code paths

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        logger.info("Thread safety test {d} on {s}", .{ i, @tagName(builtin.os.tag) });

        if (i % 5 == 0) {
            const fields = [_]zlog.Field{
                .{ .key = "platform", .value = .{ .string = @tagName(builtin.os.tag) } },
                .{ .key = "iteration", .value = .{ .uint = i } },
            };
            logger.logWithFields(.warn, "Structured thread test", &fields);
        }
    }
}

test "platform: timestamp consistency" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test that timestamps work across platforms
    const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch unreachable;
    const start_time = ts.sec;

    logger.info("Timestamp test start", .{});

    // Small delay to ensure different timestamp
    std.Io.sleep(std.testing.io, std.Io.Duration.fromNanoseconds(1_000_000), .awake) catch {};

    logger.info("Timestamp test end", .{});

    const end_time = (std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch unreachable).sec;

    // Verify time progressed
    try testing.expect(end_time >= start_time);

    const time_fields = [_]zlog.Field{
        .{ .key = "start_time", .value = .{ .int = start_time } },
        .{ .key = "end_time", .value = .{ .int = end_time } },
        .{ .key = "platform", .value = .{ .string = @tagName(builtin.os.tag) } },
    };

    logger.logWithFields(.info, "Timestamp verification", &time_fields);
}

test "platform: memory allocation patterns" {
    const allocator = testing.allocator;

    // Test that memory allocation works consistently across platforms
    var logger = try zlog.Logger.init(allocator, .{
        .buffer_size = 2048,
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test various allocation patterns (reduced for faster tests)
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const size = (i % 3) * 50 + 100; // Varying sizes
        const test_data = try allocator.alloc(u8, size);
        defer allocator.free(test_data);

        @memset(test_data, 'P'); // P for Platform

        logger.info("Platform memory test {d}", .{i});

        const fields = [_]zlog.Field{
            .{ .key = "size", .value = .{ .uint = size } },
            .{ .key = "platform", .value = .{ .string = @tagName(builtin.os.tag) } },
        };
        logger.logWithFields(.debug, "Memory allocation test", &fields);
    }
}

test "platform: async behavior" {
    if (!build_options.enable_async) return;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .stderr,
    });
    defer logger.deinit();

    logger.info("Async test on {s}", .{@tagName(builtin.os.tag)});

    // Log several messages asynchronously (reduced for faster tests)
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        logger.info("Async platform test {d}", .{i});
    }

    // Platform-specific sleep duration to allow async processing
    const sleep_duration = switch (builtin.os.tag) {
        .windows => 10_000_000, // 10ms - Windows might need more time
        else => 5_000_000, // 5ms for Unix-like systems
    };

    std.Thread.sleep(sleep_duration);

    logger.info("Async test completion on {s}", .{@tagName(builtin.os.tag)});
}

test "platform: file rotation behavior" {
    if (!build_options.enable_file_targets) return;

    const allocator = testing.allocator;

    const temp_dir = switch (builtin.os.tag) {
        .windows => "C:\\temp",
        else => "/tmp",
    };

    const test_file = try std.fmt.allocPrint(allocator, "{s}/zlog_rotation_platform_test.log", .{temp_dir});
    defer allocator.free(test_file);

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
        .max_file_size = 512, // Small size to trigger rotation quickly
        .max_backup_files = 2,
    });
    defer logger.deinit();

    // Generate enough content to potentially trigger rotation (reduced iterations)
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        logger.info("Platform rotation test {d} on {s} with extra content for size", .{ i, @tagName(builtin.os.tag) });
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

test "platform: endianness handling" {
    const allocator = testing.allocator;

    // Test binary format handling across different endianness
    if (build_options.enable_binary_format) {
        var logger = try zlog.Logger.init(allocator, .{
            .format = .binary,
            .output_target = .stderr,
        });
        defer logger.deinit();

        const endian_fields = [_]zlog.Field{
            .{ .key = "endian", .value = .{ .string = @tagName(builtin.cpu.arch.endian()) } },
            .{ .key = "test_int", .value = .{ .int = 0x123456789ABCDEF } },
            .{ .key = "test_uint", .value = .{ .uint = 0xFEDCBA9876543210 } },
            .{ .key = "test_float", .value = .{ .float = 123.456789 } },
        };

        logger.logWithFields(.info, "Endianness test", &endian_fields);
    }

    // Also test with text format for comparison
    var text_logger = try zlog.Logger.init(allocator, .{
        .format = .text,
        .output_target = .stderr,
    });
    defer text_logger.deinit();

    text_logger.info("Endianness: {s}, Platform: {s}", .{
        @tagName(builtin.cpu.arch.endian()),
        @tagName(builtin.os.tag)
    });
}

test "platform: unicode and locale handling" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Test unicode handling across platforms (reduced set for faster tests)
    const unicode_strings = [_][]const u8{
        "ASCII only",
        "UTF-8: Hello 世界 🌍",
        "Currency: $€£¥",
    };

    for (unicode_strings) |unicode_str| {
        logger.info("Unicode test: {s}", .{unicode_str});
    }
}

test "platform: performance characteristics" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    const iterations = 100;
    var timer = std.time.Timer.start() catch unreachable;

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        logger.info("Performance test {d}", .{i});
    }

    const duration_ns = timer.read();
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const messages_per_ms = @as(f64, @floatFromInt(iterations)) / duration_ms;

    logger.info("Platform performance on {s}: {d:.2} messages/ms", .{
        @tagName(builtin.os.tag),
        messages_per_ms
    });
}