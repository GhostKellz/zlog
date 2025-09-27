# API Reference

Complete API documentation for zlog.

## Types

### Level

Log levels supported by zlog.

```zig
pub const Level = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
    fatal = 4,
};
```

**Methods:**

- `toString(self: Level) []const u8` - Convert level to string representation

### Format

Output formats supported by zlog.

```zig
pub const Format = enum {
    text,    // Always available
    json,    // Requires json_format=true
    binary,  // Requires binary_format=true
};
```

**Methods:**

- `isAvailable(format: Format) bool` - Check if format is enabled in current build

### OutputTarget

Available output targets.

```zig
pub const OutputTarget = enum {
    stdout,  // Always available
    stderr,  // Always available
    file,    // Requires file_targets=true
};
```

**Methods:**

- `isAvailable(target: OutputTarget) bool` - Check if target is enabled in current build

### Field

Represents a structured logging field with a key-value pair.

```zig
pub const Field = struct {
    key: []const u8,
    value: Value,

    pub const Value = union(enum) {
        string: []const u8,
        int: i64,
        uint: u64,
        float: f64,
        boolean: bool,
    };
};
```

**Examples:**

```zig
const fields = [_]zlog.Field{
    .{ .key = "user_id", .value = .{ .uint = 12345 } },
    .{ .key = "action", .value = .{ .string = "login" } },
    .{ .key = "success", .value = .{ .boolean = true } },
    .{ .key = "latency", .value = .{ .float = 15.7 } },
};
```

### LoggerConfig

Configuration structure for Logger initialization.

```zig
pub const LoggerConfig = struct {
    level: Level = .info,
    format: Format = .text,
    output_target: OutputTarget = .stdout,
    file_path: ?[]const u8 = null,
    max_file_size: usize = 10 * 1024 * 1024, // 10MB
    max_backup_files: u8 = 5,
    async_io: bool = false,
    sampling_rate: f32 = 1.0,
    buffer_size: usize = 4096,

    // Aggregation settings (when enabled)
    enable_batching: bool = false,
    batch_size: usize = 100,
    batch_timeout_ms: u64 = 1000,
    enable_deduplication: bool = false,
    dedup_window_ms: u64 = 5000,
};
```

**Examples:**

```zig
// Basic console logger
const basic_config = zlog.LoggerConfig{};

// High-performance file logger
const file_config = zlog.LoggerConfig{
    .output_target = .file,
    .file_path = "app.log",
    .format = .binary,
    .async_io = true,
    .buffer_size = 16384,
};

// Development logger with JSON output
const dev_config = zlog.LoggerConfig{
    .level = .debug,
    .format = .json,
    .buffer_size = 8192,
};
```

## Logger Methods

### Initialization

#### `init(allocator: std.mem.Allocator, config: LoggerConfig) !Logger`

Creates and initializes a new logger instance.

**Parameters:**
- `allocator`: Memory allocator for internal buffers
- `config`: Logger configuration

**Returns:** Initialized Logger instance or error

**Examples:**

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Basic logger
    var logger = try zlog.Logger.init(allocator, .{});
    defer logger.deinit();

    // File logger with rotation
    var file_logger = try zlog.Logger.init(allocator, .{
        .output_target = .file,
        .file_path = "myapp.log",
        .max_file_size = 50 * 1024 * 1024, // 50MB
        .max_backup_files = 3,
    });
    defer file_logger.deinit();
}
```

#### `deinit(self: *Logger) void`

Cleanup logger resources. Always call this before the logger goes out of scope.

### Basic Logging

#### `debug(self: *Logger, comptime fmt: []const u8, args: anytype) void`
#### `info(self: *Logger, comptime fmt: []const u8, args: anytype) void`
#### `warn(self: *Logger, comptime fmt: []const u8, args: anytype) void`
#### `err(self: *Logger, comptime fmt: []const u8, args: anytype) void`
#### `fatal(self: *Logger, comptime fmt: []const u8, args: anytype) void`

Log messages at different levels with printf-style formatting.

**Examples:**

```zig
logger.debug("Debug info: variable = {d}", .{42});
logger.info("User {} logged in successfully", .{"alice"});
logger.warn("High memory usage: {d}%", .{85});
logger.err("Failed to connect to database: {s}", .{error_msg});
logger.fatal("Critical system failure occurred");
```

### Structured Logging

#### `logWithFields(self: *Logger, level: Level, message: []const u8, fields: []const Field) void`

Log structured data with fields.

**Examples:**

```zig
// Web request logging
const request_fields = [_]zlog.Field{
    .{ .key = "method", .value = .{ .string = "GET" } },
    .{ .key = "path", .value = .{ .string = "/api/users" } },
    .{ .key = "status", .value = .{ .uint = 200 } },
    .{ .key = "duration_ms", .value = .{ .float = 45.2 } },
    .{ .key = "user_id", .value = .{ .uint = 12345 } },
};
logger.logWithFields(.info, "HTTP request completed", &request_fields);

