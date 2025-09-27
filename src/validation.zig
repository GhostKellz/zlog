// Comprehensive configuration validation for zlog
// Provides detailed validation, suggestions, and error reporting

const std = @import("std");
const zlog = @import("root.zig");
const errors = @import("errors.zig");
const build_options = @import("build_options");

// Validation result with detailed feedback
pub const ValidationResult = struct {
    valid: bool,
    errors: std.ArrayList(ValidationError),
    warnings: std.ArrayList(ValidationWarning),
    suggestions: std.ArrayList(ValidationSuggestion),

    const ValidationError = struct {
        field: []const u8,
        message: []const u8,
        error_type: errors.ZlogError,
    };

    const ValidationWarning = struct {
        field: []const u8,
        message: []const u8,
        impact: Impact,

        const Impact = enum { low, medium, high };
    };

    const ValidationSuggestion = struct {
        field: []const u8,
        current_value: []const u8,
        suggested_value: []const u8,
        reason: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) ValidationResult {
        return ValidationResult{
            .valid = true,
            .errors = std.ArrayList(ValidationError).init(allocator),
            .warnings = std.ArrayList(ValidationWarning).init(allocator),
            .suggestions = std.ArrayList(ValidationSuggestion).init(allocator),
        };
    }

    pub fn deinit(self: *ValidationResult) void {
        self.errors.deinit();
        self.warnings.deinit();
        self.suggestions.deinit();
    }

    pub fn addError(self: *ValidationResult, field: []const u8, message: []const u8, error_type: errors.ZlogError) !void {
        self.valid = false;
        try self.errors.append(.{
            .field = field,
            .message = message,
            .error_type = error_type,
        });
    }

    pub fn addWarning(self: *ValidationResult, field: []const u8, message: []const u8, impact: ValidationWarning.Impact) !void {
        try self.warnings.append(.{
            .field = field,
            .message = message,
            .impact = impact,
        });
    }

    pub fn addSuggestion(self: *ValidationResult, field: []const u8, current: []const u8, suggested: []const u8, reason: []const u8) !void {
        try self.suggestions.append(.{
            .field = field,
            .current_value = current,
            .suggested_value = suggested,
            .reason = reason,
        });
    }

    pub fn print(self: ValidationResult) void {
        if (self.valid) {
            std.debug.print("✅ Configuration validation passed\n");
        } else {
            std.debug.print("❌ Configuration validation failed\n");
        }

        if (self.errors.items.len > 0) {
            std.debug.print("\n🚨 Errors:\n");
            for (self.errors.items) |err| {
                std.debug.print("   {s}: {s} ({})\n", .{ err.field, err.message, err.error_type });
            }
        }

        if (self.warnings.items.len > 0) {
            std.debug.print("\n⚠️  Warnings:\n");
            for (self.warnings.items) |warn| {
                const impact_icon = switch (warn.impact) {
                    .low => "🟡",
                    .medium => "🟠",
                    .high => "🔴",
                };
                std.debug.print("   {s} {s}: {s}\n", .{ impact_icon, warn.field, warn.message });
            }
        }

        if (self.suggestions.items.len > 0) {
            std.debug.print("\n💡 Suggestions:\n");
            for (self.suggestions.items) |sugg| {
                std.debug.print("   {s}: '{s}' → '{s}' ({s})\n", .{ sugg.field, sugg.current_value, sugg.suggested_value, sugg.reason });
            }
        }
    }
};

