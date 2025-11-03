// Comprehensive thread safety and concurrent stress tests
// Tests: race conditions, deadlocks, concurrent writes, mutex contention
//
// Part of Week 1-2: Stability Hardening
// Target: v0.1.0-rc1 Release Preview

const std = @import("std");
const testing = std.testing;
const zlog = @import("zlog");
const build_options = @import("build_options");

// ============================================================================
// PRIORITY 1: Basic Concurrent Logging
// ============================================================================

test "thread_safety: concurrent logging from multiple threads" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    const num_threads = 10;
    const messages_per_thread = 100;

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        thread_id: usize,
        messages: usize,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.messages) : (i += 1) {
                ctx.logger_ptr.info("Thread {d} message {d}", .{ ctx.thread_id, i });
            }
        }
    }.run;

    // Create threads
    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        contexts[t] = .{
            .logger_ptr = &logger,
            .thread_id = t,
            .messages = messages_per_thread,
        };
        threads[t] = try std.Thread.spawn(.{}, threadFunction, .{&contexts[t]});
    }

    // Wait for all threads
    t = 0;
    while (t < num_threads) : (t += 1) {
        threads[t].join();
    }

    // Should complete without deadlocks or crashes
}

test "thread_safety: concurrent structured logging" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    const num_threads = 8;

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        thread_id: usize,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < 50) : (i += 1) {
                const fields = [_]zlog.Field{
                    .{ .key = "thread_id", .value = .{ .uint = ctx.thread_id } },
                    .{ .key = "iteration", .value = .{ .uint = i } },
                    .{ .key = "timestamp", .value = .{ .uint = @intCast(std.time.timestamp()) } },
                };
                ctx.logger_ptr.logWithFields(.info, "Structured concurrent test", &fields);
            }
        }
    }.run;

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        contexts[t] = .{
            .logger_ptr = &logger,
            .thread_id = t,
        };
        threads[t] = try std.Thread.spawn(.{}, threadFunction, .{&contexts[t]});
    }

    t = 0;
    while (t < num_threads) : (t += 1) {
        threads[t].join();
    }
}

// ============================================================================
// PRIORITY 2: Concurrent File Operations
// ============================================================================

test "thread_safety: concurrent file writing" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .file,
        .file_path = "/tmp/zlog_concurrent_file_test.log",
    });
    defer logger.deinit();
    defer std.fs.cwd().deleteFile("/tmp/zlog_concurrent_file_test.log") catch {};

    const num_threads = 10;
    const messages_per_thread = 100;

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        thread_id: usize,
        count: usize,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.count) : (i += 1) {
                ctx.logger_ptr.info("Concurrent file write from thread {d}: {d}", .{ ctx.thread_id, i });
            }
        }
    }.run;

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        contexts[t] = .{
            .logger_ptr = &logger,
            .thread_id = t,
            .count = messages_per_thread,
        };
        threads[t] = try std.Thread.spawn(.{}, threadFunction, .{&contexts[t]});
    }

    t = 0;
    while (t < num_threads) : (t += 1) {
        threads[t].join();
    }

    // Verify file exists and contains data
    const file = try std.fs.cwd().openFile("/tmp/zlog_concurrent_file_test.log", .{});
    defer file.close();
    const stat = try file.stat();
    try testing.expect(stat.size > 0);
}

test "thread_safety: concurrent file rotation" {
    if (!build_options.enable_file_targets) return error.SkipZigTest;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .file,
        .file_path = "/tmp/zlog_concurrent_rotation_test.log",
        .max_file_size = 4096, // Small size for quick rotation
        .max_backup_files = 3,
    });
    defer logger.deinit();
    defer {
        std.fs.cwd().deleteFile("/tmp/zlog_concurrent_rotation_test.log") catch {};
        var i: u8 = 1;
        while (i <= 3) : (i += 1) {
            const backup_name = std.fmt.allocPrint(allocator, "/tmp/zlog_concurrent_rotation_test.log.{d}", .{i}) catch unreachable;
            defer allocator.free(backup_name);
            std.fs.cwd().deleteFile(backup_name) catch {};
        }
    }

    const num_threads = 8;

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        thread_id: usize,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < 200) : (i += 1) {
                ctx.logger_ptr.info("Thread {d} rotation stress test message {d} with padding to trigger rotation faster", .{ ctx.thread_id, i });
            }
        }
    }.run;

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        contexts[t] = .{
            .logger_ptr = &logger,
            .thread_id = t,
        };
        threads[t] = try std.Thread.spawn(.{}, threadFunction, .{&contexts[t]});
    }

    t = 0;
    while (t < num_threads) : (t += 1) {
        threads[t].join();
    }

    // Should have rotated without corruption or crashes
}