// Error logging with context
const error_fields = [_]zlog.Field{
    .{ .key = "error_code", .value = .{ .string = "DB_CONNECTION_FAILED" } },
    .{ .key = "retry_count", .value = .{ .uint = 3 } },
    .{ .key = "timeout_ms", .value = .{ .uint = 5000 } },
};
logger.logWithFields(.err, "Database operation failed", &error_fields);

// Performance metrics
const perf_fields = [_]zlog.Field{
    .{ .key = "operation", .value = .{ .string = "data_processing" } },
    .{ .key = "records_processed", .value = .{ .uint = 10000 } },
    .{ .key = "memory_mb", .value = .{ .float = 125.6 } },
    .{ .key = "cpu_percent", .value = .{ .float = 78.9 } },
};
logger.logWithFields(.info, "Performance metrics", &perf_fields);
```

## Advanced Usage

### Async Logging

```zig
var async_logger = try zlog.Logger.init(allocator, .{
    .async_io = true,
    .buffer_size = 16384, // Larger buffer for async
    .format = .json,
});
defer async_logger.deinit();

// These log calls return immediately
async_logger.info("High-throughput logging");
async_logger.warn("Non-blocking operation");
```

### Binary Format for Performance

```zig
var binary_logger = try zlog.Logger.init(allocator, .{
    .format = .binary,
    .output_target = .file,
    .file_path = "performance.bin",
});
defer binary_logger.deinit();

// Compact, high-speed logging
binary_logger.info("Binary format is ~40% smaller");
```

### Log Sampling

```zig
var sampled_logger = try zlog.Logger.init(allocator, .{
    .sampling_rate = 0.1, // Log 10% of messages
});
defer sampled_logger.deinit();

// Only ~10% of these will actually be logged
for (0..1000) |i| {
    sampled_logger.info("High-frequency event {d}", .{i});
}
```

### File Rotation

```zig
var rotating_logger = try zlog.Logger.init(allocator, .{
    .output_target = .file,
    .file_path = "/var/log/myapp.log",
    .max_file_size = 100 * 1024 * 1024, // 100MB per file
    .max_backup_files = 7, // Keep 7 days of logs
});
defer rotating_logger.deinit();

// Automatic rotation when file size exceeded
```

## Global Default Logger

For convenience, zlog provides global logging functions:

```zig
const zlog = @import("zlog");

// These use a default logger instance
zlog.info("Application started");
zlog.warn("Using default logger");
zlog.err("Something went wrong");

// Customize the default logger
var custom_logger = try zlog.Logger.init(allocator, .{
    .level = .debug,
    .format = .json,
});
zlog.setDefaultLogger(custom_logger);

// Now global functions use the custom logger
zlog.debug("This will be in JSON format");
```

## Error Handling

All logger initialization can fail. Common errors:

```zig
const logger_result = zlog.Logger.init(allocator, config);
if (logger_result) |logger| {
    defer logger.deinit();
    logger.info("Logger initialized successfully");
} else |err| switch (err) {
    error.FileNotFound => {
        std.debug.print("Log directory doesn't exist\n", .{});
    },
    error.PermissionDenied => {
        std.debug.print("No write permission for log file\n", .{});
    },
    error.OutOfMemory => {
        std.debug.print("Insufficient memory for logger\n", .{});
    },
    error.FormatNotEnabled => {
        std.debug.print("Requested format not compiled in\n", .{});
    },
    else => {
        std.debug.print("Logger initialization failed: {}\n", .{err});
    },
}
```

## Performance Tips

1. **Use appropriate buffer sizes**: Larger buffers reduce syscalls but use more memory
2. **Choose the right format**: Binary format is fastest, JSON is most readable
3. **Enable async I/O for high throughput**: Non-blocking logging for busy applications
4. **Use sampling for very high frequency events**: Reduce log volume while maintaining visibility
5. **Structure your logs**: Consistent field names make analysis easier

## Thread Safety

All Logger methods are thread-safe and can be called concurrently from multiple threads:

```zig
const logger = try zlog.Logger.init(allocator, .{});
defer logger.deinit();

// Safe to call from multiple threads
const thread1 = try std.Thread.spawn(.{}, workerFunction, .{&logger});
const thread2 = try std.Thread.spawn(.{}, workerFunction, .{&logger});

thread1.join();
thread2.join();

