const std = @import("std");
const build_options = @import("build_options");

const zsync = if (build_options.enable_async) @import("zsync") else void;

// Public API exports for advanced features
pub const network = if (build_options.enable_network_targets) @import("network.zig") else struct {};
pub const configuration = @import("config.zig");
pub const validation = @import("validation.zig");
pub const errors = @import("errors.zig");

pub const Level = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
    fatal = 4,

    pub fn toString(self: Level) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };
    }
};

pub const Format = enum {
    text,
    json,
    binary,

    pub fn isAvailable(format: Format) bool {
        return switch (format) {
            .text => true, // Always available
            .json => build_options.enable_json,
            .binary => build_options.enable_binary_format,
        };
    }
};

pub const OutputTarget = enum {
    stdout,
    stderr,
    file,
    network,

    pub fn isAvailable(target: OutputTarget) bool {
        return switch (target) {
            .stdout, .stderr => true, // Always available
            .file => build_options.enable_file_targets,
            .network => build_options.enable_network_targets,
        };
    }
};

pub const Field = struct {
    key: []const u8,
    value: Value,

    pub const Value = union(enum) {
        string: []const u8,
        int: i64,
        uint: u64,
        float: f64,
        boolean: bool,
    };
};

pub const LogEntry = struct {
    level: Level,
    timestamp: i64,
    message: []const u8,
    fields: []const Field,
};

pub const LoggerConfig = struct {
    level: Level = .info,
    format: Format = .text,
    output_target: OutputTarget = .stdout,
    file_path: ?[]const u8 = null,
    max_file_size: usize = 10 * 1024 * 1024, // 10MB default
    max_backup_files: u8 = 5,
    async_io: bool = if (build_options.enable_async) false else false,
    sampling_rate: f32 = 1.0,
    buffer_size: usize = 4096,

    // Network settings
    network_config: if (build_options.enable_network_targets) ?network.NetworkConfig else ?void = null,

    // Aggregation settings
    enable_batching: bool = if (build_options.enable_aggregation) false else false,
    batch_size: usize = 100,
    batch_timeout_ms: u64 = 1000, // 1 second
    enable_deduplication: bool = if (build_options.enable_aggregation) false else false,
    dedup_window_ms: u64 = 5000, // 5 seconds

    pub fn validate(self: LoggerConfig) !void {
        if (!self.format.isAvailable()) {
            std.debug.print("❌ zlog config error: {s} format not enabled in build\n", .{@tagName(self.format)});
            std.debug.print("   💡 Hint: Use .text format or rebuild with -D{s}_format=true\n", .{@tagName(self.format)});
            return error.FormatNotEnabled;
        }
        if (!self.output_target.isAvailable()) {
            std.debug.print("❌ zlog config error: {s} output target not enabled in build\n", .{@tagName(self.output_target)});
            std.debug.print("   💡 Hint: Use .stdout/.stderr or rebuild with -D{s}_targets=true\n", .{@tagName(self.output_target)});
            return error.OutputTargetNotEnabled;
        }
        if (self.output_target == .file and self.file_path == null) {
            std.debug.print("❌ zlog config error: file output requires file_path to be set\n", .{});
            std.debug.print("   💡 Hint: Set .file_path = \"path/to/logfile.log\" in config\n", .{});
            return error.FilePathRequired;
        }
        if (self.async_io and !build_options.enable_async) {
            std.debug.print("❌ zlog config error: async_io requested but not enabled in build\n", .{});
            std.debug.print("   💡 Hint: Set .async_io = false or rebuild with -Dasync_io=true\n", .{});
            return error.AsyncNotEnabled;
        }
        if ((self.enable_batching or self.enable_deduplication) and !build_options.enable_aggregation) {
            std.debug.print("❌ zlog config error: aggregation features requested but not enabled in build\n", .{});
            std.debug.print("   💡 Hint: Disable batching/deduplication or rebuild with -Daggregation=true\n", .{});
            return error.AggregationNotEnabled;
        }
    }
};

