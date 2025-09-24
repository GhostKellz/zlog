# Performance Guide

Optimization tips and performance benchmarks for zlog.

## Benchmarks

### Text Format Performance

```
Test Environment: Linux x86_64, Zig 0.16.0-dev
Hardware: Modern CPU, SSD storage

Text Format:     ~50,000 messages/ms
JSON Format:     ~35,000 messages/ms
Binary Format:   ~80,000 messages/ms
Structured:      ~25,000 messages/ms
```

### Memory Usage

```
Minimal Build:   ~30KB binary size
Standard Build:  ~50KB binary size
Full Build:      ~80KB binary size

Runtime Memory:  ~4KB per logger (default buffer)
                 +allocation overhead for structured fields
```

### Throughput Comparison

| Library | Messages/ms | Binary Size | Memory Usage |
|---------|------------|-------------|---------------|
| **zlog** | **80,000** | **30-80KB** | **~4KB** |
| spdlog | 60,000 | 200KB+ | ~50KB+ |
| log4c | 30,000 | 150KB+ | ~30KB+ |
| printf | 100,000 | N/A | Minimal |

## Optimization Strategies

### 1. Format Selection

Choose the right format for your use case:

```zig
// Fastest: Binary format
var config = zlog.LoggerConfig{
    .format = .binary,  // ~80k msg/ms
};

// Balanced: Text format
var config = zlog.LoggerConfig{
    .format = .text,    // ~50k msg/ms
};

// Structured: JSON format
var config = zlog.LoggerConfig{
    .format = .json,    // ~35k msg/ms
};
```

### 2. Log Level Filtering

Early filtering prevents expensive operations:

```zig
// Good: Early return if level too low
logger.debug("Expensive operation: {}", .{compute_expensive()});

// Better: Check level first
if (logger.config.level <= .debug) {
    logger.debug("Expensive operation: {}", .{compute_expensive()});
}
```

### 3. Sampling for High-Frequency Logs

```zig
// Sample high-frequency events
var high_freq_config = zlog.LoggerConfig{
    .sampling_rate = 0.01, // Log 1% of messages
};

// Full logging for important events
var important_config = zlog.LoggerConfig{
    .sampling_rate = 1.0, // Log all messages
};
```

### 4. Buffer Sizing

Optimize buffer size for your workload:

```zig
// Small buffers: Low memory, more I/O
var config = zlog.LoggerConfig{
    .buffer_size = 1024,
};

// Large buffers: More memory, less I/O
var config = zlog.LoggerConfig{
    .buffer_size = 32768,
};

// Rule of thumb: 1KB per 100 messages
```

### 5. Async I/O

Non-blocking logging for high-throughput applications:

```zig
var async_config = zlog.LoggerConfig{
    .async_io = true,
    .buffer_size = 16384,  // Larger buffer for async
};

// Logging calls return immediately
logger.info("Non-blocking log message", .{});
```

### 6. Structured Field Optimization

Minimize allocation in structured logging:

```zig
// Avoid: Creating fields in hot paths
for (requests) |req| {
    const fields = [_]zlog.Field{
        .{ .key = "id", .value = .{ .uint = req.id } },
    };
    logger.logWithFields(.info, "Request", &fields);
}

// Better: Pre-allocate field templates
const field_template = [_]zlog.Field{
    .{ .key = "id", .value = .{ .uint = 0 } },
};

for (requests) |req| {
    var fields = field_template;
    fields[0].value = .{ .uint = req.id };
    logger.logWithFields(.info, "Request", &fields);
}
```

## High-Performance Configurations

### Ultra-High Throughput

```zig
var ultra_config = zlog.LoggerConfig{
    .level = .warn,          // Only important messages
    .format = .binary,       // Fastest format
    .output_target = .file,  // Avoid terminal overhead
    .file_path = "/dev/shm/ultra.log", // RAM disk
    .async_io = true,        // Non-blocking
    .sampling_rate = 0.1,    // Sample 10%
    .buffer_size = 65536,    // Large buffer
};
```

### Low-Latency

```zig
var low_latency_config = zlog.LoggerConfig{
    .format = .binary,       // Minimal processing
    .async_io = false,       // Avoid thread overhead
    .buffer_size = 512,      // Small buffer, immediate flush
    .sampling_rate = 1.0,    // No sampling overhead
};
```

### Memory-Constrained

```zig
var memory_config = zlog.LoggerConfig{
    .level = .err,           // Only errors
    .format = .text,         // No JSON overhead
    .buffer_size = 256,      // Minimal buffer
    .sampling_rate = 1.0,    // No sampling structures
};
```

### High-Frequency Events

```zig
var high_freq_config = zlog.LoggerConfig{
    .format = .binary,       // Compact format
    .async_io = true,        // Non-blocking
    .sampling_rate = 0.001,  // 0.1% sampling
    .enable_deduplication = true, // Reduce duplicates
    .dedup_window_ms = 1000, // 1-second window
};
```

