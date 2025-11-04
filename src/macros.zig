// Convenience macros and helper functions for common zlog patterns
// Provides ergonomic shortcuts while maintaining type safety

const std = @import("std");
const zlog = @import("root.zig");

// Quick field creation macros
pub fn str(key: []const u8, value: []const u8) zlog.Field {
    return .{ .key = key, .value = .{ .string = value } };
}

pub fn int(key: []const u8, value: i64) zlog.Field {
    return .{ .key = key, .value = .{ .int = value } };
}

pub fn uint(key: []const u8, value: u64) zlog.Field {
    return .{ .key = key, .value = .{ .uint = value } };
}

pub fn float(key: []const u8, value: f64) zlog.Field {
    return .{ .key = key, .value = .{ .float = value } };
}

pub fn boolean(key: []const u8, value: bool) zlog.Field {
    return .{ .key = key, .value = .{ .boolean = value } };
}

// Common field patterns
pub const CommonFields = struct {
    // Request/Response patterns
    pub fn requestId(id: []const u8) zlog.Field {
        return str("request_id", id);
    }

    pub fn userId(id: u64) zlog.Field {
        return uint("user_id", id);
    }

    pub fn sessionId(id: []const u8) zlog.Field {
        return str("session_id", id);
    }

    pub fn statusCode(code: u32) zlog.Field {
        return uint("status_code", code);
    }

    pub fn duration(ms: f64) zlog.Field {
        return float("duration_ms", ms);
    }

    pub fn latency(ms: f64) zlog.Field {
        return float("latency_ms", ms);
    }

    // Error patterns
    pub fn errorCode(code: []const u8) zlog.Field {
        return str("error_code", code);
    }

    pub fn errorMessage(msg: []const u8) zlog.Field {
        return str("error_message", msg);
    }

    pub fn stackTrace(trace: []const u8) zlog.Field {
        return str("stack_trace", trace);
    }

    // Performance patterns
    pub fn memoryUsage(bytes: u64) zlog.Field {
        return uint("memory_bytes", bytes);
    }

    pub fn cpuUsage(percent: f64) zlog.Field {
        return float("cpu_percent", percent);
    }

    pub fn throughput(ops_per_sec: f64) zlog.Field {
        return float("ops_per_sec", ops_per_sec);
    }

    // Database patterns
    pub fn queryTime(ms: f64) zlog.Field {
        return float("query_time_ms", ms);
    }

    pub fn rowCount(count: u64) zlog.Field {
        return uint("row_count", count);
    }

    pub fn tableName(name: []const u8) zlog.Field {
        return str("table_name", name);
    }

    // Network patterns
    pub fn remoteAddr(addr: []const u8) zlog.Field {
        return str("remote_addr", addr);
    }

    pub fn userAgent(agent: []const u8) zlog.Field {
        return str("user_agent", agent);
    }

    pub fn method(m: []const u8) zlog.Field {
        return str("method", m);
    }

    pub fn path(p: []const u8) zlog.Field {
        return str("path", p);
    }

    // File patterns
    pub fn fileName(name: []const u8) zlog.Field {
        return str("file_name", name);
    }

    pub fn fileSize(bytes: u64) zlog.Field {
        return uint("file_size", bytes);
    }

    pub fn lineNumber(line: u32) zlog.Field {
        return uint("line_number", line);
    }
};

