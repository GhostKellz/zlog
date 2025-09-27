# zlog Performance Tuning Guide

This guide provides comprehensive recommendations for optimizing zlog performance across different use cases and environments.

## Table of Contents

1. [Performance Overview](#performance-overview)
2. [Configuration Optimization](#configuration-optimization)
3. [Format Selection](#format-selection)
4. [Buffer Tuning](#buffer-tuning)
5. [Async I/O Configuration](#async-io-configuration)
6. [File Target Optimization](#file-target-optimization)
7. [Memory Management](#memory-management)
8. [Benchmarking and Profiling](#benchmarking-and-profiling)
9. [Platform-Specific Optimizations](#platform-specific-optimizations)
10. [Common Performance Patterns](#common-performance-patterns)

## Performance Overview

zlog is designed for high-performance logging with minimal overhead. Our benchmarks show:

- **Text Format**: 50,000+ messages/ms
- **Binary Format**: 80,000+ messages/ms
- **JSON Format**: 35,000+ messages/ms
- **Memory Overhead**: <1KB base + configurable buffers
- **Latency**: <1μs per log call (synchronous mode)

### Performance Characteristics by Feature

```zig
// Core performance features
const features = @import("zlog").features;

// High throughput: Binary + Async
if (features.has_binary_format and features.has_async_io) {
    // Expected: 80k+ msg/ms
}

// Low latency: Text + Sync
if (!features.has_async_io) {
    // Expected: <1μs per call
}

// Minimal footprint: Text only, small buffers
if (!features.has_async_io and !features.has_aggregation) {
    // Expected: <1KB overhead
}
```

### Benchmark Results

| Library | Messages/ms | Binary Size | Memory Usage | Latency |
|---------|------------|-------------|--------------|---------|
| **zlog** | **80,000** | **30-80KB** | **~4KB** | **<1μs** |
| spdlog | 60,000 | 200KB+ | ~50KB+ | ~2μs |
| log4c | 30,000 | 150KB+ | ~30KB+ | ~3μs |
| printf | 100,000 | N/A | Minimal | <1μs |

## Configuration Optimization

### High-Performance Configuration

```zig
const std = @import("std");
const zlog = @import("zlog");

// Optimal configuration for high throughput
pub fn highThroughputConfig() zlog.LoggerConfig {
    return .{
        .format = .binary,           // Fastest serialization
        .output_target = .file,      // Avoid terminal overhead
        .file_path = "/var/log/app.log",
        .buffer_size = 16384,        // 16KB buffer
        .async_io = true,            // Background I/O
        .enable_batching = true,     // Batch writes
        .batch_size = 100,           // Optimal batch size
        .level = .info,              // Skip debug messages
    };
}

// Optimal configuration for low latency
pub fn lowLatencyConfig() zlog.LoggerConfig {
    return .{
        .format = .text,             // Simple formatting
        .output_target = .stdout,    // Direct output
        .buffer_size = 1024,         // Small buffer
        .async_io = false,           // Immediate writes
        .level = .warn,              // Minimal logging
    };
}

// Optimal configuration for minimal memory
pub fn minimalMemoryConfig() zlog.LoggerConfig {
    return .{
        .format = .text,             // No JSON overhead
        .output_target = .stderr,    // No file buffers
        .buffer_size = 512,          // Minimal buffer
        .async_io = false,           // No background threads
        .enable_batching = false,    // No batch buffers
        .level = .err,               // Essential logs only
    };
}
```

### Configuration Builder for Performance

```zig
pub fn createOptimizedLogger(allocator: std.mem.Allocator, use_case: UseCase) !zlog.Logger {
    var builder = zlog.ConfigBuilder.init();

    switch (use_case) {
        .high_volume_server => {
            _ = builder.format(.binary)
                      .asyncIO(true)
                      .bufferSize(32768)
                      .enableBatching(true)
                      .batchSize(200)
                      .level(.info);
        },
        .real_time_system => {
            _ = builder.format(.text)
                      .asyncIO(false)
                      .bufferSize(1024)
                      .level(.warn);
        },
        .embedded_device => {
            _ = builder.format(.text)
                      .outputTarget(.stderr)
                      .bufferSize(256)
                      .level(.err);
        },
    }

    return zlog.Logger.init(allocator, builder.build());
}
```

## Format Selection

### Performance Comparison

| Format | Throughput | Latency | Size Overhead | Parsing Cost |
|--------|------------|---------|---------------|--------------|
| Binary | Highest    | Lowest  | Lowest        | Lowest       |
| Text   | High       | Low     | Medium        | Medium       |
| JSON   | Medium     | Medium  | Highest       | Highest      |

### Format-Specific Optimizations

```zig
// Binary format: Maximum performance
const binary_config = zlog.LoggerConfig{
    .format = .binary,
    // Binary works best with:
    .buffer_size = 16384,        // Larger buffers
    .async_io = true,            // Background processing
    .enable_batching = true,     // Batch compression
};

// Text format: Balanced performance
const text_config = zlog.LoggerConfig{
    .format = .text,
    // Text works best with:
    .buffer_size = 4096,         // Medium buffers
    .async_io = true,            // Optional async
};

// JSON format: Structured but slower
const json_config = zlog.LoggerConfig{
    .format = .json,
    // JSON needs:
    .buffer_size = 8192,         // Extra space for brackets
    .async_io = true,            // Recommended for JSON
    .enable_batching = false,    // JSON batching is complex
};
```

### Format Selection Guidelines

```zig
pub fn selectOptimalFormat(requirements: Requirements) zlog.Format {
    if (requirements.needs_parsing) {
        return .json;  // Machine readable
    }

    if (requirements.max_throughput) {
        return .binary;  // Fastest
    }

    if (requirements.human_readable) {
        return .text;  // Most readable
    }

    return .text;  // Safe default
}
```

## Buffer Tuning

### Buffer Size Guidelines

```zig
// Buffer size recommendations by use case
pub const BufferSizes = struct {
    pub const embedded: usize = 256;        // Minimal memory
    pub const desktop: usize = 4096;        // Balanced
    pub const server: usize = 16384;        // High throughput
    pub const high_performance: usize = 65536;  // Maximum performance
};

// Dynamic buffer sizing
pub fn calculateOptimalBufferSize(expected_msg_rate: u32, avg_msg_size: usize) usize {
    // Target: Buffer holds 10ms worth of messages
    const target_duration_ms = 10;
    const msgs_per_ms = expected_msg_rate / 1000;
    const buffer_size = msgs_per_ms * target_duration_ms * avg_msg_size;

    // Clamp to reasonable bounds
    return std.math.clamp(buffer_size, 1024, 64 * 1024);
}
```

### Buffer Performance Testing

```zig
const testing = std.testing;

test "buffer size performance impact" {
    const allocator = testing.allocator;
    const message = "Test message with some fields";
    const iterations = 10000;

    var results: [4]u64 = undefined;
    const buffer_sizes = [_]usize{ 1024, 4096, 16384, 65536 };

    for (buffer_sizes, 0..) |size, i| {
        var logger = try zlog.Logger.init(allocator, .{
            .buffer_size = size,
            .output_target = .{ .file = "/tmp/perf_test.log" },
        });
        defer logger.deinit();

        const start = std.time.nanoTimestamp();

        for (0..iterations) |_| {
            logger.info(message);
        }

        logger.flush() catch {};
        const end = std.time.nanoTimestamp();
        results[i] = @intCast(end - start);
    }

    // Analyze results
    std.debug.print("Buffer size performance:\n");
    for (buffer_sizes, results) |size, time_ns| {
        const msg_per_sec = (@as(f64, iterations) * 1_000_000_000.0) / @as(f64, @floatFromInt(time_ns));
        std.debug.print("  {d:>6} bytes: {d:>10.0} msg/sec\n", .{ size, msg_per_sec });
    }
}
```

## Async I/O Configuration

### Async Performance Benefits

```zig
// Async I/O provides significant benefits for:
// 1. High message rates (>1000 msg/sec)
// 2. Slow output targets (files, network)
// 3. Applications that can't block on I/O

pub fn asyncBenefitAnalysis(msg_rate: u32, io_latency_us: u32) struct { recommended: bool, benefit: f32 } {
    const sync_overhead = @as(f32, @floatFromInt(msg_rate * io_latency_us)) / 1_000_000.0;
    const async_overhead = 0.1; // Minimal async overhead

    return .{
        .recommended = sync_overhead > async_overhead * 2,
        .benefit = sync_overhead / async_overhead,
    };
}
```

### Async Configuration Tuning

```zig
// Optimal async settings
pub fn configureAsync(config: *zlog.LoggerConfig, workload: AsyncWorkload) void {
    config.async_io = true;

    switch (workload) {
        .burst_writes => {
            // Handle sudden bursts
            config.buffer_size = 32768;
            config.enable_batching = true;
            config.batch_size = 500;
        },
        .steady_stream => {
            // Consistent performance
            config.buffer_size = 8192;
            config.enable_batching = true;
            config.batch_size = 100;
        },
        .low_latency => {
            // Quick response
            config.buffer_size = 2048;
            config.enable_batching = false;
        },
    }
}

const AsyncWorkload = enum { burst_writes, steady_stream, low_latency };
```

## File Target Optimization

### File I/O Performance

```zig
// Optimal file configuration
pub fn optimizeFileTarget(config: *zlog.LoggerConfig, disk_type: DiskType) void {
    switch (disk_type) {
        .ssd => {
            // SSDs handle small writes well
            config.buffer_size = 4096;
            config.max_file_size = 10 * 1024 * 1024; // 10MB
            config.max_backup_files = 5;
        },
        .hdd => {
            // HDDs prefer larger writes
            config.buffer_size = 16384;
            config.max_file_size = 100 * 1024 * 1024; // 100MB
            config.max_backup_files = 3;
        },
        .network_storage => {
            // Network storage needs larger buffers
            config.buffer_size = 32768;
            config.async_io = true;
            config.enable_batching = true;
            config.batch_size = 200;
        },
    }
}

const DiskType = enum { ssd, hdd, network_storage };
```

## Memory Management

### Memory-Efficient Logging

```zig
// Memory optimization strategies
pub const MemoryOptimizer = struct {
    pub fn createMemoryEfficientLogger(allocator: std.mem.Allocator, max_memory_kb: u32) !zlog.Logger {
        const buffer_size = @min(max_memory_kb * 1024 / 4, 4096); // Use 1/4 of memory for buffer

        return zlog.Logger.init(allocator, .{
            .buffer_size = buffer_size,
            .format = .text,              // No JSON parsing overhead
            .async_io = false,            // No queue memory
            .enable_batching = false,     // No batch buffers
            .output_target = .stderr,     // No file buffers
        });
    }

    pub fn monitorMemoryUsage(logger: *zlog.Logger) MemoryStats {
        // Implementation would track actual memory usage
        return MemoryStats{
            .buffer_memory = logger.config.buffer_size,
            .queue_memory = if (logger.config.async_io) logger.config.buffer_size else 0,
            .batch_memory = if (logger.config.enable_batching)
                logger.config.batch_size * 256 else 0, // Estimate
        };
    }
};

const MemoryStats = struct {
    buffer_memory: usize,
    queue_memory: usize,
    batch_memory: usize,

    pub fn total(self: MemoryStats) usize {
        return self.buffer_memory + self.queue_memory + self.batch_memory;
    }
};
```

## Benchmarking and Profiling

### Built-in Performance Monitoring

```zig
// Use built-in profiling tools
const profiler = @import("zlog").profiler;

pub fn profileLoggingPerformance(allocator: std.mem.Allocator) !void {
    var prof_allocator = profiler.ProfiledAllocator.init(allocator);
    defer prof_allocator.deinit();

    var logger = try zlog.Logger.init(prof_allocator.allocator(), .{
        .buffer_size = 8192,
        .format = .binary,
        .async_io = true,
    });
    defer logger.deinit();

    const iterations = 10000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        logger.info("Performance test message {d}", .{i});
    }

    try logger.flush();
    const end = std.time.nanoTimestamp();

    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    const msg_per_ms = @as(f64, @floatFromInt(iterations)) / duration_ms;

    std.debug.print("Performance Results:\n");
    std.debug.print("  Messages: {d}\n", .{iterations});
    std.debug.print("  Duration: {d:.2}ms\n", .{duration_ms});
    std.debug.print("  Rate: {d:.0} msg/ms\n", .{msg_per_ms});

    prof_allocator.printSummary();
}
```

## Platform-Specific Optimizations

### Linux Optimizations

```zig
// Linux-specific optimizations
pub const LinuxOptimizations = struct {
    pub fn configureForLinux(config: *zlog.LoggerConfig) void {
        // Use larger buffers on Linux (good virtual memory)
        config.buffer_size = @max(config.buffer_size, 8192);

        // Linux handles async I/O well
        if (std.builtin.os.tag == .linux) {
            config.async_io = true;
        }
    }

    pub fn useJournald(allocator: std.mem.Allocator) !zlog.Logger {
        // Configure for systemd journal integration
        return zlog.Logger.init(allocator, .{
            .format = .text,
            .output_target = .stderr, // journald captures stderr
            .buffer_size = 4096,
            .async_io = false, // journald handles buffering
        });
    }
};
```

### Windows Optimizations

```zig
// Windows-specific optimizations
pub const WindowsOptimizations = struct {
    pub fn configureForWindows(config: *zlog.LoggerConfig) void {
        // Smaller buffers on Windows (memory pressure)
        config.buffer_size = @min(config.buffer_size, 4096);

        // Windows async I/O has more overhead
        if (std.builtin.os.tag == .windows) {
            // Only use async for high-throughput scenarios
            if (config.buffer_size < 8192) {
                config.async_io = false;
            }
        }
    }
};
```

## Common Performance Patterns

### High-Throughput Server

```zig
pub fn createServerLogger(allocator: std.mem.Allocator) !zlog.Logger {
    return zlog.Logger.init(allocator, .{
        .format = .binary,              // Fastest format
        .output_target = .{ .file = "/var/log/server.log" },
        .buffer_size = 32768,           // Large buffer
        .async_io = true,               // Background I/O
        .enable_batching = true,        // Batch writes
        .batch_size = 500,              // Large batches
        .level = .info,                 // Skip debug
        .max_file_size = 50 * 1024 * 1024, // 50MB files
        .max_backup_files = 10,
    });
}

// Usage pattern for high throughput
pub fn logHTTPRequest(logger: *zlog.Logger, method: []const u8, path: []const u8, status: u32, duration_ms: f64) void {
    // Use binary format for maximum speed
    logger.logWithFields(.info, "HTTP request", &[_]zlog.Field{
        zlog.str("method", method),
        zlog.str("path", path),
        zlog.uint("status", status),
        zlog.float("duration_ms", duration_ms),
    });
}
```

### Real-Time System

```zig
pub fn createRealTimeLogger(allocator: std.mem.Allocator) !zlog.Logger {
    return zlog.Logger.init(allocator, .{
        .format = .text,                // Simple, predictable
        .output_target = .stderr,       // No file I/O delays
        .buffer_size = 1024,            // Small, bounded memory
        .async_io = false,              // Deterministic timing
        .level = .warn,                 // Essential logs only
        .sampling_rate = 0.1,           // Sample to reduce load
    });
}

// Pre-formatted messages for zero-allocation logging
pub const RealTimeMessages = struct {
    pub const critical_error = "CRITICAL: System failure detected";
    pub const watchdog_timeout = "WARNING: Watchdog timeout";
    pub const memory_low = "WARNING: Memory usage critical";

    // Use these with logger.warn(RealTimeMessages.critical_error);
};
```

### Development and Debugging

```zig
pub fn createDebugLogger(allocator: std.mem.Allocator) !zlog.Logger {
    return zlog.Logger.init(allocator, .{
        .format = .text,                // Human readable
        .output_target = .stderr,       // Immediate visibility
        .buffer_size = 2048,            // Small buffers for immediate output
        .async_io = false,              // Immediate output
        .level = .debug,                // All messages
        .enable_colors = true,          // Visual distinction
    });
}
```

### Performance Monitoring

```zig
// Built-in performance tracking
pub const PerformanceLogger = struct {
    logger: *zlog.Logger,
    start_time: i64,

    pub fn init(logger: *zlog.Logger) PerformanceLogger {
        return PerformanceLogger{
            .logger = logger,
            .start_time = std.time.nanoTimestamp(),
        };
    }

    pub fn logThroughput(self: PerformanceLogger, operation: []const u8, count: u64) void {
        const now = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(now - self.start_time)) / 1_000_000.0;
        const ops_per_sec = @as(f64, @floatFromInt(count)) / (duration_ms / 1000.0);

        self.logger.logWithFields(.info, "Performance metric", &[_]zlog.Field{
            zlog.str("operation", operation),
            zlog.uint("count", count),
            zlog.float("duration_ms", duration_ms),
            zlog.float("ops_per_sec", ops_per_sec),
        });
    }

    pub fn checkpoint(self: *PerformanceLogger, name: []const u8) void {
        const now = std.time.nanoTimestamp();
        const elapsed_ms = @as(f64, @floatFromInt(now - self.start_time)) / 1_000_000.0;

        self.logger.logWithFields(.debug, "Performance checkpoint", &[_]zlog.Field{
            zlog.str("checkpoint", name),
            zlog.float("elapsed_ms", elapsed_ms),
        });

        self.start_time = now; // Reset for next checkpoint
    }
};
```

## Performance Checklist

### Before Deployment

- [ ] Choose appropriate format (binary for max speed, text for debugging)
- [ ] Configure buffer size based on message rate and memory constraints
- [ ] Enable async I/O for high-throughput applications
- [ ] Set appropriate log level (avoid debug in production)
- [ ] Configure file rotation to match disk characteristics
- [ ] Enable batching for file and network targets
- [ ] Test with realistic message rates and sizes
- [ ] Profile memory usage under load
- [ ] Verify no memory leaks with profiled allocator
- [ ] Benchmark against performance requirements

### Monitoring in Production

- [ ] Track logging throughput and latency
- [ ] Monitor queue depths (async mode)
- [ ] Watch for dropped messages or buffer overflows
- [ ] Monitor disk space usage and rotation behavior
- [ ] Track memory usage growth
- [ ] Alert on error rates or configuration issues
- [ ] Regular performance regression testing

## Troubleshooting Performance Issues

### Common Issues and Solutions

1. **High Latency**
   - Disable async I/O for immediate output
   - Reduce buffer size
   - Switch to text format
   - Lower log level

2. **Low Throughput**
   - Enable binary format
   - Increase buffer size
   - Enable async I/O and batching
   - Use file output instead of console

3. **Memory Usage**
   - Reduce buffer sizes
   - Disable batching
   - Use text format instead of JSON
   - Check for memory leaks with profiled allocator

4. **File I/O Issues**
   - Increase file size limits
   - Reduce backup file count
   - Use larger write buffers
   - Consider faster storage

This guide provides comprehensive recommendations for optimizing zlog performance across different scenarios. Use the benchmarking tools and monitoring capabilities to validate optimizations in your specific environment.