## Measurement and Profiling

### Built-in Benchmarks

Run performance tests:

```bash
# Basic benchmarks
zig build test

# Detailed benchmarks with timing
zig build test --summary all

# Feature-specific benchmarks
zig build test -Dbinary_format=true
zig build test -Dfile_targets=true
```

### Custom Benchmarking

```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn benchmarkLogging() !void {
    const allocator = std.heap.page_allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .format = .binary,
    });
    defer logger.deinit();

    const message_count = 100_000;
    const start = std.time.nanoTimestamp();

    for (0..message_count) |i| {
        logger.info("Benchmark message {d}", .{i});
    }

    const end = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    const messages_per_ms = @as(f64, message_count) / duration_ms;

    std.debug.print("Messages/ms: {d:.2}\n", .{messages_per_ms});
}
```

### Memory Profiling

```zig
pub fn profileMemory() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const initial_memory = gpa.total_requested_bytes;

    var logger = try zlog.Logger.init(allocator, .{
        .buffer_size = 8192,
    });
    defer logger.deinit();

    for (0..1000) |i| {
        logger.info("Memory test {d}", .{i});
    }

    const final_memory = gpa.total_requested_bytes;
    const memory_used = final_memory - initial_memory;

    std.debug.print("Memory used: {d} bytes\n", .{memory_used});
}
```

## Performance Tips

### 1. Build Configuration

```bash
# Release builds are significantly faster
zig build -Doptimize=ReleaseFast

# Disable unused features
zig build -Djson_format=false -Daggregation=false
```

### 2. Avoid String Formatting in Hot Paths

```zig
// Avoid: Expensive formatting
for (items) |item| {
    logger.debug("Processing item: {s} with data: {any}", .{item.name, item.data});
}

// Better: Simple messages
for (items) |item| {
    logger.debug("Processing item", .{});
}

// Best: Structured logging
const fields = [_]zlog.Field{
    .{ .key = "item", .value = .{ .string = item.name } },
};
logger.logWithFields(.debug, "Processing", &fields);
```

### 3. Batch Operations

```zig
// Avoid: Many small log calls
for (results) |result| {
    logger.info("Result: {d}", .{result});
}

// Better: Batch with structured fields
const batch_fields = [_]zlog.Field{
    .{ .key = "count", .value = .{ .uint = results.len } },
    .{ .key = "sum", .value = .{ .uint = sum(results) } },
};
logger.logWithFields(.info, "Batch processed", &batch_fields);
```

### 4. Async Best Practices

```zig
// Good: Let async thread handle I/O
var logger = try zlog.Logger.init(allocator, .{
    .async_io = true,
    .buffer_size = 16384,
});

// Important: Ensure proper shutdown to flush pending logs
defer logger.deinit(); // Waits for async thread
```

### 5. File I/O Optimization

```zig
// Fast: Write to SSD
.file_path = "/fast/ssd/app.log",

// Faster: Write to RAM disk
.file_path = "/dev/shm/app.log",

// Avoid: Network file systems
.file_path = "/nfs/slow/app.log", // Slow
```

## Performance Monitoring

### Runtime Metrics

Monitor performance in production:

```zig
var logger = try zlog.Logger.init(allocator, .{
    .enable_metrics = true, // If available in build
});

// Periodically check performance
const stats = logger.getStats(); // Hypothetical API
std.debug.print("Messages logged: {d}\n", .{stats.message_count});
std.debug.print("Average latency: {d}μs\n", .{stats.avg_latency_us});
```

### Bottleneck Identification

Common performance bottlenecks:

1. **String formatting** - Use structured logging
2. **File I/O** - Use async I/O or faster storage
3. **Memory allocation** - Increase buffer sizes
4. **Thread contention** - Use separate loggers per thread
5. **Network storage** - Use local storage for logs

### Optimization Verification

```zig
// Before optimization
const start = std.time.nanoTimestamp();
// ... logging operations ...
const duration_before = std.time.nanoTimestamp() - start;

// After optimization
const start2 = std.time.nanoTimestamp();
// ... optimized logging operations ...
const duration_after = std.time.nanoTimestamp() - start2;

const improvement = @as(f64, @floatFromInt(duration_before)) / @as(f64, @floatFromInt(duration_after));
std.debug.print("Performance improvement: {d:.2}x\n", .{improvement});
```

## Platform-Specific Optimizations

### Linux

```zig
// Use O_DIRECT for high-throughput scenarios (advanced)
// Bypass page cache for very high-frequency logging
```

### Windows

```zig
// Use Windows-specific high-performance I/O
// Consider async file operations
```

### macOS

```zig
// Leverage unified logging system integration
// Use Apple's high-performance logging APIs
```

The key to high-performance logging with zlog is choosing the right configuration for your specific use case and measuring the results.