pub const Logger = struct {
    config: LoggerConfig,
    file: std.fs.File,
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    sample_counter: std.atomic.Value(u64),

    // File rotation fields (only used when file targets are enabled)
    current_file_size: if (build_options.enable_file_targets) std.atomic.Value(usize) else void,

    // Aggregation fields (only used when aggregation is enabled)
    batch_buffer: if (build_options.enable_aggregation) std.ArrayList(LogEntry) else void,
    last_batch_time: if (build_options.enable_aggregation) std.atomic.Value(i64) else void,
    dedup_cache: if (build_options.enable_aggregation) std.AutoHashMap(u64, i64) else void,

    // Async fields (only used when async is enabled)
    async_queue: if (build_options.enable_async) std.ArrayList([]u8) else void,
    async_thread: if (build_options.enable_async) ?std.Thread else void,
    shutdown_signal: if (build_options.enable_async) std.atomic.Value(bool) else void,

    pub fn init(allocator: std.mem.Allocator, config: LoggerConfig) !Logger {
        // Validate configuration with helpful error messages
        try config.validate();

        // Open output file
        const output_file = switch (config.output_target) {
            .stdout => std.fs.File.stdout(),
            .stderr => std.fs.File.stderr(),
            .file => if (build_options.enable_file_targets) blk: {
                const path = config.file_path.?;
                break :blk try std.fs.cwd().createFile(path, .{ .read = false, .truncate = false });
            } else std.fs.File.stdout(),
            .network => std.fs.File.stdout(), // Network targets don't use a file handle
        };

        var logger = Logger{
            .config = config,
            .file = output_file,
            .mutex = .{},
            .allocator = allocator,
            .buffer = try std.ArrayList(u8).initCapacity(allocator, config.buffer_size),
            .sample_counter = std.atomic.Value(u64).init(0),
            .current_file_size = if (build_options.enable_file_targets) std.atomic.Value(usize).init(0) else {},
            .batch_buffer = if (build_options.enable_aggregation) .{} else {},
            .last_batch_time = if (build_options.enable_aggregation) std.atomic.Value(i64).init(std.time.timestamp()) else {},
            .dedup_cache = if (build_options.enable_aggregation) std.AutoHashMap(u64, i64).init(allocator) else {},
            .async_queue = if (build_options.enable_async) .{} else {},
            .async_thread = if (build_options.enable_async) null else {},
            .shutdown_signal = if (build_options.enable_async) std.atomic.Value(bool).init(false) else {},
        };

        // Get current file size for rotation tracking
        if (build_options.enable_file_targets and config.output_target == .file) {
            const file_size = logger.file.getEndPos() catch 0;
            logger.current_file_size.store(file_size, .monotonic);
        }

        // Start async thread if enabled
        if (build_options.enable_async and config.async_io) {
            logger.async_thread = try std.Thread.spawn(.{}, asyncWorker, .{&logger});
        }

        return logger;
    }

    pub fn deinit(self: *Logger) void {
        // Shutdown async thread
        if (build_options.enable_async and self.config.async_io) {
            self.shutdown_signal.store(true, .release);
            if (self.async_thread) |thread| {
                thread.join();
            }

            // Clean up pending messages
            for (self.async_queue.items) |msg| {
                self.allocator.free(msg);
            }
            self.async_queue.deinit(self.allocator);
        }

        // Close file if it's not stdout/stderr
        if (build_options.enable_file_targets and
            self.config.output_target == .file and
            self.file.handle != std.fs.File.stdout().handle and
            self.file.handle != std.fs.File.stderr().handle) {
            self.file.close();
        }

        self.buffer.deinit(self.allocator);
    }

    fn rotateLogFile(self: *Logger) !void {
        if (!build_options.enable_file_targets or self.config.output_target != .file) {
            return;
        }

        const file_path = self.config.file_path.?;

        // Close current file
        self.file.close();

        // Rotate backup files
        var i = self.config.max_backup_files;
        while (i > 0) : (i -= 1) {
            const old_backup = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ file_path, i - 1 });
            defer self.allocator.free(old_backup);

            const new_backup = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ file_path, i });
            defer self.allocator.free(new_backup);

            std.fs.cwd().rename(old_backup, new_backup) catch {};
        }

        // Move current log to .0 backup
        const backup_name = try std.fmt.allocPrint(self.allocator, "{s}.0", .{file_path});
        defer self.allocator.free(backup_name);
        std.fs.cwd().rename(file_path, backup_name) catch {};

        // Create new log file
        self.file = try std.fs.cwd().createFile(file_path, .{ .read = false, .truncate = true });
        self.current_file_size.store(0, .monotonic);
    }

    fn asyncWorker(self: *Logger) void {
        var batch_buffer: std.ArrayList([]u8) = .{};
        defer batch_buffer.deinit(self.allocator);

        // Pre-allocate batch buffer capacity for better performance
        batch_buffer.ensureTotalCapacity(self.allocator, self.config.buffer_size / 64) catch {};

        while (!self.shutdown_signal.load(.acquire)) {
            // Batch processing for better performance
            self.mutex.lock();

            // Move messages from queue to batch buffer
            const queue_size = self.async_queue.items.len;
            if (queue_size > 0) {
                // Reserve capacity in batch buffer
                batch_buffer.ensureTotalCapacityPrecise(self.allocator, queue_size) catch {
                    self.mutex.unlock();
                    std.Thread.sleep(500000); // 0.5ms - shorter sleep for better responsiveness
                    continue;
                };

                // Move all messages to batch buffer
                for (self.async_queue.items) |msg| {
                    batch_buffer.appendAssumeCapacity(msg);
                }
                self.async_queue.clearRetainingCapacity();
            }
            self.mutex.unlock();

            // Process batch outside of lock for better concurrency
            if (batch_buffer.items.len > 0) {
                // Write all messages as efficiently as possible
                for (batch_buffer.items) |msg| {
                    _ = self.file.writeAll(msg) catch {};
                    self.allocator.free(msg);
                }
                batch_buffer.clearRetainingCapacity();
            } else {
                // Adaptive sleep - shorter when active, longer when idle
                std.Thread.sleep(500000); // 0.5ms - more responsive than 1ms
            }
        }

        // Process any remaining messages during shutdown
        self.mutex.lock();
        for (self.async_queue.items) |msg| {
            _ = self.file.writeAll(msg) catch {};
            self.allocator.free(msg);
        }
        self.async_queue.clearAndFree(self.allocator);
        self.mutex.unlock();
    }

    pub fn log(self: *Logger, level: Level, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(level) < @intFromEnum(self.config.level)) {
            return;
        }

        if (!self.shouldSample()) {
            return;
        }

        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch return;
        defer self.allocator.free(message);

        const fields = [_]Field{};
        self.logWithFields(level, message, &fields);
    }

    pub fn logWithFields(self: *Logger, level: Level, message: []const u8, fields: []const Field) void {
        if (@intFromEnum(level) < @intFromEnum(self.config.level)) {
            return;
        }

        const entry = LogEntry{
            .level = level,
            .timestamp = std.time.timestamp(),
            .message = message,
            .fields = fields,
        };

        if (build_options.enable_async and self.config.async_io) {
            // Format message in temporary buffer
            var temp_buffer: std.ArrayList(u8) = .{};
            defer temp_buffer.deinit(self.allocator);

            switch (self.config.format) {
                .text => self.formatTextToBuffer(&temp_buffer, entry) catch return,
                .json => if (build_options.enable_json) {
                    self.formatJsonToBuffer(&temp_buffer, entry) catch return;
                } else {
                    self.formatTextToBuffer(&temp_buffer, entry) catch return;
                },
                .binary => if (build_options.enable_binary_format) {
                    self.formatBinaryToBuffer(&temp_buffer, entry) catch return;
                } else {
                    self.formatTextToBuffer(&temp_buffer, entry) catch return;
                },
            }

            // Copy to owned slice for async processing
            const message_copy = self.allocator.dupe(u8, temp_buffer.items) catch return;

            self.mutex.lock();
            defer self.mutex.unlock();
            self.async_queue.append(self.allocator, message_copy) catch {
                self.allocator.free(message_copy);
            };
        } else {
            self.mutex.lock();
            defer self.mutex.unlock();

            switch (self.config.format) {
                .text => self.formatText(entry) catch {},
                .json => if (build_options.enable_json) {
                    self.formatJson(entry) catch {};
                } else {
                    self.formatText(entry) catch {};
                },
                .binary => if (build_options.enable_binary_format) {
                    self.formatBinary(entry) catch {};
                } else {
                    self.formatText(entry) catch {};
                },
            }

            self.flush() catch {};
        }
    }

    fn shouldSample(self: *Logger) bool {
        if (self.config.sampling_rate >= 1.0) {
            return true;
        }

        const count = self.sample_counter.fetchAdd(1, .monotonic);
        const threshold = @as(u64, @intFromFloat(1.0 / self.config.sampling_rate));
        return count % threshold == 0;
    }

    fn formatText(self: *Logger, entry: LogEntry) !void {
        self.buffer.clearRetainingCapacity();

        const timestamp = @as(u64, @intCast(entry.timestamp));
        const formatted = try std.fmt.allocPrint(self.allocator, "[{d}] [{s}] {s}", .{
            timestamp,
            entry.level.toString(),
            entry.message,
        });
        defer self.allocator.free(formatted);

        try self.buffer.appendSlice(self.allocator, formatted);

        for (entry.fields) |field| {
            const field_str = switch (field.value) {
                .string => |v| try std.fmt.allocPrint(self.allocator, " {s}=\"{s}\"", .{field.key, v}),
                .int => |v| try std.fmt.allocPrint(self.allocator, " {s}={d}", .{field.key, v}),
                .uint => |v| try std.fmt.allocPrint(self.allocator, " {s}={d}", .{field.key, v}),
                .float => |v| try std.fmt.allocPrint(self.allocator, " {s}={d}", .{field.key, v}),
                .boolean => |v| try std.fmt.allocPrint(self.allocator, " {s}={}", .{field.key, v}),
            };
            defer self.allocator.free(field_str);
            try self.buffer.appendSlice(self.allocator, field_str);
        }

        try self.buffer.append(self.allocator, '\n');
    }

    fn formatTextToBuffer(self: *Logger, buffer: *std.ArrayList(u8), entry: LogEntry) !void {
        const timestamp = @as(u64, @intCast(entry.timestamp));
        const formatted = try std.fmt.allocPrint(self.allocator, "[{d}] [{s}] {s}", .{
            timestamp,
            entry.level.toString(),
            entry.message,
        });
        defer self.allocator.free(formatted);

        try buffer.appendSlice(self.allocator, formatted);

        for (entry.fields) |field| {
            const field_str = switch (field.value) {
                .string => |v| try std.fmt.allocPrint(self.allocator, " {s}=\"{s}\"", .{field.key, v}),
                .int => |v| try std.fmt.allocPrint(self.allocator, " {s}={d}", .{field.key, v}),
                .uint => |v| try std.fmt.allocPrint(self.allocator, " {s}={d}", .{field.key, v}),
                .float => |v| try std.fmt.allocPrint(self.allocator, " {s}={d}", .{field.key, v}),
                .boolean => |v| try std.fmt.allocPrint(self.allocator, " {s}={}", .{field.key, v}),
            };
            defer self.allocator.free(field_str);
            try buffer.appendSlice(self.allocator, field_str);
        }

        try buffer.append(self.allocator, '\n');
    }

    fn formatJson(self: *Logger, entry: LogEntry) !void {
        if (!build_options.enable_json) {
            return self.formatText(entry);
        }

        self.buffer.clearRetainingCapacity();

        const base = try std.fmt.allocPrint(self.allocator, "{{\"timestamp\":{d},\"level\":\"{s}\",\"message\":\"{s}\"", .{
            entry.timestamp,
            entry.level.toString(),
            entry.message,
        });
        defer self.allocator.free(base);
        try self.buffer.appendSlice(self.allocator, base);

        if (entry.fields.len > 0) {
            try self.buffer.append(self.allocator, ',');
            for (entry.fields, 0..) |field, i| {
                if (i > 0) try self.buffer.append(self.allocator, ',');
                const field_json = switch (field.value) {
                    .string => |v| try std.fmt.allocPrint(self.allocator, "\"{s}\":\"{s}\"", .{field.key, v}),
                    .int => |v| try std.fmt.allocPrint(self.allocator, "\"{s}\":{d}", .{field.key, v}),
                    .uint => |v| try std.fmt.allocPrint(self.allocator, "\"{s}\":{d}", .{field.key, v}),
                    .float => |v| try std.fmt.allocPrint(self.allocator, "\"{s}\":{d}", .{field.key, v}),
                    .boolean => |v| try std.fmt.allocPrint(self.allocator, "\"{s}\":{}", .{field.key, v}),
                };
                defer self.allocator.free(field_json);
                try self.buffer.appendSlice(self.allocator, field_json);
            }
        }

        try self.buffer.appendSlice(self.allocator, "}\n");
    }

    fn formatJsonToBuffer(self: *Logger, buffer: *std.ArrayList(u8), entry: LogEntry) !void {
        if (!build_options.enable_json) {
            return self.formatTextToBuffer(buffer, entry);
        }

        const base = try std.fmt.allocPrint(self.allocator, "{{\"timestamp\":{d},\"level\":\"{s}\",\"message\":\"{s}\"", .{
            entry.timestamp,
            entry.level.toString(),
            entry.message,
        });
        defer self.allocator.free(base);
        try buffer.appendSlice(self.allocator, base);

        if (entry.fields.len > 0) {
            try buffer.append(self.allocator, ',');
            for (entry.fields, 0..) |field, i| {
                if (i > 0) try buffer.append(self.allocator, ',');
                const field_json = switch (field.value) {
                    .string => |v| try std.fmt.allocPrint(self.allocator, "\"{s}\":\"{s}\"", .{field.key, v}),
                    .int => |v| try std.fmt.allocPrint(self.allocator, "\"{s}\":{d}", .{field.key, v}),
                    .uint => |v| try std.fmt.allocPrint(self.allocator, "\"{s}\":{d}", .{field.key, v}),
                    .float => |v| try std.fmt.allocPrint(self.allocator, "\"{s}\":{d}", .{field.key, v}),
                    .boolean => |v| try std.fmt.allocPrint(self.allocator, "\"{s}\":{}", .{field.key, v}),
                };
                defer self.allocator.free(field_json);
                try buffer.appendSlice(self.allocator, field_json);
            }
        }

        try buffer.appendSlice(self.allocator, "}\n");
    }

    fn formatBinary(self: *Logger, entry: LogEntry) !void {
        if (!build_options.enable_binary_format) {
            return self.formatText(entry);
        }

        self.buffer.clearRetainingCapacity();

        // Optimized binary format v2: [header][timestamp:8][level:1][message_len:varint][message][fields_count:varint][fields...]
        // Each field: [key_len:varint][key][value_type:1][value]
        // Uses variable-length integers for better size efficiency

        // Write format version for future compatibility (magic byte)
        try self.buffer.append(self.allocator, 0x5A); // 'Z' for zlog

        // Timestamp - always 8 bytes, little-endian for consistency
        const timestamp_bytes = std.mem.toBytes(@as(u64, @intCast(entry.timestamp)));
        try self.buffer.appendSlice(self.allocator, &timestamp_bytes);

        // Level - 1 byte
        try self.buffer.append(self.allocator, @intFromEnum(entry.level));

        // Message length and content using varint encoding
        try writeVarint(&self.buffer, self.allocator, entry.message.len);
        try self.buffer.appendSlice(self.allocator, entry.message);

        // Fields count using varint
        try writeVarint(&self.buffer, self.allocator, entry.fields.len);

        for (entry.fields) |field| {
            // Key length and content using varint
            try writeVarint(&self.buffer, self.allocator, field.key.len);
            try self.buffer.appendSlice(self.allocator, field.key);

            // Value type and content
            switch (field.value) {
                .string => |v| {
                    try self.buffer.append(self.allocator, 0); // string type
                    try writeVarint(&self.buffer, self.allocator, v.len);
                    try self.buffer.appendSlice(self.allocator, v);
                },
                .int => |v| {
                    try self.buffer.append(self.allocator, 1); // int type
                    try writeVarintSigned(&self.buffer, self.allocator, v);
                },
                .uint => |v| {
                    try self.buffer.append(self.allocator, 2); // uint type
                    try writeVarint(&self.buffer, self.allocator, v);
                },
                .float => |v| {
                    try self.buffer.append(self.allocator, 3); // float type
                    const bytes = std.mem.toBytes(v);
                    try self.buffer.appendSlice(self.allocator, &bytes);
                },
                .boolean => |v| {
                    try self.buffer.append(self.allocator, 4); // bool type
                    try self.buffer.append(self.allocator, if (v) 1 else 0);
                },
            }
        }
    }

    // Optimized varint encoding for better space efficiency
    fn writeVarint(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: usize) !void {
        var v = value;
        while (v >= 0x80) {
            try buffer.append(allocator, @as(u8, @truncate(v | 0x80)));
            v >>= 7;
        }
        try buffer.append(allocator, @as(u8, @truncate(v)));
    }

    fn writeVarintSigned(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: i64) !void {
        // ZigZag encoding for signed integers
        const encoded = if (value >= 0)
            @as(u64, @intCast(value << 1))
        else
            @as(u64, @intCast(((-value - 1) << 1) | 1));

        try writeVarint(buffer, allocator, encoded);
    }

    fn formatBinaryToBuffer(self: *Logger, buffer: *std.ArrayList(u8), entry: LogEntry) !void {
        if (!build_options.enable_binary_format) {
            return self.formatTextToBuffer(buffer, entry);
        }

        // Same optimized binary format as above but writes to provided buffer
        try buffer.append(self.allocator, 0x5A); // Format version

        const timestamp_bytes = std.mem.toBytes(@as(u64, @intCast(entry.timestamp)));
        try buffer.appendSlice(self.allocator, &timestamp_bytes);

        try buffer.append(self.allocator, @intFromEnum(entry.level));

        try writeVarint(buffer, self.allocator, entry.message.len);
        try buffer.appendSlice(self.allocator, entry.message);

        try writeVarint(buffer, self.allocator, entry.fields.len);

        for (entry.fields) |field| {
            try writeVarint(buffer, self.allocator, field.key.len);
            try buffer.appendSlice(self.allocator, field.key);

            switch (field.value) {
                .string => |v| {
                    try buffer.append(self.allocator, 0);
                    try writeVarint(buffer, self.allocator, v.len);
                    try buffer.appendSlice(self.allocator, v);
                },
                .int => |v| {
                    try buffer.append(self.allocator, 1);
                    try writeVarintSigned(buffer, self.allocator, v);
                },
                .uint => |v| {
                    try buffer.append(self.allocator, 2);
                    try writeVarint(buffer, self.allocator, v);
                },
                .float => |v| {
                    try buffer.append(self.allocator, 3);
                    const bytes = std.mem.toBytes(v);
                    try buffer.appendSlice(self.allocator, &bytes);
                },
                .boolean => |v| {
                    try buffer.append(self.allocator, 4);
                    try buffer.append(self.allocator, if (v) 1 else 0);
                },
            }
        }
    }

    fn flush(self: *Logger) !void {
        if (self.buffer.items.len > 0) {
            _ = try self.file.writeAll(self.buffer.items);

            // Track file size for rotation
            if (build_options.enable_file_targets and self.config.output_target == .file) {
                const new_size = self.current_file_size.fetchAdd(self.buffer.items.len, .monotonic) + self.buffer.items.len;
                if (new_size > self.config.max_file_size) {
                    try self.rotateLogFile();
                }
            }
        }
    }

    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.debug, fmt, args);
    }

    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.info, fmt, args);
    }

    pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.warn, fmt, args);
    }

    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.err, fmt, args);
    }

    pub fn fatal(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.fatal, fmt, args);
    }
};