fn workerFunction(logger: *zlog.Logger) void {
    logger.info("Thread-safe logging");
}
```

### Field

Structured logging field with typed values.

```zig
pub const Field = struct {
    key: []const u8,
    value: Value,

    pub const Value = union(enum) {
        string: []const u8,
        int: i64,
        uint: u64,
        float: f64,
        boolean: bool,
    };
};
```

### LogEntry

Internal representation of a log entry.

```zig
pub const LogEntry = struct {
    level: Level,
    timestamp: i64,
    message: []const u8,
    fields: []const Field,
};
```

### LoggerConfig

Configuration structure for creating loggers.

```zig
pub const LoggerConfig = struct {
    level: Level = .info,
    format: Format = .text,
    output_target: OutputTarget = .stdout,
    file_path: ?[]const u8 = null,
    max_file_size: usize = 10 * 1024 * 1024, // 10MB
    max_backup_files: u8 = 5,
    async_io: bool = false,
    sampling_rate: f32 = 1.0,
    buffer_size: usize = 4096,

    // Aggregation settings (requires aggregation=true)
    enable_batching: bool = false,
    batch_size: usize = 100,
    batch_timeout_ms: u64 = 1000,
    enable_deduplication: bool = false,
    dedup_window_ms: u64 = 5000,
};
```

**Methods:**

- `validate(self: LoggerConfig) !void` - Validate configuration

**Errors:**

- `error.FormatNotEnabled` - Format not available in current build
- `error.OutputTargetNotEnabled` - Output target not available in current build
- `error.FilePathRequired` - File path required for file output
- `error.AsyncNotEnabled` - Async I/O not available in current build
- `error.AggregationNotEnabled` - Aggregation not available in current build

## Logger

Main logging interface.

```zig
pub const Logger = struct {
    // ... internal fields
};
```

### Methods

#### init

Create a new logger instance.

```zig
pub fn init(allocator: std.mem.Allocator, config: LoggerConfig) !Logger
```

**Parameters:**
- `allocator` - Memory allocator for internal buffers
- `config` - Logger configuration

**Returns:**
- `Logger` - Initialized logger instance

**Errors:**
- Configuration validation errors
- Memory allocation errors
- File creation errors (for file output)

#### deinit

Clean up logger resources.

```zig
pub fn deinit(self: *Logger) void
```

Shuts down async threads, closes files, and frees memory.

#### log

Generic logging function with formatting.

```zig
pub fn log(self: *Logger, level: Level, comptime fmt: []const u8, args: anytype) void
```

**Parameters:**
- `level` - Log level
- `fmt` - Format string (compile-time)
- `args` - Format arguments

#### logWithFields

Structured logging with fields.

```zig
pub fn logWithFields(self: *Logger, level: Level, message: []const u8, fields: []const Field) void
```

**Parameters:**
- `level` - Log level
- `message` - Log message
- `fields` - Array of structured fields

#### Convenience Methods

Level-specific logging methods:

```zig
pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void
pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void
pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) void
pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void
pub fn fatal(self: *Logger, comptime fmt: []const u8, args: anytype) void
```

## Global Functions

Convenience functions using the default logger:

```zig
pub fn debug(comptime fmt: []const u8, args: anytype) void
pub fn info(comptime fmt: []const u8, args: anytype) void
pub fn warn(comptime fmt: []const u8, args: anytype) void
pub fn err(comptime fmt: []const u8, args: anytype) void
pub fn fatal(comptime fmt: []const u8, args: anytype) void
```

### Default Logger Management

```zig
pub fn getDefaultLogger() !*Logger
pub fn setDefaultLogger(logger: Logger) void
```

## Examples

### Basic Usage

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .level = .debug,
        .format = .text,
    });
    defer logger.deinit();

    logger.debug("Debug message", .{});
    logger.info("Info with value: {d}", .{42});
    logger.warn("Warning message", .{});
    logger.err("Error occurred", .{});
}
```

### Structured Logging

```zig
const fields = [_]zlog.Field{
    .{ .key = "user_id", .value = .{ .uint = 12345 } },
    .{ .key = "action", .value = .{ .string = "login" } },
    .{ .key = "success", .value = .{ .boolean = true } },
    .{ .key = "latency", .value = .{ .float = 15.7 } },
};

logger.logWithFields(.info, "User logged in", &fields);
```

### File Logging

```zig
var logger = try zlog.Logger.init(allocator, .{
    .level = .info,
    .format = .text,
    .output_target = .file,
    .file_path = "app.log",
    .max_file_size = 50 * 1024 * 1024, // 50MB
    .max_backup_files = 10,
});
```

### JSON Format

```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .json,
});

logger.info("JSON message", .{});
// Output: {"timestamp":1234567890,"level":"INFO","message":"JSON message"}
```

### Async Logging

```zig
var logger = try zlog.Logger.init(allocator, .{
    .async_io = true,
    .buffer_size = 8192,
});

logger.info("Async message", .{});
```

### Sampling

```zig
var logger = try zlog.Logger.init(allocator, .{
    .sampling_rate = 0.1, // Log 10% of messages
});

// Only ~10% of these will be logged
for (0..1000) |i| {
    logger.info("Message {d}", .{i});
}
```

## Thread Safety

All Logger methods are thread-safe. Multiple threads can safely call logging methods on the same logger instance simultaneously. Internal synchronization is handled automatically.

## Performance Considerations

- Use sampling for high-frequency logging
- Binary format is fastest for high-throughput scenarios
- Async I/O prevents blocking on I/O operations
- Structured logging adds minimal overhead
- Log level filtering happens early to minimize work

## Build-Time Features

Features can be disabled at build time to reduce binary size:

```zig
// In build.zig
const zlog_dep = b.dependency("zlog", .{
    .json_format = false,
    .file_targets = false,
    .binary_format = false,
    .async_io = false,
    .aggregation = false,
});
```

Disabled features will compile to no-ops or fallback to basic implementations.