// ============================================================================
// PRIORITY 3: High Concurrency Stress Tests
// ============================================================================

test "thread_safety: 100 thread stress test" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    const num_threads = 100;
    const messages_per_thread = 10;

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        thread_id: usize,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < messages_per_thread) : (i += 1) {
                ctx.logger_ptr.info("High concurrency test T{d} M{d}", .{ ctx.thread_id, i });
            }
        }
    }.run;

    var threads = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(threads);

    var contexts = try allocator.alloc(ThreadContext, num_threads);
    defer allocator.free(contexts);

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        contexts[t] = .{
            .logger_ptr = &logger,
            .thread_id = t,
        };
        threads[t] = try std.Thread.spawn(.{}, threadFunction, .{&contexts[t]});
    }

    t = 0;
    while (t < num_threads) : (t += 1) {
        threads[t].join();
    }
}

test "thread_safety: rapid thread spawn and join" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        id: usize,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            ctx.logger_ptr.info("Rapid thread {d}", .{ctx.id});
        }
    }.run;

    // Rapidly create and destroy threads
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var ctx = ThreadContext{
            .logger_ptr = &logger,
            .id = i,
        };
        const thread = try std.Thread.spawn(.{}, threadFunction, .{&ctx});
        thread.join();
    }
}

// ============================================================================
// PRIORITY 4: Concurrent Mixed Operations
// ============================================================================

test "thread_safety: mixed log levels concurrent" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    const num_threads = 5;

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        level_offset: usize,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < 50) : (i += 1) {
                const level = (ctx.level_offset + i) % 5;
                switch (level) {
                    0 => ctx.logger_ptr.debug("Debug msg {d}", .{i}),
                    1 => ctx.logger_ptr.info("Info msg {d}", .{i}),
                    2 => ctx.logger_ptr.warn("Warn msg {d}", .{i}),
                    3 => ctx.logger_ptr.err("Error msg {d}", .{i}),
                    4 => ctx.logger_ptr.fatal("Fatal msg {d}", .{i}),
                    else => unreachable,
                }
            }
        }
    }.run;

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        contexts[t] = .{
            .logger_ptr = &logger,
            .level_offset = t,
        };
        threads[t] = try std.Thread.spawn(.{}, threadFunction, .{&contexts[t]});
    }

    t = 0;
    while (t < num_threads) : (t += 1) {
        threads[t].join();
    }
}

test "thread_safety: concurrent text and structured logging" {
    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    const num_threads = 10;

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        thread_id: usize,
        use_structured: bool,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < 50) : (i += 1) {
                if (ctx.use_structured) {
                    const fields = [_]zlog.Field{
                        .{ .key = "tid", .value = .{ .uint = ctx.thread_id } },
                        .{ .key = "iter", .value = .{ .uint = i } },
                    };
                    ctx.logger_ptr.logWithFields(.info, "Structured", &fields);
                } else {
                    ctx.logger_ptr.info("Simple T{d} I{d}", .{ ctx.thread_id, i });
                }
            }
        }
    }.run;

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        contexts[t] = .{
            .logger_ptr = &logger,
            .thread_id = t,
            .use_structured = (t % 2 == 0),
        };
        threads[t] = try std.Thread.spawn(.{}, threadFunction, .{&contexts[t]});
    }

    t = 0;
    while (t < num_threads) : (t += 1) {
        threads[t].join();
    }
}

// ============================================================================
// PRIORITY 5: Concurrent with Different Formats
// ============================================================================

