// Stable Public API for zlog v1.0
// This module defines the stable public interface that will be maintained
// across all v1.x releases with semantic versioning guarantees

const std = @import("std");

// Re-export core types with stability guarantees
pub const Level = @import("root.zig").Level;
pub const Format = @import("root.zig").Format;
pub const OutputTarget = @import("root.zig").OutputTarget;
pub const Field = @import("root.zig").Field;
pub const LogEntry = @import("root.zig").LogEntry;
pub const LoggerConfig = @import("root.zig").LoggerConfig;
pub const Logger = @import("root.zig").Logger;

// Stable API version
pub const API_VERSION = "1.0.0";
pub const API_MAJOR = 1;
pub const API_MINOR = 0;
pub const API_PATCH = 0;

// Stability guarantees for public API
pub const Stability = struct {
    // Level enum: STABLE - values and names will not change
    // New levels may be added with higher numeric values
    pub const level_enum_stable = true;

    // Format enum: STABLE - existing formats will not change
    // New formats may be added
    pub const format_enum_stable = true;

    // OutputTarget enum: STABLE - existing targets will not change
    // New targets may be added
    pub const output_target_stable = true;

    // Field structure: STABLE - layout and types will not change
    // New field value types may be added
    pub const field_struct_stable = true;

    // LoggerConfig: STABLE - existing fields will maintain compatibility
    // New optional fields may be added with sensible defaults
    pub const logger_config_stable = true;

    // Logger methods: STABLE - public methods will maintain signatures
    // New methods may be added
    pub const logger_methods_stable = true;
};

// API Compatibility Helpers
pub fn checkApiCompatibility(required_major: u32, required_minor: u32) bool {
    // Major version must match exactly
    if (API_MAJOR != required_major) return false;

    // Minor version must be >= required (backward compatibility)
    return API_MINOR >= required_minor;
}

pub fn getApiVersionString() []const u8 {
    return API_VERSION;
}

// Default convenience constructors with stability guarantees
pub const Defaults = struct {
    // Default logger configuration - guaranteed to remain stable
    pub fn loggerConfig() LoggerConfig {
        return LoggerConfig{
            .level = .info,
            .format = .text,
            .output_target = .stdout,
            .buffer_size = 4096,
            .sampling_rate = 1.0,
        };
    }

    // Default field constructors
    pub fn stringField(key: []const u8, value: []const u8) Field {
        return Field{
            .key = key,
            .value = .{ .string = value },
        };
    }

    pub fn intField(key: []const u8, value: i64) Field {
        return Field{
            .key = key,
            .value = .{ .int = value },
        };
    }

    pub fn uintField(key: []const u8, value: u64) Field {
        return Field{
            .key = key,
            .value = .{ .uint = value },
        };
    }

    pub fn floatField(key: []const u8, value: f64) Field {
        return Field{
            .key = key,
            .value = .{ .float = value },
        };
    }

    pub fn boolField(key: []const u8, value: bool) Field {
        return Field{
            .key = key,
            .value = .{ .boolean = value },
        };
    }
};

// Common usage patterns with stability guarantees
pub const Patterns = struct {
    // Create a basic console logger
    pub fn createConsoleLogger(allocator: std.mem.Allocator) !Logger {
        return Logger.init(allocator, Defaults.loggerConfig());
    }

    // Create a file logger with rotation
    pub fn createFileLogger(allocator: std.mem.Allocator, file_path: []const u8) !Logger {
        var config = Defaults.loggerConfig();
        config.output_target = .file;
        config.file_path = file_path;
        config.max_file_size = 10 * 1024 * 1024; // 10MB
        config.max_backup_files = 5;
        return Logger.init(allocator, config);
    }

    // Create a high-performance logger
    pub fn createHighPerformanceLogger(allocator: std.mem.Allocator) !Logger {
        var config = Defaults.loggerConfig();
        config.buffer_size = 16384;
        config.format = .binary;
        return Logger.init(allocator, config);
    }

    // Create an async logger
    pub fn createAsyncLogger(allocator: std.mem.Allocator) !Logger {
        var config = Defaults.loggerConfig();
        config.async_io = true;
        config.buffer_size = 8192;
        return Logger.init(allocator, config);
    }

    // Create a structured JSON logger
    pub fn createJsonLogger(allocator: std.mem.Allocator) !Logger {
        var config = Defaults.loggerConfig();
        config.format = .json;
        return Logger.init(allocator, config);
    }
};

