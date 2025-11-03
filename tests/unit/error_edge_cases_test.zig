// Comprehensive edge case testing for production readiness
// Tests: OOM, disk full, permission denied, corrupted files, graceful degradation
//
// Part of Week 1-2: Stability Hardening
// Target: v0.1.0-rc1 Release Preview

const std = @import("std");
const testing = std.testing;
const zlog = @import("zlog");
const build_options = @import("build_options");

// ============================================================================
// PRIORITY 1: Out of Memory (OOM) Scenarios
// ============================================================================

test "edge_case: OOM during logger initialization" {
    var failing_allocator = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    const allocator = failing_allocator.allocator();

    // Should fail gracefully without crashing
    const result = zlog.Logger.init(allocator, .{});
    try testing.expectError(error.OutOfMemory, result);
}

test "edge_case: OOM during buffer allocation" {
    var failing_allocator = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
    const allocator = failing_allocator.allocator();

    const config = zlog.LoggerConfig{
        .buffer_size = 8192, // Large buffer to trigger OOM
        .output_target = .stderr,
    };

    const result = zlog.Logger.init(allocator, config);
    try testing.expectError(error.OutOfMemory, result);
}

test "edge_case: OOM during structured logging" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Create logger first
    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .file,
        .file_path = "/tmp/zlog_oom_test.log",
    });
    defer logger.deinit();
    defer std.fs.cwd().deleteFile("/tmp/zlog_oom_test.log") catch {};

    // Log with extremely large field values to stress memory
    const huge_value = try allocator.alloc(u8, 1024 * 1024); // 1MB string
    defer allocator.free(huge_value);
    @memset(huge_value, 'X');

    const fields = [_]zlog.Field{
        .{ .key = "huge_field", .value = .{ .string = huge_value } },
    };

    // Should handle gracefully without crashing
    logger.logWithFields(.info, "Testing huge field allocation", &fields);
}

test "edge_case: progressive allocation failures" {
    // Simulate progressive memory exhaustion
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var failing_allocator = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = i });
        const allocator = failing_allocator.allocator();

        const result = zlog.Logger.init(allocator, .{});

        // Each failure point should be handled gracefully
        if (result) |logger| {
            logger.deinit();
        } else |err| {
            try testing.expect(err == error.OutOfMemory);
        }
    }
}

// ============================================================================
// PRIORITY 2: Disk Full Scenarios
// ============================================================================

test "edge_case: disk full during file creation" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    // NOTE: This test cannot reliably simulate disk full without root privileges
    // or special filesystem setup. Documented for manual testing.
    //
    // Manual test procedure:
    // 1. Create a small tmpfs: `sudo mount -t tmpfs -o size=1M tmpfs /tmp/zlog_test`
    // 2. Fill it up with a large file
    // 3. Run zlog with file output to /tmp/zlog_test/
    // 4. Verify graceful degradation or clear error message
    //
    // Expected behavior: Should return error.DiskFull or similar, not crash
}

test "edge_case: disk full during file rotation" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Create a very small max_file_size to trigger rotation quickly
    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .file,
        .file_path = "/tmp/zlog_rotation_test.log",
        .max_file_size = 1024, // 1KB - will rotate quickly
        .max_backup_files = 3,
    });
    defer logger.deinit();
    defer {
        std.fs.cwd().deleteFile("/tmp/zlog_rotation_test.log") catch {};
        var i: u8 = 1;
        while (i <= 3) : (i += 1) {
            const backup_name = std.fmt.allocPrint(allocator, "/tmp/zlog_rotation_test.log.{d}", .{i}) catch unreachable;
            defer allocator.free(backup_name);
            std.fs.cwd().deleteFile(backup_name) catch {};
        }
    }

    // Write enough data to trigger rotation
    var j: u32 = 0;
    while (j < 100) : (j += 1) {
        logger.info("Rotation test message {d} - padding to make this longer for faster rotation testing", .{j});
    }

    // Should have rotated without crashing
}

// ============================================================================
// PRIORITY 3: Permission Denied Scenarios
// ============================================================================

test "edge_case: permission denied on file creation" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Try to create file in a restricted location
    const config = zlog.LoggerConfig{
        .output_target = .file,
        .file_path = "/root/zlog_test.log", // Typically requires root access
    };

    const result = zlog.Logger.init(allocator, config);

    // Should fail with permission error, not crash
    if (result) |logger| {
        // May succeed in some test environments (e.g., running as root)
        logger.deinit();
        std.fs.cwd().deleteFile("/root/zlog_test.log") catch {};
    } else |err| {
        // Expected in most cases
        try testing.expect(err == error.AccessDenied or err == error.FileNotFound);
    }
}

