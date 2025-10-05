# zlog Performance Tuning Guide

Optimize zlog for maximum throughput, minimal latency, or minimal resource usage.

## Table of Contents

- [Performance Characteristics](#performance-characteristics)
- [Choosing the Right Configuration](#choosing-the-right-configuration)
- [Optimization Strategies](#optimization-strategies)
- [Benchmarking](#benchmarking)
- [Common Scenarios](#common-scenarios)

---

## Performance Characteristics

### Default Performance

Out of the box, zlog provides:
- **Text format**: ~50,000+ messages/ms
- **Binary format**: ~80,000+ messages/ms
- **Structured logging**: ~25,000+ messages/ms
- **Async I/O**: Non-blocking with batch processing

### Performance Dimensions

1. **Throughput** - Messages per second
2. **Latency** - Time from log call to write completion
3. **Memory** - RAM usage for buffers and queues
4. **CPU** - Processing overhead
5. **Disk I/O** - Write amplification and efficiency

---

## Choosing the Right Configuration

### High Throughput (Maximize msg/s)

For applications logging at very high rates:

```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .binary,        // Fastest format
    .buffer_size = 65536,     // Large buffer (64KB)
    .async_io = true,         // Non-blocking writes
    .output_target = .file,   // Direct to file
    .enable_batching = true,  // Batch writes
    .batch_size = 500,        // Large batches
});
```

**Expected:** ~100,000+ msg/s

**Key Settings:**
- `format = .binary` - Minimal serialization overhead
- `async_io = true` - Non-blocking, batched writes
- `buffer_size >= 32768` - Reduce flush frequency
- `enable_batching = true` - Aggregate writes

---

### Low Latency (Minimize response time)

For applications where immediate log visibility is critical:

```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .text,          // Direct formatting
    .buffer_size = 1024,      // Small buffer
    .async_io = false,        // Synchronous writes
    .output_target = .stdout, // Direct to console
});
```

**Expected:** <100µs per log call

**Key Settings:**
- `async_io = false` - Immediate writes
- `buffer_size = 1024-4096` - Frequent flushes
- `output_target = .stdout/.stderr` - No file overhead
- `sampling_rate = 1.0` - No sampling delay

---

### Minimal Memory (Reduce footprint)

For constrained environments:

```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .text,          // No extra encoding buffers
    .buffer_size = 512,       // Minimal buffer
    .async_io = false,        // No queue overhead
    .sampling_rate = 0.1,     // Sample 10% of logs
});
```

**Expected:** <1KB memory overhead

**Key Settings:**
- `buffer_size = 256-1024` - Minimal allocation
- `async_io = false` - No queue memory
- `enable_batching = false` - No batch buffers
- `sampling_rate < 1.0` - Reduce volume

---

### Balanced (General purpose)

Recommended for most applications:

```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .json,          // Structured but efficient
    .buffer_size = 8192,      // Good balance
    .async_io = true,         // Async for non-critical
    .output_target = .file,   // File with rotation
    .max_file_size = 10 * 1024 * 1024,
});
```

**Expected:** 40,000+ msg/s, <1ms latency

---

## Optimization Strategies

### 1. Format Selection

**Binary Format** (Fastest)
```zig
.format = .binary
```
- **Pros:** 60-80% faster than text, minimal CPU
- **Cons:** Not human-readable, needs decoder
- **Use when:** Maximum performance required

**JSON Format** (Structured)
```zig
.format = .json
```
- **Pros:** Structured, parseable, widely supported
- **Cons:** 20-30% slower than text
- **Use when:** Log aggregation/analysis needed

**Text Format** (Readable)
```zig
.format = .text
```
- **Pros:** Human-readable, debuggable, always available
- **Cons:** Not structured
- **Use when:** Interactive debugging, simple apps

---

### 2. Buffer Size Tuning

Buffer size directly impacts flush frequency:

```zig
// Small buffer (256-1024 bytes): Low latency, more flushes
.buffer_size = 512,

// Medium buffer (4096-8192 bytes): Balanced
.buffer_size = 4096,

// Large buffer (16384-65536 bytes): High throughput, fewer flushes
.buffer_size = 32768,
```

**Formula:**
```
Optimal buffer size ≈ Avg message size × Flush batch size
```

**Example:**
- Average message: 128 bytes
- Want to batch 100 messages
- Optimal buffer: 128 × 100 = 12,800 bytes

---

### 3. Async I/O Configuration

Enable async I/O for high-volume logging:

```zig
.async_io = true,
.buffer_size = 16384,  // Larger buffer for async
```

**Benefits:**
- Log calls return immediately (~microseconds)
- Writes batched in background thread
- Natural back-pressure handling

**Tradeoffs:**
- Logs may be delayed by up to ~500µs
- Requires background thread
- Adds queue memory overhead (~buffer_size × 2)

**When to use:**
- Throughput > 10,000 msg/s
- Log calls on critical path
- Acceptable to buffer logs briefly

---

### 4. Sampling

Reduce log volume without changing code:

```zig
.sampling_rate = 0.1,  // Keep 10% of logs
```

**Performance impact:**
```zig
sampling_rate = 1.0  // No sampling: 100% processing
sampling_rate = 0.5  // 50% sampling: ~50% faster
sampling_rate = 0.1  // 10% sampling: ~90% faster
```

**Use cases:**
- High-volume debug logging in production
- Sampling frequent events (e.g., HTTP requests)
- Reducing I/O pressure

**Warning:** Statistical sampling may miss important events. Use sampling_rate = 1.0 for errors and warnings.

---

### 5. Log Level Filtering

Most efficient way to reduce overhead:

```zig
.level = .warn,  // Only warn, err, fatal
```

**Performance:**
- Filtered logs have near-zero overhead
- Check happens before any formatting
- Recommended: Use `.info` or `.warn` in production

```zig
// Development
.level = .debug,

// Staging
.level = .info,

// Production
.level = .warn,
```

---

### 6. File Rotation Tuning

Balance between file count and rotation overhead:

```zig
.max_file_size = 50 * 1024 * 1024,  // 50MB (less frequent rotation)
.max_backup_files = 10,              // Keep 10 backups
```

**Rotation cost:**
- File close/open: ~1-5ms
- Rename operations: ~0.5ms each
- Total rotation overhead: ~5-20ms (depending on backup count)

**Optimization:**
- Larger files = less rotation overhead
- Fewer backups = faster rotation
- Consider external log rotation (logrotate) for very high throughput

---

### 7. Network Target Optimization

For network logging:

```zig
.network_config = .{
    .protocol = .udp,         // Fastest, no connection overhead
    .enable_compression = true, // Reduce bandwidth
    .compression_level = 3,   // Fast compression
};
```

**Protocol comparison:**
- **UDP**: Fastest, no guarantees (~500µs)
- **TCP**: Reliable, connection overhead (~2ms)
- **HTTP**: Most compatible, highest overhead (~5-10ms)

---

## Benchmarking

### Built-in Benchmarks

Run zlog's benchmark suite:

```bash
zig build test --summary all
```

Look for benchmark results:
```
Text format: 51234.56 messages/ms
Binary format: 87654.32 messages/ms
Structured logging: 28901.23 messages/ms
```

---

### Custom Benchmarks

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
        .async_io = true,
    });
    defer logger.deinit();

    const iterations = 100_000;
    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        logger.info("Benchmark message {d}", .{i});
    }

    const end = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    const messages_per_second = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.debug.print("Logged {d} messages in {d:.2}ms\n", .{iterations, duration_ms});
    std.debug.print("Throughput: {d:.0} msg/s\n", .{messages_per_second});
}
```

---

### Metrics Collection

Use built-in metrics for production monitoring:

```zig
var metrics = try zlog.metrics.MetricsCollector.init(allocator);
defer metrics.deinit();

// ... logging ...

metrics.printReport();
```

Output:
```
📊 zlog Performance Metrics
===========================
Throughput:
  Total messages: 1000000
  Messages/second: 45678.90
  Avg message size: 142.34 bytes

Latency:
  Avg log latency: 21.45 µs
  Avg flush latency: 123.67 µs
```

---

## Common Scenarios

### High-Volume Web Server

**Requirements:**
- 50,000+ requests/second
- Request logging with fields
- JSON for log aggregation

**Configuration:**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .json,
    .output_target = .file,
    .file_path = "/var/log/app/access.log",
    .max_file_size = 100 * 1024 * 1024,  // 100MB
    .max_backup_files = 20,
    .buffer_size = 32768,
    .async_io = true,
    .enable_batching = true,
    .batch_size = 1000,
});
```

---

### Real-time Trading System

**Requirements:**
- Microsecond latency
- Complete audit trail
- No data loss

**Configuration:**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .binary,
    .output_target = .file,
    .file_path = "/mnt/ssd/trading.log",
    .buffer_size = 2048,
    .async_io = false,  // Synchronous for guarantees
    .max_file_size = 1024 * 1024 * 1024,  // 1GB
});
```

---

### Embedded Device

**Requirements:**
- Limited memory (< 1MB)
- Slow disk I/O
- Battery powered

**Configuration:**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .text,
    .output_target = .file,
    .buffer_size = 256,
    .sampling_rate = 0.05,  // Only 5% of logs
    .level = .warn,         // Only warnings and errors
});
```

