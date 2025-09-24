# Examples

Practical usage examples for zlog in various scenarios.

## Basic Usage

### Simple Logging

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{});
    defer logger.deinit();

    logger.debug("Application starting", .{});
    logger.info("Server listening on port {d}", .{8080});
    logger.warn("High memory usage: {d}MB", .{512});
    logger.err("Database connection failed", .{});
    logger.fatal("Cannot start application", .{});
}
```

### Global Logger

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    // Use global convenience functions
    zlog.info("Application started", .{});
    zlog.warn("This is a warning", .{});
    zlog.err("An error occurred", .{});
}

fn businessLogic() void {
    zlog.debug("Processing request", .{});
    zlog.info("Request completed", .{});
}
```

## Structured Logging

### User Authentication

```zig
const std = @import("std");
const zlog = @import("zlog");

const User = struct {
    id: u64,
    email: []const u8,
    role: []const u8,
};

pub fn loginUser(logger: *zlog.Logger, user: User, success: bool) void {
    const fields = [_]zlog.Field{
        .{ .key = "user_id", .value = .{ .uint = user.id } },
        .{ .key = "email", .value = .{ .string = user.email } },
        .{ .key = "role", .value = .{ .string = user.role } },
        .{ .key = "success", .value = .{ .boolean = success } },
        .{ .key = "timestamp", .value = .{ .uint = @intCast(std.time.timestamp()) } },
    };

    if (success) {
        logger.logWithFields(.info, "User login successful", &fields);
    } else {
        logger.logWithFields(.warn, "User login failed", &fields);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .format = .json,
    });
    defer logger.deinit();

    const user = User{
        .id = 12345,
        .email = "user@example.com",
        .role = "admin",
    };

    loginUser(&logger, user, true);
}
```

### HTTP Request Logging

```zig
const std = @import("std");
const zlog = @import("zlog");

const HttpRequest = struct {
    method: []const u8,
    path: []const u8,
    status_code: u16,
    duration_ms: f64,
    user_id: ?u64,
    ip_address: []const u8,
};

pub fn logHttpRequest(logger: *zlog.Logger, request: HttpRequest) void {
    var fields = std.ArrayList(zlog.Field).init(logger.allocator);
    defer fields.deinit();

    fields.append(.{ .key = "method", .value = .{ .string = request.method } }) catch return;
    fields.append(.{ .key = "path", .value = .{ .string = request.path } }) catch return;
    fields.append(.{ .key = "status", .value = .{ .uint = request.status_code } }) catch return;
    fields.append(.{ .key = "duration_ms", .value = .{ .float = request.duration_ms } }) catch return;
    fields.append(.{ .key = "ip", .value = .{ .string = request.ip_address } }) catch return;

    if (request.user_id) |id| {
        fields.append(.{ .key = "user_id", .value = .{ .uint = id } }) catch return;
    }

    const level: zlog.Level = if (request.status_code >= 500) .err
        else if (request.status_code >= 400) .warn
        else .info;

    logger.logWithFields(level, "HTTP request", fields.items);
}
```

## File Logging

### Application with Log Rotation

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .level = .info,
        .format = .json,
        .output_target = .file,
        .file_path = "app.log",
        .max_file_size = 10 * 1024 * 1024, // 10MB
        .max_backup_files = 5,
    });
    defer logger.deinit();

    logger.info("Application started", .{});

    // Simulate application work
    for (0..1000) |i| {
        logger.info("Processing item {d}", .{i});

        if (i % 100 == 0) {
            logger.warn("Checkpoint reached: {d}", .{i});
        }

        if (i % 500 == 0) {
            const fields = [_]zlog.Field{
                .{ .key = "processed", .value = .{ .uint = i } },
                .{ .key = "memory_mb", .value = .{ .uint = 128 + i / 10 } },
            };
            logger.logWithFields(.info, "Status update", &fields);
        }
    }

    logger.info("Application finished", .{});
}
```

### Multiple Log Files

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Application logger
    var app_logger = try zlog.Logger.init(allocator, .{
        .level = .info,
        .output_target = .file,
        .file_path = "app.log",
    });
    defer app_logger.deinit();

    // Error logger
    var error_logger = try zlog.Logger.init(allocator, .{
        .level = .err,
        .output_target = .file,
        .file_path = "errors.log",
        .format = .json,
    });
    defer error_logger.deinit();

    // Access logger
    var access_logger = try zlog.Logger.init(allocator, .{
        .level = .info,
        .output_target = .file,
        .file_path = "access.log",
        .format = .text,
    });
    defer access_logger.deinit();

    app_logger.info("Application started", .{});
    access_logger.info("GET /api/users - 200", .{});
    error_logger.err("Database timeout", .{});
}
```