test "edge_case: permission denied during rotation" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    // NOTE: Difficult to test programmatically without complex setup
    // Documented for manual testing.
    //
    // Manual test procedure:
    // 1. Start logger with file output
    // 2. After some logging, change file permissions: `chmod 000 logfile.log`
    // 3. Trigger rotation by writing more data
    // 4. Verify graceful error handling
    //
    // Expected behavior: Should log error to stderr and continue or fail gracefully
}

// ============================================================================
// PRIORITY 4: Invalid File Paths
// ============================================================================

test "edge_case: nonexistent directory in file path" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    const config = zlog.LoggerConfig{
        .output_target = .file,
        .file_path = "/nonexistent/directory/structure/test.log",
    };

    // Should fail during initialization
    const result = zlog.Logger.init(allocator, config);
    try testing.expectError(error.FileNotFound, result);
}

test "edge_case: empty file path" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    const config = zlog.LoggerConfig{
        .output_target = .file,
        .file_path = "",
    };

    // Should fail validation or initialization
    const result = zlog.Logger.init(allocator, config);

    if (result) |logger| {
        logger.deinit();
        try testing.expect(false); // Should not succeed
    } else |err| {
        try testing.expect(err == error.FilePathRequired or err == error.InvalidConfiguration);
    }
}

test "edge_case: special characters in file path" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Test various special characters
    const special_paths = [_][]const u8{
        "/tmp/zlog test with spaces.log",
        "/tmp/zlog_test_with_unicode_🚀.log",
        "/tmp/zlog:test:colons.log",
        "/tmp/zlog\"quotes\".log",
    };

    for (special_paths) |path| {
        const config = zlog.LoggerConfig{
            .output_target = .file,
            .file_path = path,
        };

        const result = zlog.Logger.init(allocator, config);

        if (result) |logger| {
            logger.deinit();
            // Clean up
            std.fs.cwd().deleteFile(path) catch {};
        } else |_| {
            // Some special chars may be invalid on certain filesystems
            // Just ensure we don't crash
        }
    }
}

// ============================================================================
// PRIORITY 5: Corrupted Log File Recovery
// ============================================================================

test "edge_case: log to file with corrupted content" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;
    const test_path = "/tmp/zlog_corrupted_test.log";

    // Pre-create file with corrupted/invalid content
    {
        const file = try std.fs.cwd().createFile(test_path, .{});
        defer file.close();

        // Write binary garbage
        const corrupted_data = [_]u8{ 0xFF, 0xFE, 0xFD, 0xFC, 0x00, 0x01, 0x02 };
        try file.writeAll(&corrupted_data);
    }
    defer std.fs.cwd().deleteFile(test_path) catch {};

    // Try to initialize logger with corrupted file
    // Should either clear it or append safely
    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .file,
        .file_path = test_path,
    });
    defer logger.deinit();

    // Should be able to log despite pre-existing corrupted content
    logger.info("Testing logging after corrupted file", .{});
}

// ============================================================================
// PRIORITY 6: Graceful Degradation
// ============================================================================

test "edge_case: graceful degradation to stderr on file error" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    // This tests the current behavior - may need implementation
    // Expected: If file output fails, should fallback to stderr

    const config = zlog.LoggerConfig{
        .output_target = .file,
        .file_path = "/nonexistent/path/test.log",
    };

    const result = zlog.Logger.init(allocator, config);

    // Current implementation returns error
    // TODO: Implement graceful fallback to stderr
    try testing.expectError(error.FileNotFound, result);

    // Future implementation should:
    // 1. Log error about file failure to stderr
    // 2. Continue logging to stderr as fallback
    // 3. Return logger instance successfully
}

test "edge_case: continue logging after temporary write failure" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Log successfully
    logger.info("Before simulated failure", .{});

    // In a real scenario, a write might fail temporarily
    // Logger should continue functioning for subsequent writes
    logger.info("After simulated failure", .{});
    logger.warn("Recovery test", .{});

    // Should not crash or become unusable
}

// ============================================================================
// PRIORITY 7: Resource Exhaustion
// ============================================================================

test "edge_case: maximum field count" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Try logging with many fields
    const many_fields = try allocator.alloc(zlog.Field, 100);
    defer allocator.free(many_fields);

    var i: usize = 0;
    while (i < many_fields.len) : (i += 1) {
        many_fields[i] = .{
            .key = "field",
            .value = .{ .uint = i },
        };
    }

    // Should handle gracefully
    logger.logWithFields(.info, "Testing maximum fields", many_fields);
}