---

### Development/Debugging

**Requirements:**
- Maximum information
- Human-readable
- Immediate output

**Configuration:**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .text,
    .output_target = .stderr,
    .level = .debug,
    .buffer_size = 1024,
    .async_io = false,
});
```

---

## Performance Checklist

✅ **Always:**
- Set appropriate log level for environment
- Use structured fields instead of string formatting
- Profile your specific workload

✅ **High Throughput:**
- Enable `async_io = true`
- Use `format = .binary`
- Increase `buffer_size` to 32KB+
- Enable `enable_batching = true`

✅ **Low Latency:**
- Set `async_io = false`
- Use `output_target = .stdout/.stderr`
- Keep `buffer_size` small (1-4KB)

✅ **Resource Constrained:**
- Set `sampling_rate < 1.0`
- Use `level = .warn` or higher
- Minimize `buffer_size`
- Disable `async_io`

❌ **Avoid:**
- Logging in tight loops without sampling
- Very small buffers with high throughput
- Synchronous I/O with high message rates
- Large structured fields in hot paths

---

## Additional Resources

- [API Reference](API.md) - Complete API documentation
- [Examples](../examples/) - Sample applications
- [Benchmarks](../tests/benchmarks/) - Performance test suite

For questions or performance issues, please file an issue at: https://github.com/ghostkellz/zlog/issues
