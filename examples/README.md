# zlog Examples

This directory contains example programs demonstrating various zlog features.

## Examples

### Basic Usage (`basic_usage.zig`)

Simple logging with different levels and formatted messages.

**Run:**
```bash
zig build-exe basic_usage.zig --dep zlog --mod zlog:../src/root.zig
./basic_usage
```

**Demonstrates:**
- Creating a logger
- Logging at different levels (debug, info, warn, err)
- Formatted logging with arguments
- Different data types in logs

---

### Structured Logging (`structured_logging.zig`)

Rich, queryable logging with typed fields.

**Run:**
```bash
zig build-exe structured_logging.zig --dep zlog --mod zlog:../src/root.zig -Denable_json=true
./structured_logging
```

**Demonstrates:**
- JSON format output
- Structured fields (user data, HTTP requests, database queries)
- Type-safe field values
- Queryable log output

---

### File Rotation (`file_rotation.zig`)

Automatic log file rotation and backup management.

**Run:**
```bash
zig build-exe file_rotation.zig --dep zlog --mod zlog:../src/root.zig -Denable_file_targets=true
./file_rotation
```

**Demonstrates:**
- File output configuration
- Automatic rotation based on file size
- Backup file management
- High-volume logging

**Output:**
- `app.log` - Current log file
- `app.log.0`, `app.log.1`, ... - Rotated backups

---

### Async Logging (`async_logging.zig`)

Non-blocking high-performance logging.

**Run:**
```bash
zig build-exe async_logging.zig --dep zlog --mod zlog:../src/root.zig -Denable_file_targets=true -Denable_async=true
./async_logging
```

**Demonstrates:**
- Async vs synchronous performance comparison
- Non-blocking log calls
- Background thread processing
- Benchmark measurements

---

### Configuration from File (`config_example.zig`)

Load logger configuration from JSON files.

**Run:**
```bash
zig build-exe config_example.zig --dep zlog --mod zlog:../src/root.zig
./config_example
```

**Demonstrates:**
- JSON configuration loading
- Hot-reload capabilities
- Environment variable overrides
- Configuration validation

---

### Metrics and Monitoring (`metrics_example.zig`)

Built-in performance metrics and health checks.

**Run:**
```bash
zig build-exe metrics_example.zig --dep zlog --mod zlog:../src/root.zig -Denable_metrics=true
./metrics_example
```

**Demonstrates:**
- Metrics collection
- Performance monitoring
- Health check reporting
- Prometheus export

---

### Network Logging (`network_example.zig`)

Send logs over the network (TCP, UDP, HTTP, Syslog).

**Run:**
```bash
zig build-exe network_example.zig --dep zlog --mod zlog:../src/root.zig -Denable_network_targets=true
./network_example
```

**Demonstrates:**
- Syslog protocol support
- TCP/UDP logging
- HTTP endpoints
- Remote log shipping

---

## Running All Examples

Use the provided script to run all examples:

```bash
# From project root
zig build examples
```

Or run individually from this directory:

```bash
zig build-exe basic_usage.zig --dep zlog --mod zlog:../src/root.zig
./basic_usage
```

---

## Build Options

Enable specific features when building examples:

```bash
# Enable JSON format
zig build-exe example.zig -Denable_json=true

# Enable file targets
zig build-exe example.zig -Denable_file_targets=true

# Enable async I/O
zig build-exe example.zig -Denable_async=true

# Enable network targets
zig build-exe example.zig -Denable_network_targets=true

# Enable all features
zig build-exe example.zig \
  -Denable_json=true \
  -Denable_file_targets=true \
  -Denable_binary_format=true \
  -Denable_async=true \
  -Denable_aggregation=true \
  -Denable_network_targets=true \
  -Denable_metrics=true
```

---

## Common Patterns

### Web Server Logging

```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .json,
    .output_target = .file,
    .file_path = "/var/log/app/access.log",
    .max_file_size = 100 * 1024 * 1024,
    .async_io = true,
});

const fields = [_]zlog.Field{
    .{ .key = "method", .value = .{ .string = "GET" } },
    .{ .key = "path", .value = .{ .string = "/api/users" } },
    .{ .key = "status", .value = .{ .uint = 200 } },
    .{ .key = "duration_ms", .value = .{ .float = 45.2 } },
};
logger.logWithFields(.info, "Request", &fields);
```

### Error Tracking

```zig
logger.err("Database connection failed: {s}", .{@errorName(err)});

const error_fields = [_]zlog.Field{
    .{ .key = "error", .value = .{ .string = @errorName(err) } },
    .{ .key = "retry_count", .value = .{ .uint = retry_count } },
    .{ .key = "connection_string", .value = .{ .string = conn_str } },
};
logger.logWithFields(.err, "Connection error", &error_fields);
```

### Performance Monitoring

```zig
const start = std.time.nanoTimestamp();
// ... operation ...
const duration = std.time.nanoTimestamp() - start;

const perf_fields = [_]zlog.Field{
    .{ .key = "operation", .value = .{ .string = "database_query" } },
    .{ .key = "duration_ns", .value = .{ .uint = @intCast(duration) } },
    .{ .key = "rows", .value = .{ .uint = row_count } },
};
logger.logWithFields(.info, "Performance", &perf_fields);
```

---

## More Information

- [API Reference](../docs/API.md)
- [Performance Guide](../docs/PERFORMANCE.md)
- [Migration Guide](../docs/MIGRATION.md)