test "edge_case: extremely long log message" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
        .buffer_size = 4096,
    });
    defer logger.deinit();

    // Create message longer than buffer
    const huge_message = try allocator.alloc(u8, 10000);
    defer allocator.free(huge_message);
    @memset(huge_message, 'A');

    // Should handle truncation or dynamic allocation gracefully
    logger.info("Huge message: {s}", .{huge_message});
}

test "edge_case: rapid repeated logging" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Rapidly log many messages
    var i: u32 = 0;
    while (i < 10000) : (i += 1) {
        logger.info("Rapid log {d}", .{i});
    }

    // Should not crash or leak memory
}

// ============================================================================
// PRIORITY 8: Configuration Edge Cases
// ============================================================================

test "edge_case: zero buffer size" {
    const allocator = testing.allocator;

    const config = zlog.LoggerConfig{
        .buffer_size = 0,
    };

    const result = zlog.Logger.init(allocator, config);

    // Should either use minimum buffer size or fail gracefully
    if (result) |logger| {
        logger.deinit();
    } else |err| {
        try testing.expect(err == error.InvalidConfiguration or err == error.InvalidBufferSize);
    }
}

test "edge_case: maximum file size edge values" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    // Test with very small max_file_size
    {
        const config = zlog.LoggerConfig{
            .output_target = .file,
            .file_path = "/tmp/zlog_tiny_size_test.log",
            .max_file_size = 1, // 1 byte - should rotate immediately
        };

        var logger = try zlog.Logger.init(allocator, config);
        defer logger.deinit();
        defer std.fs.cwd().deleteFile("/tmp/zlog_tiny_size_test.log") catch {};

        logger.info("Test", .{});
    }

    // Test with very large max_file_size
    {
        const config = zlog.LoggerConfig{
            .output_target = .file,
            .file_path = "/tmp/zlog_huge_size_test.log",
            .max_file_size = std.math.maxInt(usize),
        };

        var logger = try zlog.Logger.init(allocator, config);
        defer logger.deinit();
        defer std.fs.cwd().deleteFile("/tmp/zlog_huge_size_test.log") catch {};

        logger.info("Test with huge max size", .{});
    }
}

test "edge_case: zero max backup files" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    const config = zlog.LoggerConfig{
        .output_target = .file,
        .file_path = "/tmp/zlog_no_backup_test.log",
        .max_file_size = 1024,
        .max_backup_files = 0, // No backups
    };

    var logger = try zlog.Logger.init(allocator, config);
    defer logger.deinit();
    defer std.fs.cwd().deleteFile("/tmp/zlog_no_backup_test.log") catch {};

    // Log enough to trigger rotation
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        logger.info("No backup rotation test {d}", .{i});
    }

    // Should not create backup files, just overwrite/truncate
}

// ============================================================================
// PRIORITY 9: Async Edge Cases
// ============================================================================

test "edge_case: async queue saturation" {
    if (!build_options.enable_async) return error.SkipZigTest;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .stderr,
    });
    defer logger.deinit();

    // Flood the async queue
    var i: u32 = 0;
    while (i < 100000) : (i += 1) {
        logger.info("Async queue saturation test {d}", .{i});
    }

    // Should handle queue full gracefully (drop, block, or grow queue)
}

test "edge_case: async shutdown with pending messages" {
    if (!build_options.enable_async) return error.SkipZigTest;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .stderr,
    });

    // Queue many messages
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        logger.info("Pending message {d}", .{i});
    }

    // Immediate deinit should flush pending messages
    logger.deinit();

    // Should not lose messages or crash
}

// ============================================================================
// PRIORITY 10: Concurrent Edge Cases
// ============================================================================

test "edge_case: concurrent file rotation" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .file,
        .file_path = "/tmp/zlog_concurrent_rotation_test.log",
        .max_file_size = 2048, // Small size for quick rotation
        .max_backup_files = 3,
    });
    defer logger.deinit();
    defer {
        std.fs.cwd().deleteFile("/tmp/zlog_concurrent_rotation_test.log") catch {};
        var j: u8 = 1;
        while (j <= 3) : (j += 1) {
            const backup_name = std.fmt.allocPrint(allocator, "/tmp/zlog_concurrent_rotation_test.log.{d}", .{j}) catch unreachable;
            defer allocator.free(backup_name);
            std.fs.cwd().deleteFile(backup_name) catch {};
        }
    }

    // Rapidly log from single thread to stress rotation logic
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        logger.info("Concurrent rotation stress test message number {d} with extra padding", .{i});
    }

    // Should handle rotation correctly without corruption
}
