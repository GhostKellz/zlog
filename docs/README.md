# zlog Documentation

Welcome to the comprehensive documentation for zlog - a high-performance structured logging library for Zig.

## Quick Navigation

- **[API Reference](api.md)** - Complete API documentation
- **[Configuration Guide](configuration.md)** - Detailed configuration options
- **[Performance Guide](performance.md)** - Optimization tips and benchmarks
- **[Examples](examples.md)** - Practical usage examples
- **[Migration Guide](migration.md)** - Migrating from other logging libraries

## Overview

zlog is designed to replace heavy C logging libraries like `spdlog`, `log4c`, and `rsyslog` with a modern, high-performance Zig implementation. It provides:

- **Zero-allocation fast paths** for disabled features
- **Modular architecture** - enable only what you need
- **Multiple output formats** - text, JSON, binary
- **Thread-safe concurrent logging**
- **Async I/O** with background processing
- **File rotation** with configurable retention
- **Structured logging** with type-safe fields
- **Log aggregation** and sampling capabilities

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Application   │───▶│      zlog        │───▶│     Output      │
│                 │    │                  │    │                 │
│ • Log calls     │    │ • Format         │    │ • stdout/stderr │
│ • Structured    │    │ • Filter         │    │ • Files         │
│   fields        │    │ • Buffer         │    │ • Network       │
│ • Error msgs    │    │ • Rotate         │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Core Components

1. **Logger** - Main logging interface
2. **Formatters** - Text, JSON, and binary output
3. **Targets** - File, stdout, stderr outputs
4. **Async Worker** - Background processing thread
5. **Rotation Manager** - File rotation and cleanup
6. **Aggregation Engine** - Batching and deduplication

## Quick Start

1. **Installation**
   ```bash
   zig fetch --save https://github.com/ghostkellz/zlog/archive/refs/heads/main.tar.gz
   ```

2. **Basic Usage**
   ```zig
   const zlog = @import("zlog");

   pub fn main() !void {
       var gpa = std.heap.GeneralPurposeAllocator(.{}){};
       defer _ = gpa.deinit();
       const allocator = gpa.allocator();

       var logger = try zlog.Logger.init(allocator, .{});
       defer logger.deinit();

       logger.info("Hello, zlog!", .{});
   }
   ```

3. **Structured Logging**
   ```zig
   const fields = [_]zlog.Field{
       .{ .key = "user_id", .value = .{ .uint = 12345 } },
       .{ .key = "action", .value = .{ .string = "login" } },
   };
   logger.logWithFields(.info, "User action", &fields);
   ```

## Build Options

zlog uses compile-time flags to enable/disable features:

```bash
# Minimal build (~30KB)
zig build -Djson_format=false -Dfile_targets=false -Dbinary_format=false

# Production build (~50KB)
zig build -Dfile_targets=true

# Full-featured build (~80KB)
zig build -Djson_format=true -Dfile_targets=true -Dbinary_format=true -Daggregation=true -Dasync_io=true
```

## Performance Characteristics

| Configuration | Throughput | Binary Size | Use Case |
|---------------|------------|-------------|----------|
| Minimal text | ~50k msg/ms | ~30KB | Simple CLI apps |
| JSON structured | ~35k msg/ms | ~50KB | Web services |
| Binary async | ~80k msg/ms | ~80KB | High-performance systems |

## Feature Matrix

| Feature | Available | Build Flag | Description |
|---------|-----------|------------|-------------|
| Text format | Always | N/A | Human-readable output |
| JSON format | Optional | `json_format` | Structured JSON logs |
| Binary format | Optional | `binary_format` | Compact binary encoding |
| File output | Optional | `file_targets` | File logging with rotation |
| Async I/O | Optional | `async_io` | Background processing |
| Aggregation | Optional | `aggregation` | Batching and deduplication |
| Network targets | Optional | `network_targets` | TCP/UDP/HTTP output |
| Metrics | Optional | `metrics` | Performance monitoring |

## Common Use Cases

### 1. CLI Applications
```zig
var logger = try zlog.Logger.init(allocator, .{
    .level = if (verbose) .debug else .info,
    .format = .text,
    .output_target = .stderr,
});
```

### 2. Web Services
```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .json,
    .output_target = .stdout, // For container logging
});
```

### 3. High-Performance Systems
```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .binary,
    .async_io = true,
    .sampling_rate = 0.1, // Sample 10%
    .buffer_size = 32768,
});
```

### 4. Production Services
```zig
var logger = try zlog.Logger.init(allocator, .{
    .level = .info,
    .format = .json,
    .output_target = .file,
    .file_path = "/var/log/app.log",
    .max_file_size = 100 * 1024 * 1024,
    .max_backup_files = 10,
});
```

## Best Practices

1. **Always pair init/deinit**
   ```zig
   var logger = try zlog.Logger.init(allocator, config);
   defer logger.deinit(); // Essential for async loggers
   ```

2. **Use structured logging for searchable logs**
   ```zig
   // Good: Structured fields
   logger.logWithFields(.info, "User login", &fields);

   // Avoid: String interpolation for searchable data
   logger.info("User {s} logged in", .{username});
   ```

3. **Configure appropriate levels for environments**
   ```zig
   const level = if (builtin.mode == .Debug) .debug else .info;
   ```

4. **Use sampling for high-frequency events**
   ```zig
   .sampling_rate = if (production) 0.01 else 1.0,
   ```

5. **Size buffers appropriately**
   ```zig
   .buffer_size = if (high_throughput) 32768 else 4096,
   ```

## Thread Safety

All zlog operations are thread-safe. Multiple threads can safely log to the same logger instance simultaneously. Internal synchronization is handled automatically with minimal overhead.

## Memory Management

zlog manages its own internal buffers and requires only:
- An allocator for initialization
- Proper cleanup with `deinit()`
- Temporary allocations for structured field formatting

Memory usage is predictable and bounded by configuration.

## Error Handling

zlog uses Zig's error handling patterns:

```zig
// Configuration validation
var logger = zlog.Logger.init(allocator, config) catch |err| switch (err) {
    error.FormatNotEnabled => {
        // Handle disabled format
    },
    error.FilePathRequired => {
        // Handle missing file path
    },
    else => return err,
};
```

## Comparison with Alternatives

| Aspect | zlog | spdlog | log4c | std.log |
|--------|------|--------|-------|---------|
| **Performance** | ~80k msg/ms | ~60k msg/ms | ~30k msg/ms | ~20k msg/ms |
| **Binary Size** | 30-80KB | 200KB+ | 150KB+ | Built-in |
| **Memory Safety** | ✅ Zig safety | ❌ C++ unsafe | ❌ C unsafe | ✅ Zig safety |
| **Zero Dependencies** | ✅ | ❌ | ❌ | ✅ |
| **Compile-time Config** | ✅ | ❌ | ❌ | ✅ |
| **Structured Logging** | ✅ | ❌ | ❌ | ❌ |
| **Async I/O** | ✅ | ✅ | ❌ | ❌ |
| **File Rotation** | ✅ | ✅ | ❌ | ❌ |
| **Binary Format** | ✅ | ❌ | ❌ | ❌ |

## Contributing

See the main [README.md](../README.md) for contribution guidelines.

## License

zlog is licensed under the MIT License. See [LICENSE](../LICENSE) for details.

---

For detailed information on any topic, please refer to the specific documentation files linked above.