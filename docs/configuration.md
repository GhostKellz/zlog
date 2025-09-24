# Configuration Guide

Comprehensive guide to configuring zlog for different use cases.

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