// Structured logging with predefined contexts
pub const LogContext = struct {
    fields: std.ArrayList(zlog.Field),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LogContext {
        return LogContext{
            .fields = std.ArrayList(zlog.Field).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LogContext) void {
        self.fields.deinit();
    }

    pub fn add(self: *LogContext, field: zlog.Field) !*LogContext {
        try self.fields.append(field);
        return self;
    }

    pub fn addStr(self: *LogContext, key: []const u8, value: []const u8) !*LogContext {
        return self.add(str(key, value));
    }

    pub fn addInt(self: *LogContext, key: []const u8, value: i64) !*LogContext {
        return self.add(int(key, value));
    }

    pub fn addUint(self: *LogContext, key: []const u8, value: u64) !*LogContext {
        return self.add(uint(key, value));
    }

    pub fn addFloat(self: *LogContext, key: []const u8, value: f64) !*LogContext {
        return self.add(float(key, value));
    }

    pub fn addBool(self: *LogContext, key: []const u8, value: bool) !*LogContext {
        return self.add(boolean(key, value));
    }

    // Common context builders
    pub fn withRequest(self: *LogContext, request_id: []const u8, user_id: u64) !*LogContext {
        try self.add(CommonFields.requestId(request_id));
        try self.add(CommonFields.userId(user_id));
        return self;
    }

    pub fn withTiming(self: *LogContext, start_time: i64) !*LogContext {
        const now = (std.time.Timer.start() catch unreachable).read();
        const duration = @as(f64, @floatFromInt(now - start_time)) / 1_000_000.0; // Convert to ms
        try self.add(CommonFields.duration(duration));
        return self;
    }

    pub fn withError(self: *LogContext, error_code: []const u8, error_msg: []const u8) !*LogContext {
        try self.add(CommonFields.errorCode(error_code));
        try self.add(CommonFields.errorMessage(error_msg));
        return self;
    }

    pub fn withHttp(self: *LogContext, method: []const u8, path: []const u8, status: u32) !*LogContext {
        try self.add(CommonFields.method(method));
        try self.add(CommonFields.path(path));
        try self.add(CommonFields.statusCode(status));
        return self;
    }

    pub fn log(self: LogContext, logger: *zlog.Logger, level: zlog.Level, message: []const u8) void {
        logger.logWithFields(level, message, self.fields.items);
    }

    pub fn debug(self: LogContext, logger: *zlog.Logger, message: []const u8) void {
        self.log(logger, .debug, message);
    }

    pub fn info(self: LogContext, logger: *zlog.Logger, message: []const u8) void {
        self.log(logger, .info, message);
    }

    pub fn warn(self: LogContext, logger: *zlog.Logger, message: []const u8) void {
        self.log(logger, .warn, message);
    }

    pub fn err(self: LogContext, logger: *zlog.Logger, message: []const u8) void {
        self.log(logger, .err, message);
    }

    pub fn fatal(self: LogContext, logger: *zlog.Logger, message: []const u8) void {
        self.log(logger, .fatal, message);
    }
};

// Scoped logging for RAII-style logging
pub const ScopedLogger = struct {
    logger: *zlog.Logger,
    context: LogContext,
    scope_name: []const u8,
    start_time: i64,

    pub fn init(logger: *zlog.Logger, allocator: std.mem.Allocator, scope_name: []const u8) !ScopedLogger {
        var context = LogContext.init(allocator);
        try context.addStr("scope", scope_name);

        const scoped = ScopedLogger{
            .logger = logger,
            .context = context,
            .scope_name = scope_name,
            .start_time = (std.time.Timer.start() catch unreachable).read(),
        };

        // Log scope entry
        scoped.context.debug(logger, "Entering scope");

        return scoped;
    }

    pub fn deinit(self: *ScopedLogger) void {
        // Log scope exit with timing
        const now = (std.time.Timer.start() catch unreachable).read();
        const duration = @as(f64, @floatFromInt(now - self.start_time)) / 1_000_000.0;

        // Create exit context with duration
        var exit_context = LogContext.init(self.context.allocator);
        defer exit_context.deinit();

        exit_context.addStr("scope", self.scope_name) catch {};
        exit_context.addFloat("duration_ms", duration) catch {};

        exit_context.debug(self.logger, "Exiting scope");

        self.context.deinit();
    }

    pub fn debug(self: *ScopedLogger, message: []const u8) void {
        self.context.debug(self.logger, message);
    }

    pub fn info(self: *ScopedLogger, message: []const u8) void {
        self.context.info(self.logger, message);
    }

    pub fn warn(self: *ScopedLogger, message: []const u8) void {
        self.context.warn(self.logger, message);
    }

    pub fn err(self: *ScopedLogger, message: []const u8) void {
        self.context.err(self.logger, message);
    }

    pub fn addField(self: *ScopedLogger, field: zlog.Field) !void {
        try self.context.add(field);
    }
};

// Performance logging helpers
pub const PerfLogger = struct {
    // Measure and log function execution time
    pub fn timeFunction(
        logger: *zlog.Logger,
        allocator: std.mem.Allocator,
        function_name: []const u8,
        comptime func: anytype,
        args: anytype,
    ) !@TypeOf(@call(.auto, func, args)) {
        const start = (std.time.Timer.start() catch unreachable).read();

        const result = try @call(.auto, func, args);

        const end = (std.time.Timer.start() catch unreachable).read();
        const duration = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;

        var context = LogContext.init(allocator);
        defer context.deinit();

        try context.addStr("function", function_name);
        try context.addFloat("execution_time_ms", duration);

        context.info(logger, "Function execution completed");

        return result;
    }

    // Log performance metrics
    pub fn logMetrics(
        logger: *zlog.Logger,
        allocator: std.mem.Allocator,
        operation: []const u8,
        count: u64,
        duration_ms: f64,
    ) !void {
        var context = LogContext.init(allocator);
        defer context.deinit();

        try context.addStr("operation", operation);
        try context.addUint("count", count);
        try context.addFloat("duration_ms", duration_ms);
        try context.addFloat("ops_per_sec", @as(f64, @floatFromInt(count)) / (duration_ms / 1000.0));

        context.info(logger, "Performance metrics");
    }
};

// Error logging helpers
pub const ErrorLogger = struct {
    pub fn logError(
        logger: *zlog.Logger,
        allocator: std.mem.Allocator,
        err: anyerror,
        context_msg: []const u8,
        extra_fields: []const zlog.Field,
    ) !void {
        var context = LogContext.init(allocator);
        defer context.deinit();

        try context.addStr("error", @errorName(err));
        try context.addStr("context", context_msg);

        for (extra_fields) |field| {
            try context.add(field);
        }

        context.err(logger, "Error occurred");
    }

    pub fn logException(
        logger: *zlog.Logger,
        allocator: std.mem.Allocator,
        err: anyerror,
        message: []const u8,
        file: []const u8,
        line: u32,
    ) !void {
        var context = LogContext.init(allocator);
        defer context.deinit();

        try context.addStr("error", @errorName(err));
        try context.addStr("file", file);
        try context.addUint("line", line);

        context.err(logger, message);
    }
};

// HTTP request logging
pub const HttpLogger = struct {
    pub fn logRequest(
        logger: *zlog.Logger,
        allocator: std.mem.Allocator,
        method: []const u8,
        path: []const u8,
        status: u32,
        duration_ms: f64,
        user_id: ?u64,
    ) !void {
        var context = LogContext.init(allocator);
        defer context.deinit();

        try context.withHttp(method, path, status);
        try context.addFloat("response_time_ms", duration_ms);

        if (user_id) |uid| {
            try context.addUint("user_id", uid);
        }

        context.info(logger, "HTTP request completed");
    }
};

// Convenience functions for quick logging
pub const Quick = struct {
    // Quick structured logging without creating contexts
    pub fn logWithFields(
        logger: *zlog.Logger,
        level: zlog.Level,
        message: []const u8,
        fields: []const zlog.Field,
    ) void {
        logger.logWithFields(level, message, fields);
    }

    // Quick field array creation
    pub fn fields(comptime field_list: anytype) [field_list.len]zlog.Field {
        return field_list;
    }
};

// Test the macros
const testing = std.testing;

test "macros: field creation" {
    const field = str("test", "value");
    try testing.expect(std.mem.eql(u8, field.key, "test"));
    try testing.expect(std.mem.eql(u8, field.value.string, "value"));

    const int_field = int("number", 42);
    try testing.expect(int_field.value.int == 42);
}

test "macros: log context" {
    var context = LogContext.init(testing.allocator);
    defer context.deinit();

    try context.addStr("test", "value");
    try context.addInt("number", 42);

    try testing.expect(context.fields.items.len == 2);
}

test "macros: common fields" {
    const req_id = CommonFields.requestId("abc-123");
    try testing.expect(std.mem.eql(u8, req_id.key, "request_id"));
    try testing.expect(std.mem.eql(u8, req_id.value.string, "abc-123"));

    const status = CommonFields.statusCode(200);
    try testing.expect(status.value.uint == 200);
}