## Async Logging

### High-Throughput Application

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .level = .info,
        .format = .binary,
        .output_target = .file,
        .file_path = "high_throughput.log",
        .async_io = true,
        .buffer_size = 32768,
    });
    defer logger.deinit(); // Important: waits for async thread

    logger.info("Starting high-throughput processing", .{});

    // Simulate high-frequency events
    for (0..100_000) |i| {
        logger.info("Event {d}", .{i});

        if (i % 1000 == 0) {
            const fields = [_]zlog.Field{
                .{ .key = "batch", .value = .{ .uint = i / 1000 } },
                .{ .key = "processed", .value = .{ .uint = i } },
            };
            logger.logWithFields(.info, "Batch completed", &fields);
        }
    }

    logger.info("Processing completed", .{});
    // logger.deinit() ensures all async logs are written
}
```

### Non-Blocking Web Server

```zig
const std = @import("std");
const zlog = @import("zlog");

var request_logger: zlog.Logger = undefined;

pub fn handleRequest(request_id: u64, path: []const u8) void {
    // Non-blocking log call
    const fields = [_]zlog.Field{
        .{ .key = "request_id", .value = .{ .uint = request_id } },
        .{ .key = "path", .value = .{ .string = path } },
    };

    request_logger.logWithFields(.info, "Request started", &fields);

    // Process request...

    request_logger.logWithFields(.info, "Request completed", &fields);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    request_logger = try zlog.Logger.init(allocator, .{
        .format = .json,
        .output_target = .file,
        .file_path = "requests.log",
        .async_io = true,
    });
    defer request_logger.deinit();

    // Simulate concurrent requests
    for (0..1000) |i| {
        handleRequest(i, "/api/data");
    }
}
```

## Performance Logging

### Sampling for High-Frequency Events

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Sample 1% of high-frequency events
    var high_freq_logger = try zlog.Logger.init(allocator, .{
        .level = .debug,
        .sampling_rate = 0.01,
        .output_target = .file,
        .file_path = "high_freq.log",
    });
    defer high_freq_logger.deinit();

    // Log all important events
    var important_logger = try zlog.Logger.init(allocator, .{
        .level = .info,
        .sampling_rate = 1.0,
        .output_target = .file,
        .file_path = "important.log",
    });
    defer important_logger.deinit();

    for (0..10_000) |i| {
        // High-frequency debug info (1% sampled)
        high_freq_logger.debug("Processing iteration {d}", .{i});

        if (i % 100 == 0) {
            // Important milestones (all logged)
            important_logger.info("Milestone reached: {d}", .{i});
        }
    }
}
```

### Binary Format for Maximum Performance

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .format = .binary,
        .output_target = .file,
        .file_path = "binary.log",
        .async_io = true,
        .buffer_size = 65536,
    });
    defer logger.deinit();

    const start = std.time.nanoTimestamp();

    // Log many events quickly
    for (0..50_000) |i| {
        const fields = [_]zlog.Field{
            .{ .key = "id", .value = .{ .uint = i } },
            .{ .key = "timestamp", .value = .{ .uint = @intCast(std.time.timestamp()) } },
            .{ .key = "active", .value = .{ .boolean = i % 2 == 0 } },
        };
        logger.logWithFields(.info, "Event", &fields);
    }

    const end = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;

    std.debug.print("Logged 50,000 events in {d:.2}ms\n", .{duration_ms});
    std.debug.print("Rate: {d:.0} events/second\n", .{50_000.0 / (duration_ms / 1000.0)});
}
```

## Production Examples

### Microservice Logging

```zig
const std = @import("std");
const zlog = @import("zlog");