// Error types that are part of the stable API
pub const ApiError = error{
    // Configuration errors
    InvalidConfiguration,
    UnsupportedFormat,
    UnsupportedOutputTarget,

    // Runtime errors
    LoggerNotInitialized,
    BufferOverflow,
    WriteError,

    // File errors (when file targets enabled)
    FileNotFound,
    PermissionDenied,
    DiskFull,

    // Memory errors
    OutOfMemory,

    // Version compatibility
    IncompatibleApiVersion,
};

// Stable format validation
pub fn validateFormat(format: Format) ApiError!void {
    switch (format) {
        .text => {}, // Always supported
        .json => {
            if (!Format.json.isAvailable()) {
                return ApiError.UnsupportedFormat;
            }
        },
        .binary => {
            if (!Format.binary.isAvailable()) {
                return ApiError.UnsupportedFormat;
            }
        },
    }
}

// Stable output target validation
pub fn validateOutputTarget(target: OutputTarget) ApiError!void {
    switch (target) {
        .stdout, .stderr => {}, // Always supported
        .file => {
            if (!OutputTarget.file.isAvailable()) {
                return ApiError.UnsupportedOutputTarget;
            }
        },
    }
}

// Version checking for client compatibility
pub fn ensureCompatibility(client_version: []const u8) ApiError!void {
    // Parse client version
    var parts = std.mem.split(u8, client_version, ".");
    const major_str = parts.next() orelse return ApiError.IncompatibleApiVersion;
    const minor_str = parts.next() orelse return ApiError.IncompatibleApiVersion;

    const major = std.fmt.parseInt(u32, major_str, 10) catch return ApiError.IncompatibleApiVersion;
    const minor = std.fmt.parseInt(u32, minor_str, 10) catch return ApiError.IncompatibleApiVersion;

    if (!checkApiCompatibility(major, minor)) {
        return ApiError.IncompatibleApiVersion;
    }
}

// Configuration builder pattern for complex setups
pub const ConfigBuilder = struct {
    config: LoggerConfig,

    pub fn init() ConfigBuilder {
        return ConfigBuilder{
            .config = Defaults.loggerConfig(),
        };
    }

    pub fn level(self: *ConfigBuilder, log_level: Level) *ConfigBuilder {
        self.config.level = log_level;
        return self;
    }

    pub fn format(self: *ConfigBuilder, log_format: Format) *ConfigBuilder {
        self.config.format = log_format;
        return self;
    }

    pub fn output(self: *ConfigBuilder, target: OutputTarget) *ConfigBuilder {
        self.config.output_target = target;
        return self;
    }

    pub fn file(self: *ConfigBuilder, path: []const u8) *ConfigBuilder {
        self.config.output_target = .file;
        self.config.file_path = path;
        return self;
    }

    pub fn bufferSize(self: *ConfigBuilder, size: usize) *ConfigBuilder {
        self.config.buffer_size = size;
        return self;
    }

    pub fn async(self: *ConfigBuilder, enable: bool) *ConfigBuilder {
        self.config.async_io = enable;
        return self;
    }

    pub fn sampling(self: *ConfigBuilder, rate: f32) *ConfigBuilder {
        self.config.sampling_rate = rate;
        return self;
    }

    pub fn build(self: ConfigBuilder) LoggerConfig {
        return self.config;
    }

    pub fn buildLogger(self: ConfigBuilder, allocator: std.mem.Allocator) !Logger {
        return Logger.init(allocator, self.config);
    }
};

// Test the stable API
test "api: version compatibility" {
    try testing.expect(checkApiCompatibility(1, 0));
    try testing.expect(!checkApiCompatibility(2, 0));
    try testing.expect(!checkApiCompatibility(0, 9));
}

test "api: default constructors" {
    const config = Defaults.loggerConfig();
    try testing.expect(config.level == .info);
    try testing.expect(config.format == .text);
}

test "api: field constructors" {
    const str_field = Defaults.stringField("test", "value");
    try testing.expect(std.mem.eql(u8, str_field.key, "test"));

    const int_field = Defaults.intField("number", 42);
    try testing.expect(int_field.value.int == 42);
}

test "api: config builder" {
    const config = ConfigBuilder.init()
        .level(.debug)
        .format(.json)
        .bufferSize(8192)
        .build();

    try testing.expect(config.level == .debug);
    try testing.expect(config.format == .json);
    try testing.expect(config.buffer_size == 8192);
}

test "api: format validation" {
    try validateFormat(.text); // Should always pass

    // These depend on build options
    validateFormat(.json) catch |err| {
        try testing.expect(err == ApiError.UnsupportedFormat);
    };
}