// Comprehensive error handling for zlog
// Provides detailed error types, error context, and recovery strategies

const std = @import("std");

// Helper function for getting Unix timestamp (Zig 0.16+ compatibility)
inline fn getUnixTimestamp() i64 {
    const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch unreachable;
    return ts.sec;
}

// Main error union for all zlog operations
pub const ZlogError = error{
    // Configuration errors
    InvalidConfiguration,
    FormatNotEnabled,
    OutputTargetNotEnabled,
    AsyncNotEnabled,
    AggregationNotEnabled,
    FilePathRequired,
    InvalidLogLevel,
    InvalidSamplingRate,
    InvalidBufferSize,

    // Runtime errors
    LoggerNotInitialized,
    LoggerAlreadyInitialized,
    BufferOverflow,
    WriteError,
    FlushError,
    FormatError,
    SerializationError,

    // File system errors
    FileNotFound,
    PermissionDenied,
    DiskFull,
    FileCorrupted,
    DirectoryNotFound,
    FileLocked,
    TooManyOpenFiles,

    // Memory errors
    OutOfMemory,
    BufferTooSmall,
    AllocationFailed,

    // Network errors (for future network targets)
    NetworkUnreachable,
    ConnectionRefused,
    TimeoutError,
    ProtocolError,

    // Async errors
    ThreadCreationFailed,
    QueueFull,
    SynchronizationError,

    // Validation errors
    MessageTooLong,
    TooManyFields,
    KeyTooLong,
    ValueTooLong,
    InvalidEncoding,

    // System errors
    SystemResourceExhausted,
    OperationNotSupported,
    InternalError,
};

// Error context for detailed error reporting
pub const ErrorContext = struct {
    error_type: ZlogError,
    message: []const u8,
    location: ErrorLocation,
    details: ?ErrorDetails = null,
    recovery_hint: ?[]const u8 = null,
    timestamp: i64,

    pub const ErrorLocation = struct {
        function: []const u8,
        line: u32,
        file: []const u8,
    };

    pub const ErrorDetails = union(enum) {
        file_error: FileErrorDetails,
        memory_error: MemoryErrorDetails,
        config_error: ConfigErrorDetails,
        validation_error: ValidationErrorDetails,
        system_error: SystemErrorDetails,

        pub const FileErrorDetails = struct {
            file_path: []const u8,
            operation: []const u8,
            system_error: []const u8,
        };

        pub const MemoryErrorDetails = struct {
            requested_size: usize,
            available_size: usize,
            allocation_type: []const u8,
        };

        pub const ConfigErrorDetails = struct {
            field_name: []const u8,
            provided_value: []const u8,
            expected_format: []const u8,
        };

        pub const ValidationErrorDetails = struct {
            field_name: []const u8,
            value_length: usize,
            max_length: usize,
        };

        pub const SystemErrorDetails = struct {
            operation: []const u8,
            system_error_code: i32,
            system_message: []const u8,
        };
    };

    pub fn init(
        error_type: ZlogError,
        comptime message: []const u8,
        comptime function: []const u8,
        comptime file: []const u8,
        comptime line: u32,
    ) ErrorContext {
        return ErrorContext{
            .error_type = error_type,
            .message = message,
            .location = ErrorLocation{
                .function = function,
                .line = line,
                .file = file,
            },
            .timestamp = getUnixTimestamp(),
        };
    }

    pub fn withDetails(self: ErrorContext, details: ErrorDetails) ErrorContext {
        var ctx = self;
        ctx.details = details;
        return ctx;
    }

    pub fn withRecoveryHint(self: ErrorContext, hint: []const u8) ErrorContext {
        var ctx = self;
        ctx.recovery_hint = hint;
        return ctx;
    }

    pub fn print(self: ErrorContext) void {
        std.debug.print("\n❌ zlog Error: {}\n", .{self.error_type});
        std.debug.print("   Message: {s}\n", .{self.message});
        std.debug.print("   Location: {s}() in {s}:{d}\n", .{ self.location.function, self.location.file, self.location.line });
        std.debug.print("   Timestamp: {d}\n", .{self.timestamp});

        if (self.details) |details| {
            switch (details) {
                .file_error => |file_err| {
                    std.debug.print("   File: {s}\n", .{file_err.file_path});
                    std.debug.print("   Operation: {s}\n", .{file_err.operation});
                    std.debug.print("   System Error: {s}\n", .{file_err.system_error});
                },
                .memory_error => |mem_err| {
                    std.debug.print("   Requested: {d} bytes\n", .{mem_err.requested_size});
                    std.debug.print("   Available: {d} bytes\n", .{mem_err.available_size});
                    std.debug.print("   Type: {s}\n", .{mem_err.allocation_type});
                },
                .config_error => |conf_err| {
                    std.debug.print("   Field: {s}\n", .{conf_err.field_name});
                    std.debug.print("   Value: {s}\n", .{conf_err.provided_value});
                    std.debug.print("   Expected: {s}\n", .{conf_err.expected_format});
                },
                .validation_error => |val_err| {
                    std.debug.print("   Field: {s}\n", .{val_err.field_name});
                    std.debug.print("   Length: {d}\n", .{val_err.value_length});
                    std.debug.print("   Max Length: {d}\n", .{val_err.max_length});
                },
                .system_error => |sys_err| {
                    std.debug.print("   Operation: {s}\n", .{sys_err.operation});
                    std.debug.print("   Error Code: {d}\n", .{sys_err.system_error_code});
                    std.debug.print("   Message: {s}\n", .{sys_err.system_message});
                },
            }
        }

        if (self.recovery_hint) |hint| {
            std.debug.print("   💡 Recovery Hint: {s}\n", .{hint});
        }
    }
};

