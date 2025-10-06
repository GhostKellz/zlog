# Configuration Guide

Comprehensive guide to configuring zlog for different use cases.

## Table of Contents

1. [Basic Configuration](#basic-configuration)
2. [Configuration from Files](#configuration-from-files)
3. [Environment Variables](#environment-variables)
4. [Advanced Validation](#advanced-validation)
5. [Hot Reload](#hot-reload)

## Basic Configuration

## LoggerConfig Options

### Basic Configuration

```zig
pub const LoggerConfig = struct {
    level: Level = .info,
    format: Format = .text,
    output_target: OutputTarget = .stdout,
    // ... more options
};
```

### Log Levels

Control which messages are logged:

```zig
var config = zlog.LoggerConfig{
    .level = .debug,  // Log debug and above
};

var config = zlog.LoggerConfig{
    .level = .warn,   // Only warnings, errors, and fatal
};
```

**Level Hierarchy:**
- `debug` (0) - Most verbose
- `info` (1) - General information
- `warn` (2) - Warning conditions
- `err` (3) - Error conditions
- `fatal` (4) - Critical errors

### Output Formats

#### Text Format (Always Available)

```zig
var config = zlog.LoggerConfig{
    .format = .text,
};

// Output: [1234567890] [INFO] Hello, world!
```

#### JSON Format (Requires `json_format=true`)

```zig
var config = zlog.LoggerConfig{
    .format = .json,
};

// Output: {"timestamp":1234567890,"level":"INFO","message":"Hello, world!"}
```

#### Binary Format (Requires `binary_format=true`)

```zig
var config = zlog.LoggerConfig{
    .format = .binary,
};

// Output: Binary data (not human readable)
```

### Output Targets

#### Standard Streams

```zig
// Standard output (default)
var config = zlog.LoggerConfig{
    .output_target = .stdout,
};

// Standard error
var config = zlog.LoggerConfig{
    .output_target = .stderr,
};
```

#### File Output (Requires `file_targets=true`)

```zig
var config = zlog.LoggerConfig{
    .output_target = .file,
    .file_path = "app.log",
    .max_file_size = 100 * 1024 * 1024, // 100MB
    .max_backup_files = 5,
};
```

### Performance Settings

#### Buffer Size

```zig
var config = zlog.LoggerConfig{
    .buffer_size = 8192, // Larger buffer for better performance
};
```

#### Sampling

Control logging frequency for high-throughput scenarios:

```zig
var config = zlog.LoggerConfig{
    .sampling_rate = 0.1, // Log 10% of messages
};

var config = zlog.LoggerConfig{
    .sampling_rate = 1.0, // Log all messages (default)
};
```

### Async I/O (Requires `async_io=true`)

Non-blocking logging with background processing:

```zig
var config = zlog.LoggerConfig{
    .async_io = true,
    .buffer_size = 16384, // Larger buffer for async
};
```

### Aggregation Features (Requires `aggregation=true`)

#### Batching

```zig
var config = zlog.LoggerConfig{
    .enable_batching = true,
    .batch_size = 100,
    .batch_timeout_ms = 1000, // Flush batch after 1 second
};
```

#### Deduplication

```zig
var config = zlog.LoggerConfig{
    .enable_deduplication = true,
    .dedup_window_ms = 5000, // 5 second dedup window
};
```

## Common Configurations

### Development

Verbose logging with all debug information:

```zig
var dev_config = zlog.LoggerConfig{
    .level = .debug,
    .format = .text,
    .output_target = .stdout,
};
```

### Production

Structured JSON logs with file rotation:

```zig
var prod_config = zlog.LoggerConfig{
    .level = .info,
    .format = .json,
    .output_target = .file,
    .file_path = "/var/log/app.log",
    .max_file_size = 100 * 1024 * 1024, // 100MB
    .max_backup_files = 10,
};
```

### High-Performance

Binary format with async I/O and sampling:

```zig
var perf_config = zlog.LoggerConfig{
    .level = .info,
    .format = .binary,
    .output_target = .file,
    .file_path = "high_perf.log",
    .async_io = true,
    .sampling_rate = 0.1, // Sample 10%
    .buffer_size = 32768,
};
```

### Microservice

JSON with structured logging and deduplication:

```zig
var service_config = zlog.LoggerConfig{
    .level = .info,
    .format = .json,
    .output_target = .stdout, // For container logs
    .enable_deduplication = true,
    .dedup_window_ms = 10000,
};
```

## File Rotation Configuration

### Size-Based Rotation

```zig
var config = zlog.LoggerConfig{
    .output_target = .file,
    .file_path = "app.log",
    .max_file_size = 50 * 1024 * 1024, // 50MB
    .max_backup_files = 5,
};
```

**File naming pattern:**
- `app.log` - Current log file
- `app.log.0` - Most recent backup
- `app.log.1` - Second most recent
- `app.log.4` - Oldest backup (deleted when new backup created)

### Rotation Behavior

1. When `app.log` reaches `max_file_size`:
2. Existing backups are shifted: `app.log.0` → `app.log.1`, etc.
3. Current log becomes `app.log.0`
4. New empty `app.log` is created
5. Oldest backup beyond `max_backup_files` is deleted

## Build-Time Configuration

Enable/disable features at build time to control binary size and dependencies:

### Feature Flags

```bash
# Minimal build (text only, ~30KB)
zig build -Djson_format=false -Dfile_targets=false -Dbinary_format=false

# Standard build (~50KB)
zig build -Dfile_targets=true

# Full-featured build (~80KB)
zig build -Djson_format=true -Dfile_targets=true -Dbinary_format=true -Daggregation=true -Dasync_io=true
```

### In build.zig

```zig
const zlog_dep = b.dependency("zlog", .{
    .json_format = true,
    .file_targets = true,
    .binary_format = false,
    .async_io = true,
    .aggregation = false,
});
```

## Validation

All configurations are validated at runtime:

```zig
var config = zlog.LoggerConfig{
    .format = .json,        // But json_format=false at build time
    .output_target = .file,
    .file_path = null,      // Missing required file path
};

var logger = zlog.Logger.init(allocator, config); // Will return error
```

**Common Validation Errors:**
- `error.FormatNotEnabled` - Format disabled at build time
- `error.OutputTargetNotEnabled` - Target disabled at build time
- `error.FilePathRequired` - File path required for file output
- `error.AsyncNotEnabled` - Async disabled at build time
- `error.AggregationNotEnabled` - Aggregation disabled at build time

## Performance Tuning

### Buffer Sizing

```zig
// Small buffers (low memory usage)
.buffer_size = 1024,

// Medium buffers (balanced)
.buffer_size = 4096,  // Default

// Large buffers (high throughput)
.buffer_size = 32768,
```

### Sampling Strategies

```zig
// No sampling (log everything)
.sampling_rate = 1.0,

// Light sampling (log 50%)
.sampling_rate = 0.5,

// Heavy sampling (log 1%)
.sampling_rate = 0.01,

// Debug-only sampling
.sampling_rate = if (builtin.mode == .Debug) 1.0 else 0.1,
```

### Async Configuration

```zig
var async_config = zlog.LoggerConfig{
    .async_io = true,
    .buffer_size = 16384,    // Larger buffer for async
    .enable_batching = true, // Batch async writes
    .batch_size = 50,
};
```

## Environment-Specific Settings

### Docker/Container

```zig
var container_config = zlog.LoggerConfig{
    .level = .info,
    .format = .json,
    .output_target = .stdout, // For container log collection
};
```

### Systemd Service

```zig
var systemd_config = zlog.LoggerConfig{
    .level = .info,
    .format = .text,
    .output_target = .stderr, // Systemd captures stderr
};
```

### CLI Application

```zig
var cli_config = zlog.LoggerConfig{
    .level = if (verbose) .debug else .info,
    .format = .text,
    .output_target = if (log_file) |path| .file else .stderr,
    .file_path = log_file,
};
```

## Dynamic Configuration

Configuration can be adjusted based on runtime conditions:

```zig
const config = zlog.LoggerConfig{
    .level = if (std.process.getEnvVarOwned(allocator, "DEBUG")) |_| .debug else .info,
    .format = if (is_production) .json else .text,
    .output_target = if (log_file_path) |_| .file else .stdout,
    .file_path = log_file_path,
    .sampling_rate = if (high_load) 0.1 else 1.0,
};
```

---

## Configuration from Files

zlog supports loading configuration from JSON files (YAML and TOML support coming in future versions).

### JSON Configuration

Create a `log_config.json` file:

```json
{
  "level": "debug",
  "format": "json",
  "output_target": "file",
  "file_path": "/var/log/myapp.log",
  "max_file_size": 10485760,
  "max_backup_files": 5,
  "async_io": true,
  "buffer_size": 8192,
  "sampling_rate": 1.0,
  "enable_batching": false,
  "batch_size": 100,
  "enable_deduplication": false
}
```

Load the configuration:

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load configuration from JSON file
    var config_manager = try zlog.configuration.ConfigManager.init(
        allocator,
        "log_config.json",
        .json,
    );
    defer config_manager.deinit();

    // Create logger with loaded configuration
    var logger = try zlog.Logger.init(allocator, config_manager.getConfig());
    defer logger.deinit();

    logger.info("Logger initialized from config file", .{});
}
```

### Saving Configuration

Save current configuration to a file:

```zig
const config = zlog.LoggerConfig{
    .level = .info,
    .format = .json,
    .output_target = .stdout,
};

try zlog.configuration.saveConfigToFile(allocator, config, "my_config.json");
```

---

## Environment Variables

zlog can read configuration from environment variables, making it easy to configure logging in containerized environments.

### Supported Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `ZLOG_LEVEL` | Log level | `debug`, `info`, `warn`, `error`, `fatal` |
| `ZLOG_FORMAT` | Output format | `text`, `json`, `binary` |
| `ZLOG_OUTPUT` | Output target | `stdout`, `stderr`, `file` |
| `ZLOG_FILE` | Log file path | `/var/log/app.log` |

### Using Environment Variables

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Start with default configuration
    var config = zlog.LoggerConfig{};

    // Override with environment variables
    config = zlog.configuration.loadFromEnv(config);

    var logger = try zlog.Logger.init(allocator, config);
    defer logger.deinit();

    logger.info("Logger configured from environment", .{});
}
```

### Shell Examples

```bash
# Set debug level
export ZLOG_LEVEL=debug
./myapp

# JSON logging to file
export ZLOG_FORMAT=json
export ZLOG_OUTPUT=file
export ZLOG_FILE=/var/log/myapp.log
./myapp

# Production settings
export ZLOG_LEVEL=warn
export ZLOG_FORMAT=json
./myapp

# Development settings
export ZLOG_LEVEL=debug
export ZLOG_FORMAT=text
./myapp
```

### Docker/Kubernetes Example

```dockerfile
FROM alpine:latest

ENV ZLOG_LEVEL=info
ENV ZLOG_FORMAT=json
ENV ZLOG_OUTPUT=stdout

COPY myapp /usr/local/bin/
CMD ["/usr/local/bin/myapp"]
```

```yaml
# Kubernetes ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  ZLOG_LEVEL: "info"
  ZLOG_FORMAT: "json"
  ZLOG_OUTPUT: "stdout"
```

---

## Advanced Validation

zlog provides comprehensive configuration validation with helpful error messages and suggestions.

### Manual Validation

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = zlog.LoggerConfig{
        .level = .debug,
        .format = .json,
        .buffer_size = 100, // Too small!
    };

    // Validate configuration
    const validator = zlog.validation.ConfigValidator.init(allocator);
    var result = try validator.validate(config);
    defer result.deinit();

    // Check validation results
    if (!result.valid) {
        std.debug.print("Configuration has errors:\n", .{});
        result.print(); // Prints detailed errors, warnings, and suggestions
        return error.InvalidConfiguration;
    }

    var logger = try zlog.Logger.init(allocator, config);
    defer logger.deinit();
}
```

### Automatic Fixing

```zig
// Automatically fix common configuration issues
const config = zlog.LoggerConfig{
    .buffer_size = 100,     // Too small
    .sampling_rate = 2.0,   // Invalid (must be 0.0-1.0)
};

const fixed_config = try zlog.validation.fixConfig(allocator, config);
// fixed_config.buffer_size = 4096 (safe default)
// fixed_config.sampling_rate = 1.0 (no sampling)

var logger = try zlog.Logger.init(allocator, fixed_config);
defer logger.deinit();
```

### Validation Output Example

```
❌ Configuration validation failed

🚨 Errors:
   buffer_size: Buffer size too small, minimum 256 bytes (InvalidBufferSize)
   sampling_rate: Sampling rate must be between 0.0 and 1.0 (InvalidSamplingRate)

⚠️  Warnings:
   🟠 level: Debug level will log all messages - may impact performance

💡 Suggestions:
   buffer_size: '100' → '1024' (Minimum safe buffer size)
   sampling_rate: '2.00' → '1.0' (No sampling)
```

---

## Hot Reload

zlog supports hot-reloading configuration from files without restarting your application.

### Enabling Hot Reload

```zig
const std = @import("std");
const zlog = @import("zlog");

var current_logger: ?zlog.Logger = null;

fn onConfigReload(new_config: zlog.LoggerConfig) void {
    std.debug.print("Configuration reloaded!\n", .{});

    // Clean up old logger
    if (current_logger) |*logger| {
        logger.deinit();
    }

    // Create new logger with updated config
    current_logger = zlog.Logger.init(
        std.heap.page_allocator,
        new_config,
    ) catch |err| {
        std.debug.print("Failed to create logger: {}\n", .{err});
        return;
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize config manager
    var config_manager = try zlog.configuration.ConfigManager.init(
        allocator,
        "log_config.json",
        .json,
    );
    defer config_manager.deinit();

    // Enable hot reload with callback
    try config_manager.enableHotReload(onConfigReload);

    // Initialize logger
    current_logger = try zlog.Logger.init(allocator, config_manager.getConfig());

    // Your application code...
    while (true) {
        if (current_logger) |logger| {
            logger.info("Application running", .{});
        }
        std.time.sleep(1 * std.time.ns_per_s);
    }
}
```

### Manual Reload

```zig
var config_manager = try zlog.configuration.ConfigManager.init(
    allocator,
    "log_config.json",
    .json,
);

// ... later ...

// Manually reload configuration
try config_manager.reload();
const new_config = config_manager.getConfig();

// Recreate logger with new config
var logger = try zlog.Logger.init(allocator, new_config);
```

---

## Best Practices

### 1. **Development vs Production**

```zig
const is_production = std.process.getEnvVarOwned(allocator, "PRODUCTION") catch |_| false;

const config = zlog.LoggerConfig{
    .level = if (is_production) .warn else .debug,
    .format = if (is_production) .json else .text,
    .output_target = if (is_production) .file else .stdout,
    .file_path = if (is_production) "/var/log/app.log" else null,
    .async_io = is_production, // Better performance in production
};
```

### 2. **Configuration Layering**

```zig
// 1. Start with defaults
var config = zlog.LoggerConfig{};

// 2. Load from config file (if exists)
if (std.fs.cwd().openFile("log_config.json", .{})) |_| {
    var cfg_mgr = try zlog.configuration.ConfigManager.init(allocator, "log_config.json", .json);
    config = cfg_mgr.getConfig();
    cfg_mgr.deinit();
} else |_| {}

// 3. Override with environment variables
config = zlog.configuration.loadFromEnv(config);

// 4. Validate and fix
config = try zlog.validation.fixConfig(allocator, config);
```

### 3. **Error Handling**

Always validate configuration and handle errors gracefully:

```zig
var logger = zlog.Logger.init(allocator, config) catch |err| {
    std.debug.print("Failed to initialize logger: {}\n", .{err});
    // Fall back to stderr logging
    return zlog.Logger.init(allocator, .{
        .output_target = .stderr,
    }) catch unreachable;
};
```