// Comprehensive configuration validator
pub const ConfigValidator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConfigValidator {
        return ConfigValidator{ .allocator = allocator };
    }

    pub fn validate(self: ConfigValidator, config: zlog.LoggerConfig) !ValidationResult {
        var result = ValidationResult.init(self.allocator);

        // Validate each field
        try self.validateLevel(config.level, &result);
        try self.validateFormat(config.format, &result);
        try self.validateOutputTarget(config.output_target, config.file_path, &result);
        try self.validateBufferSize(config.buffer_size, &result);
        try self.validateSamplingRate(config.sampling_rate, &result);
        try self.validateFileSettings(config, &result);
        try self.validateAsyncSettings(config, &result);
        try self.validateAggregationSettings(config, &result);

        // Cross-field validation
        try self.validateCombinations(config, &result);

        return result;
    }

    fn validateLevel(self: ConfigValidator, level: zlog.Level, result: *ValidationResult) !void {
        _ = self;
        // Level validation is mostly type-safe, but we can provide guidance
        switch (level) {
            .debug => {
                try result.addWarning("level", "Debug level will log all messages - may impact performance", .medium);
            },
            .fatal => {
                try result.addWarning("level", "Fatal level will only log critical errors - may miss important information", .medium);
            },
            else => {},
        }
    }

    fn validateFormat(self: ConfigValidator, format: zlog.Format, result: *ValidationResult) !void {
        _ = self;
        switch (format) {
            .text => {}, // Always available
            .json => {
                if (!build_options.enable_json) {
                    try result.addError("format", "JSON format requested but not enabled in build", .FormatNotEnabled);
                    try result.addSuggestion("format", "json", "text", "JSON format disabled, use text format");
                }
            },
            .binary => {
                if (!build_options.enable_binary_format) {
                    try result.addError("format", "Binary format requested but not enabled in build", .FormatNotEnabled);
                    try result.addSuggestion("format", "binary", "text", "Binary format disabled, use text format");
                }
            },
        }
    }

    fn validateOutputTarget(self: ConfigValidator, target: zlog.OutputTarget, file_path: ?[]const u8, result: *ValidationResult) !void {
        _ = self;
        switch (target) {
            .stdout, .stderr => {}, // Always available
            .file => {
                if (!build_options.enable_file_targets) {
                    try result.addError("output_target", "File output requested but not enabled in build", .OutputTargetNotEnabled);
                    try result.addSuggestion("output_target", "file", "stdout", "File targets disabled, use stdout");
                    return;
                }

                if (file_path == null) {
                    try result.addError("file_path", "File output requires file_path to be set", .FilePathRequired);
                    return;
                }

                const path = file_path.?;
                if (path.len == 0) {
                    try result.addError("file_path", "File path cannot be empty", .InvalidConfiguration);
                }

                // Validate file path characteristics
                if (std.mem.indexOf(u8, path, "..") != null) {
                    try result.addWarning("file_path", "File path contains '..' - potential security risk", .high);
                }

                if (!std.fs.path.isAbsolute(path)) {
                    try result.addWarning("file_path", "Relative file paths may be problematic in different working directories", .medium);
                }

                // Check if parent directory exists (best effort)
                const dir_path = std.fs.path.dirname(path) orelse ".";
                std.fs.cwd().openDir(dir_path, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        try result.addWarning("file_path", "Parent directory may not exist", .high);
                    },
                    error.AccessDenied => {
                        try result.addWarning("file_path", "May not have write access to directory", .high);
                    },
                    else => {},
                };
            },
        }
    }

    fn validateBufferSize(self: ConfigValidator, buffer_size: usize, result: *ValidationResult) !void {
        _ = self;
        const min_size = 256;
        const max_size = 1024 * 1024; // 1MB
        const recommended_min = 1024;
        const recommended_max = 64 * 1024; // 64KB

        if (buffer_size < min_size) {
            try result.addError("buffer_size", "Buffer size too small, minimum 256 bytes", .InvalidBufferSize);
            try result.addSuggestion("buffer_size", try std.fmt.allocPrint(self.allocator, "{d}", .{buffer_size}), "1024", "Minimum safe buffer size");
        } else if (buffer_size > max_size) {
            try result.addError("buffer_size", "Buffer size too large, maximum 1MB", .InvalidBufferSize);
            try result.addSuggestion("buffer_size", try std.fmt.allocPrint(self.allocator, "{d}", .{buffer_size}), "65536", "Reasonable maximum buffer size");
        } else {
            if (buffer_size < recommended_min) {
                try result.addWarning("buffer_size", "Small buffer size may impact performance", .medium);
                try result.addSuggestion("buffer_size", try std.fmt.allocPrint(self.allocator, "{d}", .{buffer_size}), "4096", "Recommended minimum for good performance");
            } else if (buffer_size > recommended_max) {
                try result.addWarning("buffer_size", "Large buffer size may waste memory", .low);
                try result.addSuggestion("buffer_size", try std.fmt.allocPrint(self.allocator, "{d}", .{buffer_size}), "8192", "Good balance of performance and memory usage");
            }
        }
    }

    fn validateSamplingRate(self: ConfigValidator, sampling_rate: f32, result: *ValidationResult) !void {
        _ = self;
        if (sampling_rate < 0.0 or sampling_rate > 1.0) {
            try result.addError("sampling_rate", "Sampling rate must be between 0.0 and 1.0", .InvalidSamplingRate);
            try result.addSuggestion("sampling_rate", try std.fmt.allocPrint(self.allocator, "{d:.2}", .{sampling_rate}), "1.0", "No sampling");
        } else if (sampling_rate < 0.01) {
            try result.addWarning("sampling_rate", "Very low sampling rate may miss important logs", .medium);
        } else if (sampling_rate < 0.1) {
            try result.addWarning("sampling_rate", "Low sampling rate - ensure this is intentional", .low);
        }
    }

    fn validateFileSettings(self: ConfigValidator, config: zlog.LoggerConfig, result: *ValidationResult) !void {
        _ = self;
        if (config.output_target == .file and build_options.enable_file_targets) {
            if (config.max_file_size < 1024) {
                try result.addWarning("max_file_size", "Very small file size may cause frequent rotations", .medium);
            }

            if (config.max_file_size > 100 * 1024 * 1024) { // 100MB
                try result.addWarning("max_file_size", "Large file size may impact log processing tools", .low);
            }

            if (config.max_backup_files == 0) {
                try result.addWarning("max_backup_files", "No backup files - logs will be lost on rotation", .medium);
            }

            if (config.max_backup_files > 100) {
                try result.addWarning("max_backup_files", "Many backup files may consume significant disk space", .low);
            }
        }
    }

    fn validateAsyncSettings(self: ConfigValidator, config: zlog.LoggerConfig, result: *ValidationResult) !void {
        _ = self;
        if (config.async_io) {
            if (!build_options.enable_async) {
                try result.addError("async_io", "Async I/O requested but not enabled in build", .AsyncNotEnabled);
                try result.addSuggestion("async_io", "true", "false", "Async I/O disabled in build");
            }

            // Async I/O recommendations
            if (config.buffer_size < 4096) {
                try result.addSuggestion("buffer_size", try std.fmt.allocPrint(self.allocator, "{d}", .{config.buffer_size}), "8192", "Larger buffers work better with async I/O");
            }
        }
    }

    fn validateAggregationSettings(self: ConfigValidator, config: zlog.LoggerConfig, result: *ValidationResult) !void {
        _ = self;
        if (config.enable_batching or config.enable_deduplication) {
            if (!build_options.enable_aggregation) {
                try result.addError("aggregation", "Aggregation features requested but not enabled in build", .AggregationNotEnabled);
                try result.addSuggestion("enable_batching", "true", "false", "Aggregation disabled in build");
            }

            if (config.enable_batching and config.batch_size == 0) {
                try result.addError("batch_size", "Batch size cannot be zero when batching is enabled", .InvalidConfiguration);
            }

            if (config.enable_deduplication and config.dedup_window_ms == 0) {
                try result.addWarning("dedup_window_ms", "Zero deduplication window may not be effective", .medium);
            }
        }
    }

    fn validateCombinations(self: ConfigValidator, config: zlog.LoggerConfig, result: *ValidationResult) !void {
        _ = self;
        // Check for suboptimal combinations
        if (config.format == .binary and config.async_io) {
            // This is actually a good combination
            try result.addSuggestion("", "", "", "Binary format + async I/O is excellent for high performance");
        }

        if (config.format == .json and config.sampling_rate < 1.0) {
            try result.addWarning("combination", "JSON format with sampling may make log analysis difficult", .medium);
        }

        if (config.level == .debug and config.async_io) {
            try result.addWarning("combination", "Debug level with async I/O may delay critical debug information", .medium);
        }

        if (config.output_target == .file and config.async_io and config.max_file_size < 1024 * 1024) {
            try result.addWarning("combination", "Small file sizes with async I/O may cause rotation issues", .medium);
        }
    }
};

