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