const Service = struct {
    name: []const u8,
    version: []const u8,
    logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8) !Service {
        const logger = try zlog.Logger.init(allocator, .{
            .level = .info,
            .format = .json,
            .output_target = .stdout, // For container log collection
        });

        return Service{
            .name = name,
            .version = version,
            .logger = logger,
        };
    }

    pub fn deinit(self: *Service) void {
        self.logger.deinit();
    }

    pub fn start(self: *Service) void {
        const fields = [_]zlog.Field{
            .{ .key = "service", .value = .{ .string = self.name } },
            .{ .key = "version", .value = .{ .string = self.version } },
        };
        self.logger.logWithFields(.info, "Service starting", &fields);
    }

    pub fn handleRequest(self: *Service, request_id: []const u8, method: []const u8, path: []const u8) void {
        const fields = [_]zlog.Field{
            .{ .key = "service", .value = .{ .string = self.name } },
            .{ .key = "request_id", .value = .{ .string = request_id } },
            .{ .key = "method", .value = .{ .string = method } },
            .{ .key = "path", .value = .{ .string = path } },
        };
        self.logger.logWithFields(.info, "Request received", &fields);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var service = try Service.init(allocator, "user-api", "1.2.3");
    defer service.deinit();

    service.start();
    service.handleRequest("req-123", "GET", "/api/users/42");
}
```

### CLI Application

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const verbose = for (args) |arg| {
        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            break true;
        }
    } else false;

    const log_file = for (args[0..], 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--log-file") and i + 1 < args.len) {
            break args[i + 1];
        }
    } else null;

    // Configure logger based on CLI options
    var logger = try zlog.Logger.init(allocator, .{
        .level = if (verbose) .debug else .info,
        .format = .text,
        .output_target = if (log_file != null) .file else .stderr,
        .file_path = log_file,
    });
    defer logger.deinit();

    logger.info("CLI application starting", .{});

    if (verbose) {
        logger.debug("Verbose logging enabled", .{});
        logger.debug("Arguments: {any}", .{args});
    }

    if (log_file) |path| {
        logger.info("Logging to file: {s}", .{path});
    }

    // Application logic
    logger.info("Processing...", .{});
    logger.info("Processing complete", .{});
}
```

### Game Engine Logging

```zig
const std = @import("std");
const zlog = @import("zlog");

const GameEngine = struct {
    render_logger: zlog.Logger,
    physics_logger: zlog.Logger,
    audio_logger: zlog.Logger,
    general_logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator) !GameEngine {
        return GameEngine{
            .render_logger = try zlog.Logger.init(allocator, .{
                .level = .debug,
                .output_target = .file,
                .file_path = "render.log",
                .sampling_rate = 0.1, // High-frequency events
            }),
            .physics_logger = try zlog.Logger.init(allocator, .{
                .level = .info,
                .output_target = .file,
                .file_path = "physics.log",
            }),
            .audio_logger = try zlog.Logger.init(allocator, .{
                .level = .warn,
                .output_target = .file,
                .file_path = "audio.log",
            }),
            .general_logger = try zlog.Logger.init(allocator, .{
                .level = .info,
                .format = .text,
                .output_target = .stdout,
            }),
        };
    }

    pub fn deinit(self: *GameEngine) void {
        self.render_logger.deinit();
        self.physics_logger.deinit();
        self.audio_logger.deinit();
        self.general_logger.deinit();
    }

    pub fn update(self: *GameEngine, delta_time: f32) void {
        self.render_logger.debug("Frame rendered in {d:.2}ms", .{delta_time * 1000});

        const physics_fields = [_]zlog.Field{
            .{ .key = "delta_time", .value = .{ .float = delta_time } },
            .{ .key = "objects", .value = .{ .uint = 150 } },
        };
        self.physics_logger.logWithFields(.info, "Physics update", &physics_fields);
    }
};
```

## Error Handling

### Graceful Error Logging

```zig
const std = @import("std");
const zlog = @import("zlog");

const MyError = error{
    NetworkError,
    DatabaseError,
    ValidationError,
};

pub fn handleError(logger: *zlog.Logger, err: MyError, context: []const u8) void {
    const error_name = @errorName(err);

    const fields = [_]zlog.Field{
        .{ .key = "error", .value = .{ .string = error_name } },
        .{ .key = "context", .value = .{ .string = context } },
        .{ .key = "timestamp", .value = .{ .uint = @intCast(std.time.timestamp()) } },
    };

    logger.logWithFields(.err, "Error occurred", &fields);
}

pub fn riskyOperation(logger: *zlog.Logger) MyError!void {
    logger.debug("Starting risky operation", .{});

    // Simulate error
    return MyError.NetworkError;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .format = .json,
    });
    defer logger.deinit();

    riskyOperation(&logger) catch |err| {
        handleError(&logger, err, "main function");
    };
}
```

These examples demonstrate zlog's flexibility and power across different scenarios, from simple applications to high-performance systems.