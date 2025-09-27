# zlog Best Practices Guide

This guide provides comprehensive best practices for using zlog effectively in production environments. Following these practices will help you build robust, maintainable, and high-performance logging systems.

## Table of Contents

1. [General Principles](#general-principles)
2. [Configuration Best Practices](#configuration-best-practices)
3. [Message Design](#message-design)
4. [Structured Logging](#structured-logging)
5. [Error Handling](#error-handling)
6. [Performance Optimization](#performance-optimization)
7. [Security Considerations](#security-considerations)
8. [Testing and Monitoring](#testing-and-monitoring)
9. [Deployment Patterns](#deployment-patterns)
10. [Common Anti-Patterns](#common-anti-patterns)

## General Principles

### 1. Log with Purpose

Every log message should serve a specific purpose:

```zig
// ❌ Bad: Vague, unhelpful logging
logger.info("Processing data");
logger.debug("Loop iteration");

// ✅ Good: Clear, actionable logging
logger.info("Processing user registration for user_id={d}", .{user_id});
logger.debug("Retrying database connection, attempt {d}/3", .{attempt});
```

### 2. Use Appropriate Log Levels

Follow consistent log level conventions:

```zig
const LogLevel = zlog.Level;

// FATAL: System cannot continue
logger.fatal("Database connection pool exhausted, shutting down");

// ERROR: Something failed but system continues
logger.err("Failed to save user profile: {}", .{err});

// WARN: Potentially problematic situation
logger.warn("API rate limit approaching: {d}/1000 requests", .{current_requests});

// INFO: General information about program flow
logger.info("User {d} logged in successfully", .{user_id});

// DEBUG: Detailed information for troubleshooting
logger.debug("SQL query: {s} (took {d}ms)", .{query, duration});
```

### 3. Be Consistent

Establish and follow consistent naming conventions:

```zig
// ✅ Good: Consistent field naming
const CommonFields = struct {
    pub fn userId(id: u64) zlog.Field { return zlog.uint("user_id", id); }
    pub fn requestId(id: []const u8) zlog.Field { return zlog.str("request_id", id); }
    pub fn sessionId(id: []const u8) zlog.Field { return zlog.str("session_id", id); }
    pub fn duration(ms: f64) zlog.Field { return zlog.float("duration_ms", ms); }
};

// Usage
logger.logWithFields(.info, "Request completed", &[_]zlog.Field{
    CommonFields.userId(user_id),
    CommonFields.requestId(req_id),
    CommonFields.duration(elapsed_ms),
});
```

### 4. Make Logs Searchable

Design log messages for easy searching and filtering:

```zig
// ✅ Good: Searchable patterns
logger.info("AUTH_SUCCESS user_id={d} method=password", .{user_id});
logger.info("AUTH_FAILURE user_id={d} reason=invalid_password", .{user_id});
logger.info("PAYMENT_PROCESSED order_id={s} amount={d:.2} currency={s}", .{order_id, amount, currency});

// This allows searching for:
// - AUTH_SUCCESS (all successful authentications)
// - user_id=123 (all activity for specific user)
// - PAYMENT_PROCESSED (all payment events)
```

## Configuration Best Practices

### 1. Environment-Specific Configuration

Use different configurations for different environments:

```zig
pub const LogConfig = struct {
    pub fn forEnvironment(env: Environment) zlog.LoggerConfig {
        return switch (env) {
            .development => .{
                .level = .debug,
                .format = .text,
                .output_target = .stderr,
                .buffer_size = 1024,
                .async_io = false,
                .enable_colors = true,
            },
            .testing => .{
                .level = .warn,
                .format = .text,
                .output_target = .stderr,
                .buffer_size = 512,
                .async_io = false,
            },
            .staging => .{
                .level = .info,
                .format = .json,
                .output_target = .{ .file = "/var/log/app-staging.log" },
                .buffer_size = 8192,
                .async_io = true,
                .max_file_size = 10 * 1024 * 1024,
                .max_backup_files = 5,
            },
            .production => .{
                .level = .info,
                .format = .json,
                .output_target = .{ .file = "/var/log/app.log" },
                .buffer_size = 16384,
                .async_io = true,
                .enable_batching = true,
                .batch_size = 100,
                .max_file_size = 100 * 1024 * 1024,
                .max_backup_files = 10,
                .sampling_rate = 1.0,
            },
        };
    }

    const Environment = enum { development, testing, staging, production };
};
```

### 2. Configuration Validation

Always validate configuration before use:

```zig
pub fn createLogger(allocator: std.mem.Allocator, config: zlog.LoggerConfig) !zlog.Logger {
    // Validate configuration
    const validation = @import("zlog").validation;
    const is_valid = try validation.validateConfig(allocator, config);
    if (!is_valid) {
        return error.InvalidLoggerConfiguration;
    }

    // Create logger with validated config
    return zlog.Logger.init(allocator, config);
}
```

### 3. Runtime Configuration Updates

Support runtime configuration changes where appropriate:

```zig
pub const ConfigurableLogger = struct {
    logger: zlog.Logger,
    mutex: std.Thread.Mutex,

    pub fn updateLevel(self: *ConfigurableLogger, new_level: zlog.Level) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.logger.config.level = new_level;
        self.logger.info("Log level changed to {s}", .{@tagName(new_level)});
    }

    pub fn toggleDebugMode(self: *ConfigurableLogger) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const new_level: zlog.Level = if (self.logger.config.level == .debug) .info else .debug;
        self.logger.config.level = new_level;
        self.logger.info("Debug mode {s}", .{if (new_level == .debug) "enabled" else "disabled"});
    }
};
```

## Message Design

### 1. Write Clear, Actionable Messages

```zig
// ❌ Bad: Unclear what happened or what to do
logger.err("Error in function");
logger.warn("Something wrong");

// ✅ Good: Clear problem and context
logger.err("Failed to connect to database: {s} (check connection settings)", .{@errorName(err)});
logger.warn("Memory usage high: {d}MB/{d}MB (consider scaling up)", .{used_mb, total_mb});
```

### 2. Include Relevant Context

Provide enough context for debugging without overwhelming:

```zig
// ❌ Bad: Too little context
logger.err("Save failed");

// ❌ Bad: Too much irrelevant context
logger.err("Save failed in function save_user called from handle_request called from process_request with params user_id={d} session_id={s} timestamp={d} server_id={s} build_version={s}", .{user_id, session_id, timestamp, server_id, build_version});

// ✅ Good: Right amount of relevant context
logger.err("Failed to save user profile: {s} user_id={d} validation_errors={d}", .{@errorName(err), user_id, validation_errors.len});
```

### 3. Use Structured Context When Appropriate

For complex context, use structured logging:

```zig
pub fn logUserAction(logger: *zlog.Logger, action: []const u8, user_id: u64, success: bool, details: ?[]const u8) void {
    const fields = [_]zlog.Field{
        zlog.str("action", action),
        zlog.uint("user_id", user_id),
        zlog.boolean("success", success),
        zlog.str("details", details orelse ""),
        zlog.uint("timestamp", @intCast(std.time.timestamp())),
    };

    const level: zlog.Level = if (success) .info else .warn;
    logger.logWithFields(level, "User action completed", &fields);
}

// Usage
logUserAction(logger, "password_change", user_id, true, null);
logUserAction(logger, "login_attempt", user_id, false, "invalid_password");
```

### 4. Avoid Sensitive Information

Never log sensitive data:

```zig
// ❌ Bad: Logging sensitive information
logger.info("User login: email={s} password={s}", .{email, password});
logger.debug("Credit card processed: number={s} cvv={s}", .{card_number, cvv});

// ✅ Good: Log safely without sensitive data
logger.info("User login: email_domain={s} user_id={d}", .{getEmailDomain(email), user_id});
logger.debug("Credit card processed: last_four={s} type={s}", .{getLastFour(card_number), card_type});
```

## Structured Logging

### 1. Design a Consistent Schema

Define a consistent schema for structured logs:

```zig
pub const LogSchema = struct {
    // Common fields for all logs
    pub const Common = struct {
        pub fn timestamp() zlog.Field { return zlog.uint("timestamp", @intCast(std.time.timestamp())); }
        pub fn level(log_level: zlog.Level) zlog.Field { return zlog.str("level", @tagName(log_level)); }
        pub fn service(name: []const u8) zlog.Field { return zlog.str("service", name); }
        pub fn version(ver: []const u8) zlog.Field { return zlog.str("version", ver); }
    };

    // HTTP request fields
    pub const Http = struct {
        pub fn method(m: []const u8) zlog.Field { return zlog.str("http_method", m); }
        pub fn path(p: []const u8) zlog.Field { return zlog.str("http_path", p); }
        pub fn status(code: u32) zlog.Field { return zlog.uint("http_status", code); }
        pub fn userAgent(agent: []const u8) zlog.Field { return zlog.str("user_agent", agent); }
        pub fn remoteAddr(addr: []const u8) zlog.Field { return zlog.str("remote_addr", addr); }
    };

    // Database operation fields
    pub const Database = struct {
        pub fn operation(op: []const u8) zlog.Field { return zlog.str("db_operation", op); }
        pub fn table(name: []const u8) zlog.Field { return zlog.str("db_table", name); }
        pub fn queryTime(ms: f64) zlog.Field { return zlog.float("db_query_time_ms", ms); }
        pub fn rowCount(count: u64) zlog.Field { return zlog.uint("db_row_count", count); }
    };

    // Business logic fields
    pub const Business = struct {
        pub fn userId(id: u64) zlog.Field { return zlog.uint("user_id", id); }
        pub fn orderId(id: []const u8) zlog.Field { return zlog.str("order_id", id); }
        pub fn amount(value: f64) zlog.Field { return zlog.float("amount", value); }
        pub fn currency(code: []const u8) zlog.Field { return zlog.str("currency", code); }
    };
};
```

### 2. Use Structured Logging for Key Events

```zig
pub fn logHttpRequest(
    logger: *zlog.Logger,
    method: []const u8,
    path: []const u8,
    status: u32,
    duration_ms: f64,
    user_id: ?u64,
) void {
    var fields = std.ArrayList(zlog.Field).init(std.heap.page_allocator);
    defer fields.deinit();

    fields.appendSlice(&[_]zlog.Field{
        LogSchema.Common.timestamp(),
        LogSchema.Http.method(method),
        LogSchema.Http.path(path),
        LogSchema.Http.status(status),
        zlog.float("response_time_ms", duration_ms),
    }) catch return;

    if (user_id) |uid| {
        fields.append(LogSchema.Business.userId(uid)) catch return;
    }

    logger.logWithFields(.info, "HTTP request completed", fields.items);
}
```

### 3. Implement Logging Middleware

Create reusable logging components:

```zig
pub const LoggingMiddleware = struct {
    logger: *zlog.Logger,
    service_name: []const u8,

    pub fn init(logger: *zlog.Logger, service_name: []const u8) LoggingMiddleware {
        return LoggingMiddleware{
            .logger = logger,
            .service_name = service_name,
        };
    }

    pub fn logError(self: LoggingMiddleware, err: anyerror, context: []const u8, extra_fields: []const zlog.Field) void {
        var fields = std.ArrayList(zlog.Field).init(std.heap.page_allocator);
        defer fields.deinit();

        fields.appendSlice(&[_]zlog.Field{
            LogSchema.Common.timestamp(),
            LogSchema.Common.service(self.service_name),
            zlog.str("error", @errorName(err)),
            zlog.str("context", context),
        }) catch return;

        fields.appendSlice(extra_fields) catch return;

        self.logger.logWithFields(.err, "Error occurred", fields.items);
    }

    pub fn logPerformance(self: LoggingMiddleware, operation: []const u8, duration_ms: f64, success: bool) void {
        const fields = [_]zlog.Field{
            LogSchema.Common.timestamp(),
            LogSchema.Common.service(self.service_name),
            zlog.str("operation", operation),
            zlog.float("duration_ms", duration_ms),
            zlog.boolean("success", success),
        };

        self.logger.logWithFields(.info, "Performance metric", &fields);
    }
};
```

## Error Handling

### 1. Comprehensive Error Logging

Log errors with full context and recovery information:

```zig
pub fn handleDatabaseError(logger: *zlog.Logger, err: anyerror, operation: []const u8, retry_count: u32) void {
    const fields = [_]zlog.Field{
        zlog.str("error_type", @errorName(err)),
        zlog.str("operation", operation),
        zlog.uint("retry_count", retry_count),
        zlog.uint("timestamp", @intCast(std.time.timestamp())),
    };

    const message = switch (err) {
        error.ConnectionRefused => "Database connection refused - check if database is running",
        error.AccessDenied => "Database access denied - check credentials and permissions",
        error.Timeout => "Database operation timed out - check network and load",
        else => "Database operation failed",
    };

    logger.logWithFields(.err, message, &fields);
}
```

### 2. Implement Error Recovery Logging

Track error recovery attempts:

```zig
pub const ErrorRecoveryLogger = struct {
    logger: *zlog.Logger,
    recovery_attempts: std.HashMap([]const u8, u32, std.hash_map.StringContext, std.heap.page_allocator),

    pub fn init(logger: *zlog.Logger) ErrorRecoveryLogger {
        return ErrorRecoveryLogger{
            .logger = logger,
            .recovery_attempts = std.HashMap([]const u8, u32, std.hash_map.StringContext, std.heap.page_allocator).init(),
        };
    }

    pub fn logRecoveryAttempt(self: *ErrorRecoveryLogger, operation: []const u8, err: anyerror) void {
        const count = self.recovery_attempts.get(operation) orelse 0;
        self.recovery_attempts.put(operation, count + 1) catch return;

        const fields = [_]zlog.Field{
            zlog.str("operation", operation),
            zlog.str("error", @errorName(err)),
            zlog.uint("attempt_count", count + 1),
        };

        self.logger.logWithFields(.warn, "Error recovery attempt", &fields);
    }

    pub fn logRecoverySuccess(self: *ErrorRecoveryLogger, operation: []const u8) void {
        const count = self.recovery_attempts.get(operation) orelse 0;
        self.recovery_attempts.remove(operation);

        const fields = [_]zlog.Field{
            zlog.str("operation", operation),
            zlog.uint("total_attempts", count),
        };

        self.logger.logWithFields(.info, "Error recovery successful", &fields);
    }
};
```

### 3. Error Categorization

Categorize errors for better monitoring:

```zig
pub const ErrorCategory = enum {
    user_error,      // User input errors
    system_error,    // Internal system errors
    external_error,  // External service errors
    security_error,  // Security-related errors

    pub fn logLevel(self: ErrorCategory) zlog.Level {
        return switch (self) {
            .user_error => .warn,
            .system_error => .err,
            .external_error => .warn,
            .security_error => .err,
        };
    }
};

pub fn logCategorizedError(
    logger: *zlog.Logger,
    category: ErrorCategory,
    err: anyerror,
    context: []const u8,
    user_id: ?u64,
) void {
    var fields = std.ArrayList(zlog.Field).init(std.heap.page_allocator);
    defer fields.deinit();

    fields.appendSlice(&[_]zlog.Field{
        zlog.str("error_category", @tagName(category)),
        zlog.str("error", @errorName(err)),
        zlog.str("context", context),
    }) catch return;

    if (user_id) |uid| {
        fields.append(zlog.uint("user_id", uid)) catch return;
    }

    logger.logWithFields(category.logLevel(), "Categorized error", fields.items);
}
```

## Performance Optimization

### 1. Lazy Evaluation for Expensive Operations

Use lazy evaluation for expensive log message construction:

```zig
// ❌ Bad: Always computes expensive operation
logger.debug("User data: {s}", .{computeExpensiveUserSummary(user)});

// ✅ Good: Only compute if debug logging is enabled
if (logger.config.level <= .debug) {
    logger.debug("User data: {s}", .{computeExpensiveUserSummary(user)});
}

// ✅ Better: Use a helper function
fn debugLog(logger: *zlog.Logger, comptime fmt: []const u8, args: anytype) void {
    if (logger.config.level <= .debug) {
        logger.debug(fmt, args);
    }
}
```

### 2. Optimize High-Frequency Logging

For high-frequency logs, use optimized patterns:

```zig
pub const HighFrequencyLogger = struct {
    logger: *zlog.Logger,
    sample_counter: std.atomic.Atomic(u64),
    sample_rate: u32, // Log every Nth message

    pub fn init(logger: *zlog.Logger, sample_rate: u32) HighFrequencyLogger {
        return HighFrequencyLogger{
            .logger = logger,
            .sample_counter = std.atomic.Atomic(u64).init(0),
            .sample_rate = sample_rate,
        };
    }

    pub fn logIfSampled(self: *HighFrequencyLogger, level: zlog.Level, comptime fmt: []const u8, args: anytype) void {
        const count = self.sample_counter.fetchAdd(1, .Monotonic);
        if (count % self.sample_rate == 0) {
            self.logger.log(level, fmt, args);
        }
    }
};

// Usage for high-frequency events
var high_freq_logger = HighFrequencyLogger.init(main_logger, 1000); // Sample 1 in 1000
high_freq_logger.logIfSampled(.debug, "Processing packet {d}", .{packet_id});
```

### 3. Pre-allocate Field Arrays

Pre-allocate commonly used field combinations:

```zig
pub const PreallocatedFields = struct {
    const MAX_FIELDS = 10;
    var field_pool: [MAX_FIELDS]zlog.Field = undefined;
    var pool_index: usize = 0;

    pub fn getHttpFields(method: []const u8, path: []const u8, status: u32, duration: f64) []zlog.Field {
        const start_index = pool_index;
        field_pool[pool_index] = zlog.str("method", method);
        pool_index += 1;
        field_pool[pool_index] = zlog.str("path", path);
        pool_index += 1;
        field_pool[pool_index] = zlog.uint("status", status);
        pool_index += 1;
        field_pool[pool_index] = zlog.float("duration_ms", duration);
        pool_index += 1;

        const result = field_pool[start_index..pool_index];
        pool_index = (pool_index + 1) % MAX_FIELDS; // Simple ring buffer
        return result;
    }
};
```

## Security Considerations

### 1. Data Sanitization

Implement automatic data sanitization:

```zig
pub const DataSanitizer = struct {
    const REDACTED = "[REDACTED]";
    const PARTIAL_EMAIL_REGEX = std.regex.Regex.compile("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}") catch unreachable;

    pub fn sanitizeEmail(email: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        if (email.len < 3) return REDACTED;

        const at_index = std.mem.indexOf(u8, email, "@") orelse return REDACTED;
        if (at_index == 0) return REDACTED;

        // Show first character + domain
        return try std.fmt.allocPrint(allocator, "{c}***{s}", .{email[0], email[at_index..]});
    }

    pub fn sanitizePhoneNumber(phone: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        if (phone.len < 4) return REDACTED;

        // Show last 4 digits
        const visible = phone[phone.len - 4..];
        return try std.fmt.allocPrint(allocator, "***-***-{s}", .{visible});
    }

    pub fn sanitizeCreditCard(card: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        if (card.len < 4) return REDACTED;

        // Show last 4 digits only
        const visible = card[card.len - 4..];
        return try std.fmt.allocPrint(allocator, "****-****-****-{s}", .{visible});
    }
};

pub fn logUserDataSafely(logger: *zlog.Logger, email: []const u8, phone: []const u8, allocator: std.mem.Allocator) !void {
    const sanitized_email = try DataSanitizer.sanitizeEmail(email, allocator);
    defer allocator.free(sanitized_email);

    const sanitized_phone = try DataSanitizer.sanitizePhoneNumber(phone, allocator);
    defer allocator.free(sanitized_phone);

    const fields = [_]zlog.Field{
        zlog.str("email", sanitized_email),
        zlog.str("phone", sanitized_phone),
    };

    logger.logWithFields(.info, "User data processed", &fields);
}
```

### 2. Access Control for Log Files

Implement proper access control for log files:

```zig
pub fn createSecureLogger(allocator: std.mem.Allocator, log_file_path: []const u8) !zlog.Logger {
    // Ensure log directory exists with proper permissions
    const log_dir = std.fs.path.dirname(log_file_path) orelse ".";
    try std.fs.cwd().makePath(log_dir);

    // Set restrictive permissions (owner read/write only)
    const log_file = try std.fs.cwd().createFile(log_file_path, .{
        .mode = 0o600, // Owner read/write only
    });
    log_file.close();

    return zlog.Logger.init(allocator, .{
        .output_target = .{ .file = log_file_path },
        .format = .json,
        .async_io = true,
    });
}
```

### 3. Log Retention and Rotation

Implement secure log retention:

```zig
pub const SecureLogRotation = struct {
    pub fn rotateWithEncryption(log_file_path: []const u8, backup_count: u32) !void {
        // Rotate existing logs
        var i: u32 = backup_count;
        while (i > 0) : (i -= 1) {
            const old_name = try std.fmt.allocPrint(std.heap.page_allocator, "{s}.{d}", .{log_file_path, i - 1});
            defer std.heap.page_allocator.free(old_name);

            const new_name = try std.fmt.allocPrint(std.heap.page_allocator, "{s}.{d}", .{log_file_path, i});
            defer std.heap.page_allocator.free(new_name);

            std.fs.cwd().rename(old_name, new_name) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        }

        // Move current log to .0
        const backup_name = try std.fmt.allocPrint(std.heap.page_allocator, "{s}.0", .{log_file_path});
        defer std.heap.page_allocator.free(backup_name);

        try std.fs.cwd().rename(log_file_path, backup_name);

        // Optionally encrypt old logs
        try encryptLogFile(backup_name);
    }

    fn encryptLogFile(file_path: []const u8) !void {
        // Implementation would encrypt the log file
        // For demo purposes, just add .encrypted extension
        const encrypted_name = try std.fmt.allocPrint(std.heap.page_allocator, "{s}.encrypted", .{file_path});
        defer std.heap.page_allocator.free(encrypted_name);

        try std.fs.cwd().rename(file_path, encrypted_name);
    }
};
```

## Testing and Monitoring

### 1. Unit Testing Logging

Create testable logging patterns:

```zig
pub const TestLogger = struct {
    logged_messages: std.ArrayList(LoggedMessage),
    allocator: std.mem.Allocator,

    const LoggedMessage = struct {
        level: zlog.Level,
        message: []const u8,
        fields: []zlog.Field,
    };

    pub fn init(allocator: std.mem.Allocator) TestLogger {
        return TestLogger{
            .logged_messages = std.ArrayList(LoggedMessage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestLogger) void {
        for (self.logged_messages.items) |msg| {
            self.allocator.free(msg.message);
            self.allocator.free(msg.fields);
        }
        self.logged_messages.deinit();
    }

    pub fn log(self: *TestLogger, level: zlog.Level, message: []const u8) void {
        const owned_message = self.allocator.dupe(u8, message) catch return;
        self.logged_messages.append(.{
            .level = level,
            .message = owned_message,
            .fields = &[_]zlog.Field{},
        }) catch return;
    }

    pub fn logWithFields(self: *TestLogger, level: zlog.Level, message: []const u8, fields: []const zlog.Field) void {
        const owned_message = self.allocator.dupe(u8, message) catch return;
        const owned_fields = self.allocator.dupe(zlog.Field, fields) catch return;

        self.logged_messages.append(.{
            .level = level,
            .message = owned_message,
            .fields = owned_fields,
        }) catch return;
    }

    // Test helpers
    pub fn hasLoggedMessage(self: TestLogger, level: zlog.Level, message: []const u8) bool {
        for (self.logged_messages.items) |logged| {
            if (logged.level == level and std.mem.eql(u8, logged.message, message)) {
                return true;
            }
        }
        return false;
    }

    pub fn getLogCount(self: TestLogger, level: zlog.Level) usize {
        var count: usize = 0;
        for (self.logged_messages.items) |logged| {
            if (logged.level == level) count += 1;
        }
        return count;
    }
};

// Usage in tests
test "user service logs authentication events" {
    var test_logger = TestLogger.init(std.testing.allocator);
    defer test_logger.deinit();

    const user_service = UserService.init(&test_logger);
    try user_service.authenticate("user@example.com", "password123");

    try std.testing.expect(test_logger.hasLoggedMessage(.info, "User authentication successful"));
    try std.testing.expect(test_logger.getLogCount(.err) == 0);
}
```

### 2. Log Monitoring and Alerting

Implement log-based monitoring:

```zig
pub const LogMonitor = struct {
    error_count: std.atomic.Atomic(u64),
    warning_count: std.atomic.Atomic(u64),
    last_error_time: std.atomic.Atomic(i64),
    alert_thresholds: AlertThresholds,

    const AlertThresholds = struct {
        error_rate_per_minute: u32,
        consecutive_errors: u32,
        warning_rate_per_minute: u32,
    };

    pub fn init(thresholds: AlertThresholds) LogMonitor {
        return LogMonitor{
            .error_count = std.atomic.Atomic(u64).init(0),
            .warning_count = std.atomic.Atomic(u64).init(0),
            .last_error_time = std.atomic.Atomic(i64).init(0),
            .alert_thresholds = thresholds,
        };
    }

    pub fn recordLog(self: *LogMonitor, level: zlog.Level) void {
        const now = std.time.timestamp();

        switch (level) {
            .err, .fatal => {
                const error_count = self.error_count.fetchAdd(1, .Monotonic);
                self.last_error_time.store(now, .Monotonic);

                self.checkErrorRateAlert(error_count + 1, now);
            },
            .warn => {
                const warning_count = self.warning_count.fetchAdd(1, .Monotonic);
                self.checkWarningRateAlert(warning_count + 1, now);
            },
            else => {},
        }
    }

    fn checkErrorRateAlert(self: *LogMonitor, error_count: u64, now: i64) void {
        // Check if error rate exceeds threshold
        const errors_per_minute = self.calculateErrorRate(now);
        if (errors_per_minute >= self.alert_thresholds.error_rate_per_minute) {
            self.sendAlert("High error rate detected", errors_per_minute);
        }
    }

    fn checkWarningRateAlert(self: *LogMonitor, warning_count: u64, now: i64) void {
        const warnings_per_minute = self.calculateWarningRate(now);
        if (warnings_per_minute >= self.alert_thresholds.warning_rate_per_minute) {
            self.sendAlert("High warning rate detected", warnings_per_minute);
        }
    }

    fn calculateErrorRate(self: *LogMonitor, now: i64) u32 {
        // Simplified rate calculation
        const total_errors = self.error_count.load(.Monotonic);
        return @intCast(@min(total_errors, std.math.maxInt(u32)));
    }

    fn calculateWarningRate(self: *LogMonitor, now: i64) u32 {
        const total_warnings = self.warning_count.load(.Monotonic);
        return @intCast(@min(total_warnings, std.math.maxInt(u32)));
    }

    fn sendAlert(self: *LogMonitor, message: []const u8, rate: u32) void {
        // Implementation would send actual alerts (email, Slack, etc.)
        std.debug.print("ALERT: {s} - Rate: {d}/minute\n", .{message, rate});
    }
};
```

### 3. Log Analytics Integration

Design logs for analytics and monitoring tools:

```zig
pub const AnalyticsLogger = struct {
    logger: *zlog.Logger,
    session_id: []const u8,

    pub fn init(logger: *zlog.Logger, session_id: []const u8) AnalyticsLogger {
        return AnalyticsLogger{
            .logger = logger,
            .session_id = session_id,
        };
    }

    pub fn logEvent(self: AnalyticsLogger, event_type: []const u8, properties: []const zlog.Field) void {
        var all_fields = std.ArrayList(zlog.Field).init(std.heap.page_allocator);
        defer all_fields.deinit();

        // Standard analytics fields
        all_fields.appendSlice(&[_]zlog.Field{
            zlog.str("event_type", event_type),
            zlog.str("session_id", self.session_id),
            zlog.uint("timestamp", @intCast(std.time.timestamp())),
            zlog.str("source", "application"),
        }) catch return;

        // Custom properties
        all_fields.appendSlice(properties) catch return;

        self.logger.logWithFields(.info, "Analytics event", all_fields.items);
    }

    pub fn logUserAction(self: AnalyticsLogger, action: []const u8, user_id: u64, success: bool) void {
        const properties = [_]zlog.Field{
            zlog.str("action", action),
            zlog.uint("user_id", user_id),
            zlog.boolean("success", success),
        };

        self.logEvent("user_action", &properties);
    }

    pub fn logPerformanceMetric(self: AnalyticsLogger, operation: []const u8, duration_ms: f64, throughput: f64) void {
        const properties = [_]zlog.Field{
            zlog.str("operation", operation),
            zlog.float("duration_ms", duration_ms),
            zlog.float("throughput", throughput),
        };

        self.logEvent("performance_metric", &properties);
    }
};
```

## Deployment Patterns

### 1. Container Logging

Best practices for containerized applications:

```zig
pub fn createContainerLogger(allocator: std.mem.Allocator) !zlog.Logger {
    // In containers, log to stdout/stderr for container orchestration
    return zlog.Logger.init(allocator, .{
        .format = .json,           // Structured logs for log aggregation
        .output_target = .stdout,  // Container stdout
        .buffer_size = 4096,       // Moderate buffer for container env
        .async_io = false,         // Immediate output for container logs
        .level = .info,            // Production level
    });
}

pub const ContainerLogging = struct {
    pub fn addContainerFields(fields: *std.ArrayList(zlog.Field)) !void {
        // Add container-specific metadata
        const container_id = std.os.getenv("HOSTNAME") orelse "unknown";
        const pod_name = std.os.getenv("POD_NAME") orelse "unknown";
        const namespace = std.os.getenv("POD_NAMESPACE") orelse "default";

        try fields.appendSlice(&[_]zlog.Field{
            zlog.str("container_id", container_id),
            zlog.str("pod_name", pod_name),
            zlog.str("namespace", namespace),
        });
    }
};
```

### 2. Microservices Logging

Implement distributed tracing support:

```zig
pub const DistributedLogger = struct {
    logger: *zlog.Logger,
    service_name: []const u8,

    pub fn init(logger: *zlog.Logger, service_name: []const u8) DistributedLogger {
        return DistributedLogger{
            .logger = logger,
            .service_name = service_name,
        };
    }

    pub fn logWithTrace(
        self: DistributedLogger,
        level: zlog.Level,
        message: []const u8,
        trace_id: ?[]const u8,
        span_id: ?[]const u8,
        parent_span_id: ?[]const u8,
        extra_fields: []const zlog.Field,
    ) void {
        var fields = std.ArrayList(zlog.Field).init(std.heap.page_allocator);
        defer fields.deinit();

        // Service identification
        fields.appendSlice(&[_]zlog.Field{
            zlog.str("service", self.service_name),
            zlog.uint("timestamp", @intCast(std.time.timestamp())),
        }) catch return;

        // Distributed tracing fields
        if (trace_id) |tid| {
            fields.append(zlog.str("trace_id", tid)) catch return;
        }
        if (span_id) |sid| {
            fields.append(zlog.str("span_id", sid)) catch return;
        }
        if (parent_span_id) |psid| {
            fields.append(zlog.str("parent_span_id", psid)) catch return;
        }

        // Extra fields
        fields.appendSlice(extra_fields) catch return;

        self.logger.logWithFields(level, message, fields.items);
    }

    pub fn logServiceCall(
        self: DistributedLogger,
        target_service: []const u8,
        operation: []const u8,
        duration_ms: f64,
        success: bool,
        trace_id: ?[]const u8,
    ) void {
        const extra_fields = [_]zlog.Field{
            zlog.str("target_service", target_service),
            zlog.str("operation", operation),
            zlog.float("duration_ms", duration_ms),
            zlog.boolean("success", success),
        };

        self.logWithTrace(.info, "Service call completed", trace_id, null, null, &extra_fields);
    }
};
```

### 3. High-Availability Logging

Implement failover logging for HA systems:

```zig
pub const HALogger = struct {
    primary_logger: zlog.Logger,
    backup_logger: ?zlog.Logger,
    failover_threshold: u32,
    consecutive_failures: std.atomic.Atomic(u32),

    pub fn init(
        allocator: std.mem.Allocator,
        primary_config: zlog.LoggerConfig,
        backup_config: ?zlog.LoggerConfig,
    ) !HALogger {
        const primary = try zlog.Logger.init(allocator, primary_config);
        const backup = if (backup_config) |config|
            try zlog.Logger.init(allocator, config)
        else
            null;

        return HALogger{
            .primary_logger = primary,
            .backup_logger = backup,
            .failover_threshold = 3,
            .consecutive_failures = std.atomic.Atomic(u32).init(0),
        };
    }

    pub fn log(self: *HALogger, level: zlog.Level, comptime fmt: []const u8, args: anytype) void {
        // Try primary logger first
        self.primary_logger.log(level, fmt, args) catch |err| {
            const failures = self.consecutive_failures.fetchAdd(1, .Monotonic);

            // If primary fails and we have backup, use backup
            if (self.backup_logger) |*backup| {
                backup.warn("Primary logger failed, using backup: {}", .{err});
                backup.log(level, fmt, args) catch {
                    // Both loggers failed - emergency logging to stderr
                    std.debug.print("EMERGENCY LOG: {s}\n", .{fmt});
                };
            }

            // If too many consecutive failures, consider primary dead
            if (failures >= self.failover_threshold) {
                if (self.backup_logger) |*backup| {
                    backup.err("Primary logger failed {d} times, switching to backup", .{failures});
                }
            }
        };

        // Reset failure counter on success
        self.consecutive_failures.store(0, .Monotonic);
    }

    pub fn deinit(self: *HALogger) void {
        self.primary_logger.deinit();
        if (self.backup_logger) |*backup| {
            backup.deinit();
        }
    }
};
```

## Common Anti-Patterns

### 1. Avoid These Logging Mistakes

```zig
// ❌ ANTI-PATTERN: Logging in loops without sampling
for (items) |item| {
    logger.debug("Processing item {d}", .{item.id}); // Creates massive log volume
}

// ✅ CORRECT: Sample or aggregate
var processed_count: u32 = 0;
for (items) |item| {
    // Process item...
    processed_count += 1;

    if (processed_count % 1000 == 0) {
        logger.info("Processed {d} items so far", .{processed_count});
    }
}
logger.info("Completed processing {d} items", .{processed_count});

// ❌ ANTI-PATTERN: Logging in error handlers without context
catch |err| {
    logger.err("Error: {}", .{err}); // No context about what failed
}

// ✅ CORRECT: Include context
catch |err| {
    logger.err("Failed to save user profile for user_id={d}: {}", .{user_id, err});
}

// ❌ ANTI-PATTERN: Using string concatenation in log messages
logger.info("User " + user.name + " logged in at " + timestamp); // Inefficient

// ✅ CORRECT: Use formatting
logger.info("User {s} logged in at {d}", .{user.name, timestamp});

// ❌ ANTI-PATTERN: Logging sensitive data
logger.debug("Password validation for: {s}", .{password}); // Security risk

// ✅ CORRECT: Log safely
logger.debug("Password validation completed for user_id={d}", .{user_id});

// ❌ ANTI-PATTERN: Inconsistent log levels
logger.info("Database connection failed"); // Should be error level
logger.err("User preference updated");     // Should be info level

// ✅ CORRECT: Appropriate levels
logger.err("Database connection failed");
logger.info("User preference updated");

// ❌ ANTI-PATTERN: Overly verbose debugging
logger.debug("Entering function processUser");
logger.debug("Creating user object");
logger.debug("Validating user data");
logger.debug("Saving to database");
logger.debug("Exiting function processUser");

// ✅ CORRECT: Meaningful debug information
logger.debug("Processing user registration: user_id={d} validation_time={d}ms", .{user_id, validation_time});
```

### 2. Configuration Anti-Patterns

```zig
// ❌ ANTI-PATTERN: Hardcoded configuration
const logger = zlog.Logger.init(allocator, .{
    .output_target = .{ .file = "/var/log/myapp.log" }, // Hardcoded path
    .level = .debug,                                    // Hardcoded level
});

// ✅ CORRECT: Environment-based configuration
const log_level = parseLogLevel(std.os.getenv("LOG_LEVEL") orelse "info");
const log_file = std.os.getenv("LOG_FILE") orelse "/var/log/myapp.log";

const logger = zlog.Logger.init(allocator, .{
    .output_target = .{ .file = log_file },
    .level = log_level,
});

// ❌ ANTI-PATTERN: Ignoring configuration validation
const config = zlog.LoggerConfig{ .buffer_size = 0 }; // Invalid
const logger = zlog.Logger.init(allocator, config); // Will fail

// ✅ CORRECT: Validate configuration
const config = zlog.LoggerConfig{ .buffer_size = 4096 };
const is_valid = try zlog.validation.validateConfig(allocator, config);
if (!is_valid) return error.InvalidConfiguration;
const logger = try zlog.Logger.init(allocator, config);
```

### 3. Performance Anti-Patterns

```zig
// ❌ ANTI-PATTERN: Synchronous logging in performance-critical paths
fn handleRequest() void {
    logger.info("Request started"); // Blocks on I/O
    // Critical processing...
    logger.info("Request completed"); // Blocks on I/O
}

// ✅ CORRECT: Asynchronous logging for performance
fn handleRequest() void {
    async_logger.info("Request started"); // Non-blocking
    // Critical processing...
    async_logger.info("Request completed"); // Non-blocking
}

// ❌ ANTI-PATTERN: Creating loggers repeatedly
fn processItems(items: []Item) void {
    for (items) |item| {
        var logger = zlog.Logger.init(allocator, config) catch return; // Expensive
        defer logger.deinit();
        logger.info("Processing item {d}", .{item.id});
    }
}

// ✅ CORRECT: Reuse logger instances
fn processItems(items: []Item, logger: *zlog.Logger) void {
    for (items) |item| {
        logger.info("Processing item {d}", .{item.id});
    }
}
```

This comprehensive best practices guide provides the foundation for using zlog effectively in production systems. Following these patterns will help you build maintainable, secure, and performant logging systems that provide valuable insights into your application's behavior.