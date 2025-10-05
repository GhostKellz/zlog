# Migration Guide

Migrate from popular C/C++ logging libraries to zlog.

## Table of Contents

- [From spdlog (C++)](#from-spdlog-c)
- [From log4c (C)](#from-log4c-c)
- [From rsyslog](#from-rsyslog)
- [From Boost.Log (C++)](#from-boostlog-c)
- [General Migration Tips](#general-migration-tips)

---

## From spdlog (C++)

spdlog is a fast C++ logging library. Here's how to migrate to zlog.

### Basic Setup

**spdlog:**
```cpp
#include "spdlog/spdlog.h"
#include "spdlog/sinks/basic_file_sink.h"

auto logger = spdlog::basic_logger_mt("basic_logger", "logs/basic.log");
```

**zlog:**
```zig
const std = @import("std");
const zlog = @import("zlog");

var logger = try zlog.Logger.init(allocator, .{
    .output_target = .file,
    .file_path = "logs/basic.log",
});
defer logger.deinit();
```

---

### Logging Levels

**spdlog:**
```cpp
logger->trace("Trace message");
logger->debug("Debug message");
logger->info("Info message");
logger->warn("Warning message");
logger->error("Error message");
logger->critical("Critical message");
```

**zlog:**
```zig
logger.debug("Debug message", .{});
logger.info("Info message", .{});
logger.warn("Warning message", .{});
logger.err("Error message", .{});
logger.fatal("Critical message", .{});  // Note: 'critical' → 'fatal'
```

**Note:** zlog uses 5 levels (debug, info, warn, err, fatal) vs spdlog's 6 (trace, debug, info, warn, error, critical).

---

### Formatted Logging

**spdlog:**
```cpp
logger->info("User {} logged in from IP {}", username, ip_address);
```

**zlog:**
```zig
logger.info("User {s} logged in from IP {s}", .{username, ip_address});
```

**Note:** Zig uses `{s}` for strings, `{d}` for integers, `{d:.2}` for floats.

---

### Structured Logging

**spdlog:**
```cpp
logger->info("User event: user_id={}, action={}, duration={}",
             user_id, action, duration);
```

**zlog (Better):**
```zig
const fields = [_]zlog.Field{
    .{ .key = "user_id", .value = .{ .uint = user_id } },
    .{ .key = "action", .value = .{ .string = action } },
    .{ .key = "duration", .value = .{ .float = duration } },
};
logger.logWithFields(.info, "User event", &fields);
```

---

### File Rotation

**spdlog:**
```cpp
#include "spdlog/sinks/rotating_file_sink.h"

auto logger = spdlog::rotating_logger_mt(
    "logger",
    "logs/mylog.log",
    1024 * 1024 * 10,  // 10MB
    5                   // 5 backup files
);
```

**zlog:**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .output_target = .file,
    .file_path = "logs/mylog.log",
    .max_file_size = 10 * 1024 * 1024,
    .max_backup_files = 5,
});
```

---

### Async Logging

**spdlog:**
```cpp
#include "spdlog/async.h"
#include "spdlog/sinks/basic_file_sink.h"

auto async_file = spdlog::basic_logger_mt<spdlog::async_factory>(
    "async_logger", "logs/async.log"
);
```

**zlog:**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .output_target = .file,
    .file_path = "logs/async.log",
    .async_io = true,
});
```

---

### Multiple Sinks

**spdlog:**
```cpp
#include "spdlog/sinks/stdout_sinks.h"
#include "spdlog/sinks/basic_file_sink.h"

auto console_sink = std::make_shared<spdlog::sinks::stdout_sink_mt>();
auto file_sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>("log.txt");

spdlog::logger logger("multi_sink", {console_sink, file_sink});
```

**zlog (Workaround):**
```zig
// Create two loggers
var console_logger = try zlog.Logger.init(allocator, .{
    .output_target = .stdout,
});
defer console_logger.deinit();

var file_logger = try zlog.Logger.init(allocator, .{
    .output_target = .file,
    .file_path = "log.txt",
});
defer file_logger.deinit();

// Helper function to log to both
fn logBoth(level: zlog.Level, msg: []const u8) void {
    console_logger.log(level, msg, .{});
    file_logger.log(level, msg, .{});
}
```

---

### Pattern Formatting

**spdlog:**
```cpp
spdlog::set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] %v");
```

**zlog:**

zlog has fixed formats (text, json, binary), but you can use custom formatting:

```zig
// Use JSON format for structured output
.format = .json,

// Or implement custom formatter
// See examples/custom_formatter.zig
```

---

## From log4c (C)

log4c is a C logging library based on log4j.

### Initialization

**log4c:**
```c
#include "log4c.h"

int main() {
    log4c_init();
    log4c_category_t* mycat = log4c_category_get("mycat");
```

**zlog:**
```zig
const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try zlog.Logger.init(allocator, .{});
    defer logger.deinit();
```

---

### Logging

**log4c:**
```c
log4c_category_log(mycat, LOG4C_PRIORITY_INFO, "Info message");
log4c_category_log(mycat, LOG4C_PRIORITY_ERROR, "Error message");
```

**zlog:**
```zig
logger.info("Info message", .{});
logger.err("Error message", .{});
```

---

### File Appender

**log4c:**
```c
// Configured in log4crc file
log4c.appender.myappender=file
log4c.appender.myappender.file=mylog.log
```

**zlog:**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .output_target = .file,
    .file_path = "mylog.log",
});
```

---

### Categories (Hierarchical Logging)

**log4c:**
```c
log4c_category_t* root = log4c_category_get("root");
log4c_category_t* network = log4c_category_get("root.network");
log4c_category_t* database = log4c_category_get("root.database");
```

**zlog (Alternative):**
```zig
// Use structured fields to categorize
const fields = [_]zlog.Field{
    .{ .key = "category", .value = .{ .string = "network" } },
};
logger.logWithFields(.info, "Network event", &fields);
```

---

## From rsyslog

rsyslog is a system logging daemon for Unix-like systems.

### Basic syslog

**rsyslog (C API):**
```c
#include <syslog.h>

openlog("myapp", LOG_PID, LOG_USER);
syslog(LOG_INFO, "Application started");
closelog();
```

**zlog (to syslog):**
```zig
const network_config = zlog.network.NetworkConfig{
    .protocol = .syslog_udp,
    .host = "localhost",
    .port = 514,
    .syslog_facility = .user,
    .syslog_app_name = "myapp",
};

var logger = try zlog.Logger.init(allocator, .{
    .output_target = .network,
    .network_config = network_config,
});
defer logger.deinit();

logger.info("Application started", .{});
```

---

### Priority Levels

**rsyslog:**
```c
syslog(LOG_EMERG,   "Emergency");
syslog(LOG_ALERT,   "Alert");
syslog(LOG_CRIT,    "Critical");
syslog(LOG_ERR,     "Error");
syslog(LOG_WARNING, "Warning");
syslog(LOG_NOTICE,  "Notice");
syslog(LOG_INFO,    "Info");
syslog(LOG_DEBUG,   "Debug");
```

**zlog (maps to syslog priorities):**
```zig
logger.fatal("Critical", .{});     // Maps to LOG_CRIT (3)
logger.err("Error", .{});          // Maps to LOG_ERR (3)
logger.warn("Warning", .{});       // Maps to LOG_WARNING (4)
logger.info("Info", .{});          // Maps to LOG_INFO (6)
logger.debug("Debug", .{});        // Maps to LOG_DEBUG (7)
```

---

### Facilities

**rsyslog:**
```c
openlog("myapp", LOG_PID, LOG_USER);
openlog("myapp", LOG_PID, LOG_DAEMON);
openlog("myapp", LOG_PID, LOG_LOCAL0);
```

**zlog:**
```zig
const network_config = zlog.network.NetworkConfig{
    .protocol = .syslog_udp,
    .host = "localhost",
    .port = 514,
    .syslog_facility = .user,    // or .daemon, .local0, etc.
    .syslog_app_name = "myapp",
};
```

---

### Structured Data (RFC 5424)

**rsyslog:**
```c
syslog(LOG_INFO, "[exampleSDID@32473 iut=\"3\" eventSource=\"Application\"] Message");
```

**zlog:**
```zig
const fields = [_]zlog.Field{
    .{ .key = "iut", .value = .{ .uint = 3 } },
    .{ .key = "eventSource", .value = .{ .string = "Application" } },
};
logger.logWithFields(.info, "Message", &fields);
// zlog automatically formats as RFC 5424 structured data
```

---

## From Boost.Log (C++)

Boost.Log is a comprehensive C++ logging library.

### Basic Setup

**Boost.Log:**
```cpp
#include <boost/log/trivial.hpp>

BOOST_LOG_TRIVIAL(info) << "Info message";
BOOST_LOG_TRIVIAL(warning) << "Warning message";
```

**zlog:**
```zig
logger.info("Info message", .{});
logger.warn("Warning message", .{});
```

---

### File Logging

**Boost.Log:**
```cpp
#include <boost/log/utility/setup/file.hpp>

boost::log::add_file_log("sample.log");
```

**zlog:**
```zig
var logger = try zlog.Logger.init(allocator, .{
    .output_target = .file,
    .file_path = "sample.log",
});
```

---

### Severity Levels

**Boost.Log:**
```cpp
enum severity_level {
    trace,
    debug,
    info,
    warning,
    error,
    fatal
};
```

**zlog:**
```zig
// Built-in levels
.debug, .info, .warn, .err, .fatal
```

---

### Attributes (Structured Fields)

**Boost.Log:**
```cpp
BOOST_LOG_TRIVIAL(info)
    << "User=" << username
    << " ID=" << user_id
    << " Action=" << action;
```

**zlog:**
```zig
const fields = [_]zlog.Field{
    .{ .key = "User", .value = .{ .string = username } },
    .{ .key = "ID", .value = .{ .uint = user_id } },
    .{ .key = "Action", .value = .{ .string = action } },
};
logger.logWithFields(.info, "User action", &fields);
```

---

## General Migration Tips

### 1. Memory Management

**C/C++:**
- Manual resource management
- Potential memory leaks

**Zig/zlog:**
- Explicit allocator usage
- Defer cleanup for safety

```zig
var logger = try zlog.Logger.init(allocator, .{});
defer logger.deinit();  // Always cleanup
```

---

### 2. Error Handling

**C:**
```c
if (log_init() != 0) {
    fprintf(stderr, "Failed to init logger\n");
    exit(1);
}
```

**Zig:**
```zig
var logger = try zlog.Logger.init(allocator, .{});
// Error is automatically propagated with detailed info
```

---

### 3. Thread Safety

**C/C++ (varies by library):**
- May require manual locking
- Thread-local storage

**zlog:**
- Thread-safe by default
- Internal mutex protection

```zig
// Safe to call from multiple threads
logger.info("Thread-safe log", .{});
```

---

### 4. Performance

**Migration optimization checklist:**

✅ Enable async I/O for high throughput
```zig
.async_io = true,
```

✅ Use binary format for maximum speed
```zig
.format = .binary,
```

✅ Adjust buffer size
```zig
.buffer_size = 32768,  // Tune based on workload
```

✅ Set appropriate log level
```zig
.level = .info,  // Filter debug logs in production
```

---

### 5. Configuration

**From config files:**

Many C/C++ loggers use XML or property files. zlog supports JSON:

**log4c (log4crc):**
```
log4c.rootCategory=INFO, myappender
log4c.appender.myappender=file
log4c.appender.myappender.file=mylog.log
```

**zlog (config.json):**
```json
{
  "level": "info",
  "output_target": "file",
  "file_path": "mylog.log"
}
```

Load with:
```zig
const config_mgr = try zlog.config.ConfigManager.init(
    allocator,
    "config.json",
    .json,
);
const config = config_mgr.getConfig();
var logger = try zlog.Logger.init(allocator, config);
```

---

### 6. Testing

**Mock logging in tests:**

```zig
test "application logic" {
    // Create logger that outputs to stderr for tests
    var logger = try zlog.Logger.init(testing.allocator, .{
        .output_target = .stderr,
        .level = .debug,
    });
    defer logger.deinit();

    // Your test code
}
```

---

## Complete Migration Example

### Original (spdlog):

```cpp
#include "spdlog/spdlog.h"
#include "spdlog/sinks/rotating_file_sink.h"

class Application {
public:
    Application() {
        logger_ = spdlog::rotating_logger_mt(
            "app",
            "logs/app.log",
            1024 * 1024 * 10,
            3
        );
        logger_->set_level(spdlog::level::info);
    }

    void processRequest(int user_id, const std::string& action) {
        logger_->info("Processing: user={}, action={}", user_id, action);
        // ... process ...
        logger_->info("Completed in {}ms", duration);
    }

private:
    std::shared_ptr<spdlog::logger> logger_;
};
```

### Migrated (zlog):

```zig
const std = @import("std");
const zlog = @import("zlog");

pub const Application = struct {
    logger: zlog.Logger,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Application {
        const logger = try zlog.Logger.init(allocator, .{
            .level = .info,
            .output_target = .file,
            .file_path = "logs/app.log",
            .max_file_size = 10 * 1024 * 1024,
            .max_backup_files = 3,
        });

        return Application{
            .logger = logger,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Application) void {
        self.logger.deinit();
    }

    pub fn processRequest(self: *Application, user_id: u64, action: []const u8) !void {
        const fields = [_]zlog.Field{
            .{ .key = "user_id", .value = .{ .uint = user_id } },
            .{ .key = "action", .value = .{ .string = action } },
        };
        self.logger.logWithFields(.info, "Processing", &fields);

        // ... process ...

        const duration_fields = [_]zlog.Field{
            .{ .key = "duration_ms", .value = .{ .float = duration } },
        };
        self.logger.logWithFields(.info, "Completed", &duration_fields);
    }
};
```

---

## Need Help?

For migration assistance or questions:
- **Documentation**: See [API.md](API.md) for complete API reference
- **Examples**: Check `examples/` directory for sample code
- **Issues**: https://github.com/ghostkellz/zlog/issues

Happy migrating! 🚀