// Error creation macros for consistent error handling
pub fn createError(
    comptime error_type: ZlogError,
    comptime message: []const u8,
    comptime function: []const u8,
    comptime file: []const u8,
    comptime line: u32,
) ErrorContext {
    return ErrorContext.init(error_type, message, function, file, line);
}

// Convenience macros
pub fn fileError(
    comptime message: []const u8,
    file_path: []const u8,
    operation: []const u8,
    system_error: []const u8,
    comptime function: []const u8,
    comptime file: []const u8,
    comptime line: u32,
) ErrorContext {
    return createError(.FileNotFound, message, function, file, line)
        .withDetails(.{
            .file_error = .{
                .file_path = file_path,
                .operation = operation,
                .system_error = system_error,
            },
        })
        .withRecoveryHint("Check file path and permissions");
}

pub fn memoryError(
    comptime message: []const u8,
    requested: usize,
    available: usize,
    allocation_type: []const u8,
    comptime function: []const u8,
    comptime file: []const u8,
    comptime line: u32,
) ErrorContext {
    return createError(.OutOfMemory, message, function, file, line)
        .withDetails(.{
            .memory_error = .{
                .requested_size = requested,
                .available_size = available,
                .allocation_type = allocation_type,
            },
        })
        .withRecoveryHint("Reduce buffer size or increase available memory");
}

pub fn configError(
    comptime message: []const u8,
    field_name: []const u8,
    provided_value: []const u8,
    expected_format: []const u8,
    comptime function: []const u8,
    comptime file: []const u8,
    comptime line: u32,
) ErrorContext {
    return createError(.InvalidConfiguration, message, function, file, line)
        .withDetails(.{
            .config_error = .{
                .field_name = field_name,
                .provided_value = provided_value,
                .expected_format = expected_format,
            },
        })
        .withRecoveryHint("Check configuration documentation");
}

// Error recovery strategies
pub const RecoveryStrategy = enum {
    retry,
    fallback,
    abort,
    ignore,
};

pub const ErrorRecovery = struct {
    strategy: RecoveryStrategy,
    max_retries: u32 = 3,
    fallback_action: ?fn () void = null,

    pub fn shouldRetry(self: ErrorRecovery, attempt: u32) bool {
        return self.strategy == .retry and attempt < self.max_retries;
    }

    pub fn executeFallback(self: ErrorRecovery) void {
        if (self.fallback_action) |action| {
            action();
        }
    }
};

