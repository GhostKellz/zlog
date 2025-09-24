# Migration Guide

Guide for migrating from other logging libraries to zlog.

## From spdlog (C++)

### Basic Usage

**Before (spdlog):**
```cpp
#include "spdlog/spdlog.h"

int main() {
    spdlog::info("Hello, spdlog!");
    spdlog::warn("Warning message");
    spdlog::error("Error message");
    return 0;
}
```

**After (zlog):**
```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    zlog.info("Hello, zlog!", .{});
    zlog.warn("Warning message", .{});
    zlog.err("Error message", .{});
}
```

### File Logging

**Before (spdlog):**
```cpp
#include "spdlog/sinks/basic_file_sink.h"

auto file_logger = spdlog::basic_logger_mt("file_logger", "app.log");
file_logger->info("Logging to file");
```

**After (zlog):**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .output_target = .file,
    .file_path = "app.log",
});
defer logger.deinit();

logger.info("Logging to file", .{});
```

### Rotating File Logger

**Before (spdlog):**
```cpp
#include "spdlog/sinks/rotating_file_sink.h"

auto rotating_logger = spdlog::rotating_logger_mt(
    "rotating_logger",
    "rotating.log",
    1048576 * 5,  // 5MB
    3             // 3 backup files
);
rotating_logger->info("Message");
```

**After (zlog):**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .output_target = .file,
    .file_path = "rotating.log",
    .max_file_size = 5 * 1024 * 1024, // 5MB
    .max_backup_files = 3,
});
defer logger.deinit();

logger.info("Message", .{});
```

### Async Logging

**Before (spdlog):**
```cpp
#include "spdlog/async.h"
#include "spdlog/sinks/basic_file_sink.h"

spdlog::init_thread_pool(8192, 1);
auto async_logger = spdlog::basic_logger_mt<spdlog::async_factory>(
    "async_logger", "async.log");
async_logger->info("Async message");
```

**After (zlog):**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .output_target = .file,
    .file_path = "async.log",
    .async_io = true,
    .buffer_size = 8192,
});
defer logger.deinit();

logger.info("Async message", .{});
```

## From log4c (C)

### Basic Configuration

**Before (log4c):**
```c
#include <log4c.h>

int main() {
    log4c_init();

    log4c_category_t* category = log4c_category_get("myapp");

    log4c_category_log(category, LOG4C_PRIORITY_INFO, "Hello, log4c!");
    log4c_category_log(category, LOG4C_PRIORITY_WARN, "Warning");
    log4c_category_log(category, LOG4C_PRIORITY_ERROR, "Error");

    log4c_fini();
    return 0;
}
```

**After (zlog):**
```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{});
    defer logger.deinit();

    logger.info("Hello, zlog!", .{});
    logger.warn("Warning", .{});
    logger.err("Error", .{});
}
```

### Priority Levels Mapping

| log4c Priority | zlog Level |
|---------------|------------|
| `LOG4C_PRIORITY_DEBUG` | `.debug` |
| `LOG4C_PRIORITY_INFO` | `.info` |
| `LOG4C_PRIORITY_WARN` | `.warn` |
| `LOG4C_PRIORITY_ERROR` | `.err` |
| `LOG4C_PRIORITY_FATAL` | `.fatal` |

## From Standard Library Logging

### Go `log` package

**Before (Go):**
```go
package main

import (
    "log"
    "os"
)

func main() {
    log.SetOutput(os.Stdout)
    log.SetPrefix("APP: ")
    log.Println("Hello, log!")
}
```

**After (zlog):**
```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
    });
    defer logger.deinit();

    logger.info("Hello, zlog!", .{});
}
```

### Python `logging`

**Before (Python):**
```python
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filename='app.log'
)

logger = logging.getLogger(__name__)
logger.info("Hello, logging!")
logger.warning("Warning message")
logger.error("Error message")
```

**After (zlog):**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .level = .info,
    .format = .text,
    .output_target = .file,
    .file_path = "app.log",
});
defer logger.deinit();

logger.info("Hello, zlog!", .{});
logger.warn("Warning message", .{});
logger.err("Error message", .{});
```

## Migration Strategies

### 1. Gradual Migration

Replace logging incrementally:

```zig
// Keep existing logger for now
var legacy_logger = ...; // Your existing logger

// Create zlog logger for new code
var zlog_logger = try zlog.Logger.init(allocator, .{
    .format = .json,
    .output_target = .file,
    .file_path = "new_logs.log",
});
defer zlog_logger.deinit();

// Use zlog for new features
fn newFeature() void {
    zlog_logger.info("New feature called", .{});
}

// Gradually convert existing code
fn existingFeature() void {
    // legacy_logger.info("Old way");
    zlog_logger.info("New way", .{});
}
```

### 2. Wrapper Approach

Create a wrapper to maintain existing API:

```zig
// Wrapper to maintain existing API
const LegacyLogger = struct {
    zlog_logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator) !LegacyLogger {
        return LegacyLogger{
            .zlog_logger = try zlog.Logger.init(allocator, .{
                .format = .text,
            }),
        };
    }

    pub fn deinit(self: *LegacyLogger) void {
        self.zlog_logger.deinit();
    }

    // Maintain old API
    pub fn log_info(self: *LegacyLogger, msg: []const u8) void {
        self.zlog_logger.info("{s}", .{msg});
    }

    pub fn log_error(self: *LegacyLogger, msg: []const u8) void {
        self.zlog_logger.err("{s}", .{msg});
    }
};
```

### 3. Configuration Migration

Map existing configuration to zlog:

```zig
// Convert legacy config to zlog config
fn migrateConfig(legacy_config: LegacyConfig) zlog.LoggerConfig {
    const level = switch (legacy_config.verbosity) {
        0 => zlog.Level.err,
        1 => zlog.Level.warn,
        2 => zlog.Level.info,
        3 => zlog.Level.debug,
        else => zlog.Level.debug,
    };

    const format = if (legacy_config.use_json) zlog.Format.json else zlog.Format.text;

    return zlog.LoggerConfig{
        .level = level,
        .format = format,
        .output_target = if (legacy_config.log_file) |_| .file else .stdout,
        .file_path = legacy_config.log_file,
        .max_file_size = legacy_config.max_file_size orelse (10 * 1024 * 1024),
    };
}
```

## Performance Migration

### From printf-style logging

**Before:**
```c
printf("[INFO] Processing item %d\n", item_id);
```

**After:**
```zig
logger.info("Processing item {d}", .{item_id});
```

**Benefits:**
- Type safety at compile time
- Better performance through structured logging
- Built-in timestamp and level formatting

### High-Performance Scenarios

**Before (custom binary logging):**
```c
// Custom binary format
write_binary_log(LOG_INFO, timestamp, "message", data, data_len);
```

**After (zlog binary format):**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .format = .binary,
    .async_io = true,
});

const fields = [_]zlog.Field{
    .{ .key = "data", .value = .{ .string = data } },
};
logger.logWithFields(.info, "message", &fields);
```

## Feature Mapping

### Common Features

| Feature | spdlog | log4c | zlog |
|---------|--------|-------|------|
| Basic logging | ✅ | ✅ | ✅ |
| File output | ✅ | ✅ | ✅ |
| Log rotation | ✅ | ❌ | ✅ |
| Async logging | ✅ | ❌ | ✅ |
| JSON format | ✅ | ❌ | ✅ |
| Binary format | ❌ | ❌ | ✅ |
| Thread safety | ✅ | ❌ | ✅ |
| Structured logging | ❌ | ❌ | ✅ |

### Advanced Features

| Feature | zlog Advantage |
|---------|----------------|
| Modular builds | Disable unused features for smaller binaries |
| Compile-time format strings | Type safety and performance |
| Sampling | Handle high-frequency logging efficiently |
| Zero-allocation paths | Better performance for disabled features |
| Memory safety | Zig's built-in memory safety |

## Common Pitfalls

### 1. Memory Management

**Wrong:**
```zig
// Don't forget to deinit!
var logger = try zlog.Logger.init(allocator, .{});
// Missing: defer logger.deinit();
```

**Right:**
```zig
var logger = try zlog.Logger.init(allocator, .{});
defer logger.deinit(); // Always pair with deinit
```

### 2. Format String Safety

**Wrong:**
```zig
const user_input = getUserInput();
logger.info(user_input, .{}); // Security risk if user_input has format specifiers
```

**Right:**
```zig
const user_input = getUserInput();
logger.info("{s}", .{user_input}); // Safe
```

### 3. Async Logger Shutdown

**Wrong:**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .async_io = true,
});
// Exit immediately without waiting for async logs
```

**Right:**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .async_io = true,
});
defer logger.deinit(); // Waits for async thread to finish
```

## Testing During Migration

Create tests to ensure equivalent behavior:

```zig
test "migration compatibility" {
    const allocator = std.testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .format = .text,
    });
    defer logger.deinit();

    // Test that zlog produces expected output format
    logger.info("Test message", .{});

    // Compare with expected legacy format
    // ... verification code ...
}
```

## Build System Integration

### CMake to Zig Build

**Before (CMakeLists.txt):**
```cmake
find_package(spdlog REQUIRED)
target_link_libraries(myapp spdlog::spdlog)
```

**After (build.zig):**
```zig
const zlog_dep = b.dependency("zlog", .{});
const zlog_module = zlog_dep.module("zlog");
exe.root_module.addImport("zlog", zlog_module);
```

### Makefile to Zig Build

**Before (Makefile):**
```makefile
LIBS += -llog4c
CFLAGS += -DUSE_LOGGING
```

**After (build.zig):**
```zig
// Logging is built-in, no external dependencies
exe.root_module.addImport("zlog", zlog_module);
```

## Post-Migration Optimization

After migrating, optimize for zlog's strengths:

1. **Use structured logging** instead of formatted strings
2. **Enable sampling** for high-frequency logs
3. **Use async I/O** for better performance
4. **Configure appropriate buffer sizes**
5. **Use binary format** for maximum throughput
6. **Disable unused features** in builds

The migration to zlog typically results in better performance, smaller binaries, and improved type safety while maintaining familiar logging patterns.