// Quick validation function for simple use cases
pub fn validateConfig(allocator: std.mem.Allocator, config: zlog.LoggerConfig) !bool {
    const validator = ConfigValidator.init(allocator);
    var result = try validator.validate(config);
    defer result.deinit();

    if (!result.valid) {
        result.print();
    }

    return result.valid;
}

// Enhanced configuration with automatic fixing
pub fn fixConfig(allocator: std.mem.Allocator, config: zlog.LoggerConfig) !zlog.LoggerConfig {
    const validator = ConfigValidator.init(allocator);
    var result = try validator.validate(config);
    defer result.deinit();

    var fixed_config = config;

    // Apply automatic fixes based on errors
    for (result.errors.items) |err| {
        if (std.mem.eql(u8, err.field, "format")) {
            if (err.error_type == .FormatNotEnabled) {
                fixed_config.format = .text; // Fall back to text
            }
        } else if (std.mem.eql(u8, err.field, "output_target")) {
            if (err.error_type == .OutputTargetNotEnabled) {
                fixed_config.output_target = .stdout; // Fall back to stdout
            }
        } else if (std.mem.eql(u8, err.field, "buffer_size")) {
            if (err.error_type == .InvalidBufferSize) {
                fixed_config.buffer_size = 4096; // Safe default
            }
        } else if (std.mem.eql(u8, err.field, "sampling_rate")) {
            if (err.error_type == .InvalidSamplingRate) {
                fixed_config.sampling_rate = 1.0; // No sampling
            }
        }
    }

    return fixed_config;
}

// Test validation
const testing = std.testing;

test "validation: valid configuration" {
    const validator = ConfigValidator.init(testing.allocator);
    const config = zlog.LoggerConfig{};

    var result = try validator.validate(config);
    defer result.deinit();

    try testing.expect(result.valid);
    try testing.expect(result.errors.items.len == 0);
}

test "validation: invalid buffer size" {
    const validator = ConfigValidator.init(testing.allocator);
    const config = zlog.LoggerConfig{
        .buffer_size = 100, // Too small
    };

    var result = try validator.validate(config);
    defer result.deinit();

    try testing.expect(!result.valid);
    try testing.expect(result.errors.items.len > 0);
}

test "validation: config fixing" {
    const config = zlog.LoggerConfig{
        .buffer_size = 100, // Invalid
        .sampling_rate = 2.0, // Invalid
    };

    const fixed = try fixConfig(testing.allocator, config);

    try testing.expect(fixed.buffer_size == 4096);
    try testing.expect(fixed.sampling_rate == 1.0);
}