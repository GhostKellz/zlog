# zlog API Reference

Complete API documentation for zlog v1.0.0

## Table of Contents

- [Core Types](#core-types)
- [Logger](#logger)
- [Configuration](#configuration)
- [Fields and Structured Logging](#fields-and-structured-logging)
- [Output Targets](#output-targets)
- [Formats](#formats)
- [Network Targets](#network-targets)
- [Metrics and Monitoring](#metrics-and-monitoring)
- [Error Handling](#error-handling)
- [Utilities](#utilities)

---

## Core Types

### `Level`

Log level enumeration with severity ordering.

```zig
pub const Level = enum(u8) {
    debug = 0,  // Detailed diagnostic information
    info = 1,   // General application flow
    warn = 2,   // Warning conditions
    err = 3,    // Error conditions
    fatal = 4,  // Critical errors
};
```

**Methods:**
- `toString() []const u8` - Returns string representation

**Example:**
```zig
const level = zlog.Level.info;
std.debug.print("Level: {s}\n", .{level.toString()}); // "INFO"
```

---

### `Format`

Output format enumeration.

```zig
pub const Format = enum {
    text,    // Human-readable text (always available)
    json,    // Structured JSON (requires enable_json build flag)
    binary,  // Compact binary format (requires enable_binary_format)
};
```

**Methods:**
- `isAvailable(format: Format) bool` - Check if format is enabled in build

---

### `OutputTarget`

Output destination enumeration.

```zig
pub const OutputTarget = enum {
    stdout,   // Standard output (always available)
    stderr,   // Standard error (always available)
    file,     // File output (requires enable_file_targets)
    network,  // Network output (requires enable_network_targets)
};
```

---

## Logger

### `Logger.init()`

Create and initialize a new logger instance.

```zig
pub fn init(allocator: std.mem.Allocator, config: LoggerConfig) !Logger
```

**Parameters:**
- `allocator` - Memory allocator for logger resources
- `config` - Logger configuration

**Returns:** Initialized `Logger` instance

**Example:**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .level = .info,
    .format = .text,
    .output_target = .stdout,
});
defer logger.deinit();
```

---

### `Logger.deinit()`

Clean up logger resources.

```zig
pub fn deinit(self: *Logger) void
```

**Example:**
```zig
defer logger.deinit();
```

---

### Logging Methods

#### `debug()`, `info()`, `warn()`, `err()`, `fatal()`

Log formatted messages at specific levels.

```zig
pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void
pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void
pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) void
pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void
pub fn fatal(self: *Logger, comptime fmt: []const u8, args: anytype) void
```

**Example:**
```zig
logger.info("Server started on port {d}", .{8080});
logger.warn("High memory usage: {d}%", .{85});
logger.err("Failed to connect to database", .{});
```

---

### `logWithFields()`

Log structured messages with typed fields.

```zig
pub fn logWithFields(
    self: *Logger,
    level: Level,
    message: []const u8,
    fields: []const Field
) void
```

**Parameters:**
- `level` - Log level
- `message` - Log message
- `fields` - Array of structured fields

**Example:**
```zig
const fields = [_]zlog.Field{
    .{ .key = "user_id", .value = .{ .uint = 12345 } },
    .{ .key = "action", .value = .{ .string = "login" } },
    .{ .key = "duration_ms", .value = .{ .float = 15.7 } },
};
logger.logWithFields(.info, "User action completed", &fields);
```

---

## Configuration

### `LoggerConfig`

Configuration structure for logger initialization.

```zig
pub const LoggerConfig = struct {
    // Core settings
    level: Level = .info,
    format: Format = .text,
    output_target: OutputTarget = .stdout,
    buffer_size: usize = 4096,
    sampling_rate: f32 = 1.0,  // 0.0-1.0, percentage of logs to keep

    // File settings (when output_target = .file)
    file_path: ?[]const u8 = null,
    max_file_size: usize = 10 * 1024 * 1024,  // 10MB
    max_backup_files: u8 = 5,

    // Async settings (requires enable_async)
    async_io: bool = false,

    // Network settings (requires enable_network_targets)
    network_config: ?NetworkConfig = null,

    // Aggregation settings (requires enable_aggregation)
    enable_batching: bool = false,
    batch_size: usize = 100,
    batch_timeout_ms: u64 = 1000,
    enable_deduplication: bool = false,
    dedup_window_ms: u64 = 5000,
};
```

**Methods:**
- `validate() !void` - Validate configuration

---

### Configuration Builder

Fluent API for building configurations.

```zig
const config = zlog.api.ConfigBuilder.init()
    .level(.debug)
    .format(.json)
    .file("app.log")
    .bufferSize(8192)
    .async(true)
    .build();

var logger = try zlog.Logger.init(allocator, config);
```

---

### Configuration Files

Load configuration from JSON files.

```zig
const config_mgr = try zlog.config.ConfigManager.init(
    allocator,
    "logger.json",
    .json,
);
defer config_mgr.deinit();

const config = config_mgr.getConfig();
var logger = try zlog.Logger.init(allocator, config);
```

**Example JSON Configuration:**
```json
{
  "level": "info",
  "format": "json",
  "output_target": "file",
  "file_path": "app.log",
  "max_file_size": 10485760,
  "async_io": true,
  "buffer_size": 8192
}
```

---

### Hot Reload

Enable automatic configuration reloading.

```zig
fn onConfigReload(new_config: zlog.LoggerConfig) void {
    std.debug.print("Configuration reloaded\n", .{});
}

try config_mgr.enableHotReload(onConfigReload);
```

---

## Fields and Structured Logging

### `Field`

Typed key-value pair for structured logging.

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

---

### Convenience Field Constructors

Use the `macros` module for easier field creation.

```zig
const zlog_macros = @import("zlog").macros;

const fields = [_]zlog.Field{
    zlog_macros.str("username", "alice"),
    zlog_macros.uint("user_id", 123),
    zlog_macros.float("latency_ms", 45.2),
    zlog_macros.boolean("success", true),
};
```

---

### Common Fields

Pre-defined field helpers for common patterns.

```zig
const fields = [_]zlog.Field{
    zlog_macros.CommonFields.requestId("req-123"),
    zlog_macros.CommonFields.userId(456),
    zlog_macros.CommonFields.duration(123.45),
    zlog_macros.CommonFields.statusCode(200),
};
```

---

### Log Context

Builder pattern for accumulating fields.

```zig
var ctx = zlog_macros.LogContext.init(allocator);
defer ctx.deinit();

try ctx.addStr("operation", "user_login");
try ctx.addUint("user_id", 123);
try ctx.addFloat("duration_ms", 45.2);

ctx.info(&logger, "Operation completed");
```

---

## Output Targets

### File Output with Rotation

```zig
var logger = try zlog.Logger.init(allocator, .{
    .output_target = .file,
    .file_path = "app.log",
    .max_file_size = 10 * 1024 * 1024,  // 10MB
    .max_backup_files = 5,  // Keep 5 rotated files
});
```

**Behavior:**
- Files rotate automatically when `max_file_size` is reached
- Rotated files are named: `app.log.0`, `app.log.1`, etc.
- Oldest files are deleted when `max_backup_files` is exceeded

---

### Async I/O

Enable non-blocking logging for high-performance applications.

```zig
var logger = try zlog.Logger.init(allocator, .{
    .async_io = true,
    .buffer_size = 16384,
});
```

**Benefits:**
- Non-blocking log calls
- Batch processing for efficiency
- Automatic queue management

---

## Network Targets

Send logs over the network (requires `enable_network_targets`).

### TCP/UDP Output

```zig
const network_config = zlog.network.NetworkConfig{
    .protocol = .tcp,
    .host = "192.168.1.100",
    .port = 5140,
    .connect_timeout_ms = 5000,
};

var logger = try zlog.Logger.init(allocator, .{
    .output_target = .network,
    .network_config = network_config,
});
```

---

### HTTP/HTTPS Output

```zig
const network_config = zlog.network.NetworkConfig{
    .protocol = .https,
    .host = "logs.example.com",
    .port = 443,
    .http_method = "POST",
    .http_path = "/v1/logs",
    .auth_token = "your-api-token",
};
```

---

### Syslog Output

```zig
const network_config = zlog.network.NetworkConfig{
    .protocol = .syslog_udp,
    .host = "syslog.example.com",
    .port = 514,
    .syslog_facility = .user,
    .syslog_app_name = "myapp",
};
```

---

## Metrics and Monitoring

### Built-in Metrics

Track logger performance automatically.

```zig
var metrics = try zlog.metrics.MetricsCollector.init(allocator);
defer metrics.deinit();

// Metrics are collected automatically
metrics.recordMessage(.info, 100);
metrics.recordLogLatency(5000); // nanoseconds

// Print performance report
metrics.printReport();
```

**Available Metrics:**
- `messages_logged` - Total messages logged
- `messages_per_level` - Messages by level
- `bytes_written` - Total bytes written
- `log_latency_ns` - Log operation latency
- `write_errors` - Write failures
- `buffer_overflows` - Buffer overflow events

---

### Health Checks

Monitor logger health status.

```zig
var health = try zlog.metrics.HealthCheck.fromMetrics(allocator, &metrics);
defer health.deinit();

health.print(); // Human-readable output

// JSON output
var buffer = std.ArrayList(u8).init(allocator);
defer buffer.deinit();
try health.toJson(buffer.writer());
```

---

### Prometheus Export

Export metrics in Prometheus format.

```zig
var buffer = std.ArrayList(u8).init(allocator);
defer buffer.deinit();

try metrics.exportPrometheus(buffer.writer());
// Write buffer.items to HTTP endpoint
```

---

## Error Handling

### Error Types

All zlog errors are part of the `ZlogError` error set.

```zig
pub const ZlogError = error{
    InvalidConfiguration,
    FormatNotEnabled,
    OutputTargetNotEnabled,
    FilePathRequired,
    OutOfMemory,
    WriteError,
    // ... and more
};
```

---

### Error Context

Detailed error information with recovery hints.

```zig
const errors = @import("zlog").errors;

const err_ctx = errors.createError(
    .InvalidConfiguration,
    "Buffer size too small",
    "init",
    "logger.zig",
    42
);

err_ctx.print(); // Detailed error output
```

---

### Validation

Validate configuration before use.

```zig
const validator = zlog.validation.ConfigValidator.init(allocator);
var result = try validator.validate(config);
defer result.deinit();

if (!result.valid) {
    result.print(); // Shows errors, warnings, and suggestions
}
```

---

## Utilities

### Global Default Logger

Use convenience functions without explicit logger instance.

```zig
zlog.info("Application started", .{});
zlog.warn("Low disk space", .{});
zlog.err("Connection failed", .{});
```

---

### Scoped Logging

Automatic timing and scope tracking.

```zig
var scoped = try zlog_macros.ScopedLogger.init(&logger, allocator, "processRequest");
defer scoped.deinit(); // Logs exit with duration

scoped.info("Processing started");
// ... work ...
// Automatically logs "Exiting scope" with duration
```

---

### Environment Variables

Override configuration with environment variables:

- `ZLOG_LEVEL` - Set log level (debug, info, warn, error, fatal)
- `ZLOG_FORMAT` - Set output format (text, json, binary)
- `ZLOG_OUTPUT` - Set output target (stdout, stderr, file)
- `ZLOG_FILE` - Set file path for file output

```zig
const config = zlog.config.loadFromEnv(base_config);
```

---

## Build Options

Control zlog features at compile time:

```bash
# Enable all features
zig build -Djson_format=true -Dfile_targets=true -Dbinary_format=true \
          -Daggregation=true -Dasync_io=true -Dnetwork_targets=true \
          -Dmetrics=true

# Minimal build (text format only)
zig build -Djson_format=false -Dfile_targets=false

# High-performance build
zig build -Dbinary_format=true -Dasync_io=true
```

---

## Complete Example

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger with file rotation
    var logger = try zlog.Logger.init(allocator, .{
        .level = .info,
        .format = .json,
        .output_target = .file,
        .file_path = "app.log",
        .max_file_size = 10 * 1024 * 1024,
        .max_backup_files = 5,
        .async_io = true,
    });
    defer logger.deinit();

    // Simple logging
    logger.info("Application started", .{});

    // Structured logging
    const fields = [_]zlog.Field{
        .{ .key = "user_id", .value = .{ .uint = 12345 } },
        .{ .key = "action", .value = .{ .string = "login" } },
        .{ .key = "duration_ms", .value = .{ .float = 15.7 } },
    };
    logger.logWithFields(.info, "User logged in", &fields);

    // Using context builder
    const macros = @import("zlog").macros;
    var ctx = macros.LogContext.init(allocator);
    defer ctx.deinit();

    try ctx.addStr("operation", "database_query");
    try ctx.addFloat("duration_ms", 123.45);
    ctx.info(&logger, "Query completed");
}
```

---

For more examples, see the `examples/` directory.
For performance tuning, see [PERFORMANCE.md](PERFORMANCE.md).
For migration from other loggers, see [MIGRATION.md](MIGRATION.md).