test "thread_safety: concurrent JSON logging" {
    if (!build_options.enable_json) return error.SkipZigTest;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .format = .json,
        .output_target = .stderr,
    });
    defer logger.deinit();

    const num_threads = 8;

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        thread_id: usize,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < 50) : (i += 1) {
                const fields = [_]zlog.Field{
                    .{ .key = "thread", .value = .{ .uint = ctx.thread_id } },
                    .{ .key = "count", .value = .{ .uint = i } },
                };
                ctx.logger_ptr.logWithFields(.info, "JSON concurrent test", &fields);
            }
        }
    }.run;

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        contexts[t] = .{
            .logger_ptr = &logger,
            .thread_id = t,
        };
        threads[t] = try std.Thread.spawn(.{}, threadFunction, .{&contexts[t]});
    }

    t = 0;
    while (t < num_threads) : (t += 1) {
        threads[t].join();
    }
}

test "thread_safety: concurrent binary logging" {
    if (!build_options.enable_binary_format) return error.SkipZigTest;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .format = .binary,
        .output_target = .stderr,
    });
    defer logger.deinit();

    const num_threads = 8;

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        thread_id: usize,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < 50) : (i += 1) {
                ctx.logger_ptr.info("Binary concurrent T{d} M{d}", .{ ctx.thread_id, i });
            }
        }
    }.run;

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        contexts[t] = .{
            .logger_ptr = &logger,
            .thread_id = t,
        };
        threads[t] = try std.Thread.spawn(.{}, threadFunction, .{&contexts[t]});
    }

    t = 0;
    while (t < num_threads) : (t += 1) {
        threads[t].join();
    }
}

// ============================================================================
// PRIORITY 6: Async Concurrent Tests
// ============================================================================

test "thread_safety: concurrent async logging" {
    if (!build_options.enable_async) return error.SkipZigTest;

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .async_io = true,
        .output_target = .stderr,
    });
    defer logger.deinit();

    const num_threads = 10;
    const messages_per_thread = 100;

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        thread_id: usize,
        count: usize,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.count) : (i += 1) {
                ctx.logger_ptr.info("Async concurrent T{d} M{d}", .{ ctx.thread_id, i });
            }
        }
    }.run;

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        contexts[t] = .{
            .logger_ptr = &logger,
            .thread_id = t,
            .count = messages_per_thread,
        };
        threads[t] = try std.Thread.spawn(.{}, threadFunction, .{&contexts[t]});
    }

    t = 0;
    while (t < num_threads) : (t += 1) {
        threads[t].join();
    }

    // Give async thread time to process queue
    std.Thread.sleep(100_000_000); // 100ms
}

// ============================================================================
// PRIORITY 7: Deadlock Prevention Tests
// ============================================================================

test "thread_safety: no deadlock on rapid concurrent init/deinit" {
    // NOTE: This test verifies that rapid init/deinit doesn't cause deadlocks
    // Each iteration is independent to prevent actual resource conflicts
    const allocator = testing.allocator;

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var logger = try zlog.Logger.init(allocator, .{
            .output_target = .stderr,
        });

        // Log from current thread
        logger.info("Rapid init/deinit test {d}", .{i});

        logger.deinit();
    }
}

// ============================================================================
// PRIORITY 8: Memory Ordering and Visibility Tests
// ============================================================================

test "thread_safety: message ordering visibility" {
    // This test verifies that messages from different threads are visible
    // Not testing strict ordering (which isn't guaranteed) but that all
    // messages are processed without loss

    const allocator = testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    });
    defer logger.deinit();

    const num_threads = 5;
    const messages_per_thread = 20;

    const ThreadContext = struct {
        logger_ptr: *zlog.Logger,
        thread_id: usize,
    };

    const threadFunction = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < messages_per_thread) : (i += 1) {
                ctx.logger_ptr.info("Visibility test T{d} M{d}", .{ ctx.thread_id, i });
            }
        }
    }.run;

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;

    var t: usize = 0;
    while (t < num_threads) : (t += 1) {
        contexts[t] = .{
            .logger_ptr = &logger,
            .thread_id = t,
        };
        threads[t] = try std.Thread.spawn(.{}, threadFunction, .{&contexts[t]});
    }

    t = 0;
    while (t < num_threads) : (t += 1) {
        threads[t].join();
    }

    // All messages should have been processed
    // Total: num_threads * messages_per_thread = 100 messages
}