// Error categorization for handling
pub fn isRecoverable(err: ZlogError) bool {
    return switch (err) {
        .OutOfMemory, .DiskFull, .NetworkUnreachable, .TimeoutError => true,
        .FileNotFound, .PermissionDenied, .InvalidConfiguration => false,
        else => false,
    };
}

pub fn isTemporary(err: ZlogError) bool {
    return switch (err) {
        .NetworkUnreachable, .TimeoutError, .QueueFull, .FileLocked => true,
        else => false,
    };
}

pub fn requiresUserAction(err: ZlogError) bool {
    return switch (err) {
        .InvalidConfiguration, .FilePathRequired, .FormatNotEnabled => true,
        else => false,
    };
}

// Error aggregation for monitoring
pub const ErrorStats = struct {
    total_errors: u64 = 0,
    error_counts: std.AutoHashMap(ZlogError, u64),
    last_error: ?ErrorContext = null,
    first_error_time: ?i64 = null,

    pub fn init(allocator: std.mem.Allocator) ErrorStats {
        return ErrorStats{
            .error_counts = std.AutoHashMap(ZlogError, u64).init(allocator),
        };
    }

    pub fn deinit(self: *ErrorStats) void {
        self.error_counts.deinit();
    }

    pub fn recordError(self: *ErrorStats, error_ctx: ErrorContext) void {
        self.total_errors += 1;
        self.last_error = error_ctx;

        if (self.first_error_time == null) {
            self.first_error_time = error_ctx.timestamp;
        }

        const count = self.error_counts.get(error_ctx.error_type) orelse 0;
        self.error_counts.put(error_ctx.error_type, count + 1) catch {};
    }

    pub fn getErrorRate(self: ErrorStats) f64 {
        if (self.first_error_time == null) return 0.0;

        const duration = getUnixTimestamp() - self.first_error_time.?;
        if (duration <= 0) return 0.0;

        return @as(f64, @floatFromInt(self.total_errors)) / @as(f64, @floatFromInt(duration));
    }

    pub fn printSummary(self: ErrorStats) void {
        std.debug.print("\n📊 Error Statistics\n");
        std.debug.print("==================\n");
        std.debug.print("Total errors: {d}\n", .{self.total_errors});
        std.debug.print("Error rate: {d:.2} errors/second\n", .{self.getErrorRate()});

        if (self.last_error) |last| {
            std.debug.print("Last error: {} at {d}\n", .{ last.error_type, last.timestamp });
        }

        std.debug.print("\nError breakdown:\n");
        var iterator = self.error_counts.iterator();
        while (iterator.next()) |entry| {
            std.debug.print("  {}: {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }
};

// Test error handling
const testing = std.testing;

test "error context creation" {
    const ctx = createError(.InvalidConfiguration, "Test error", "test_function", "test.zig", 123);

    try testing.expect(ctx.error_type == .InvalidConfiguration);
    try testing.expect(std.mem.eql(u8, ctx.message, "Test error"));
    try testing.expect(std.mem.eql(u8, ctx.location.function, "test_function"));
}

test "error categorization" {
    try testing.expect(isRecoverable(.OutOfMemory));
    try testing.expect(!isRecoverable(.InvalidConfiguration));
    try testing.expect(isTemporary(.TimeoutError));
    try testing.expect(requiresUserAction(.FilePathRequired));
}

test "error stats" {
    var stats = ErrorStats.init(testing.allocator);
    defer stats.deinit();

    const ctx1 = createError(.OutOfMemory, "Memory error", "func1", "file1.zig", 10);
    const ctx2 = createError(.FileNotFound, "File error", "func2", "file2.zig", 20);

    stats.recordError(ctx1);
    stats.recordError(ctx2);

    try testing.expect(stats.total_errors == 2);
    try testing.expect(stats.error_counts.get(.OutOfMemory).? == 1);
    try testing.expect(stats.error_counts.get(.FileNotFound).? == 1);
}