var default_logger: ?Logger = null;
var default_mutex = std.Thread.Mutex{};

pub fn getDefaultLogger() !*Logger {
    default_mutex.lock();
    defer default_mutex.unlock();

    if (default_logger == null) {
        default_logger = try Logger.init(std.heap.page_allocator, .{});
    }

    return &default_logger.?;
}

pub fn setDefaultLogger(logger: Logger) void {
    default_mutex.lock();
    defer default_mutex.unlock();

    if (default_logger) |*l| {
        l.deinit();
    }
    default_logger = logger;
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    const logger = getDefaultLogger() catch return;
    logger.debug(fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    const logger = getDefaultLogger() catch return;
    logger.info(fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    const logger = getDefaultLogger() catch return;
    logger.warn(fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    const logger = getDefaultLogger() catch return;
    logger.err(fmt, args);
}

pub fn fatal(comptime fmt: []const u8, args: anytype) void {
    const logger = getDefaultLogger() catch return;
    logger.fatal(fmt, args);
}

test "basic logging" {
    const allocator = std.testing.allocator;
    var logger = try Logger.init(allocator, .{
        .level = .debug,
        .format = .text,
    });
    defer logger.deinit();

    logger.debug("Debug message", .{});
    logger.info("Info message with value: {d}", .{42});
    logger.warn("Warning message", .{});
    logger.err("Error occurred", .{});
}

test "structured logging" {
    const allocator = std.testing.allocator;
    var logger = try Logger.init(allocator, .{
        .level = .info,
        .format = .text,
    });
    defer logger.deinit();

    const fields = [_]Field{
        .{ .key = "user_id", .value = .{ .uint = 12345 } },
        .{ .key = "action", .value = .{ .string = "login" } },
        .{ .key = "success", .value = .{ .boolean = true } },
    };

    logger.logWithFields(.info, "User logged in", &fields);
}

test "log levels" {
    const allocator = std.testing.allocator;
    var logger = try Logger.init(allocator, .{
        .level = .warn,
        .format = .text,
    });
    defer logger.deinit();

    logger.debug("This should not appear", .{});
    logger.info("This should not appear either", .{});
    logger.warn("This should appear", .{});
    logger.err("This should also appear", .{});
}

test "sampling" {
    const allocator = std.testing.allocator;
    var logger = try Logger.init(allocator, .{
        .level = .debug,
        .format = .text,
        .sampling_rate = 0.5,
    });
    defer logger.deinit();

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        logger.info("Sample log {d}", .{i});
    }
}

test "benchmark text format" {
    const allocator = std.testing.allocator;
    var logger = try Logger.init(allocator, .{
        .level = .info,
        .format = .text,
    });
    defer logger.deinit();

    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < 10000) : (i += 1) {
        logger.info("Benchmark message {d}", .{i});
    }

    const end = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    const messages_per_ms = 10000.0 / duration_ms;

    std.debug.print("Text format: {d:.2} messages/ms\n", .{messages_per_ms});
}

test "benchmark binary format" {
    if (!build_options.enable_binary_format) return;

    const allocator = std.testing.allocator;
    var logger = try Logger.init(allocator, .{
        .level = .info,
        .format = .binary,
    });
    defer logger.deinit();

    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < 10000) : (i += 1) {
        logger.info("Benchmark message {d}", .{i});
    }

    const end = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    const messages_per_ms = 10000.0 / duration_ms;

    std.debug.print("Binary format: {d:.2} messages/ms\n", .{messages_per_ms});
}

test "benchmark structured logging" {
    const allocator = std.testing.allocator;
    var logger = try Logger.init(allocator, .{
        .level = .info,
        .format = .text,
    });
    defer logger.deinit();

    const fields = [_]Field{
        .{ .key = "user_id", .value = .{ .uint = 12345 } },
        .{ .key = "action", .value = .{ .string = "benchmark" } },
        .{ .key = "latency", .value = .{ .float = 15.7 } },
        .{ .key = "success", .value = .{ .boolean = true } },
    };

    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < 5000) : (i += 1) {
        logger.logWithFields(.info, "Structured benchmark", &fields);
    }

    const end = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    const messages_per_ms = 5000.0 / duration_ms;

    std.debug.print("Structured logging: {d:.2} messages/ms\n", .{messages_per_ms});
}