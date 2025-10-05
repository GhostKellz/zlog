// Configuration file parsing and management for zlog
// Supports JSON and YAML configuration files with hot-reload capabilities

const std = @import("std");
const zlog = @import("root.zig");
const build_options = @import("build_options");

/// Configuration file format
pub const ConfigFormat = enum {
    json,
    yaml, // Future support
    toml, // Future support
};

/// Configuration manager with hot-reload support
pub const ConfigManager = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    format: ConfigFormat,
    config: zlog.LoggerConfig,
    last_modified: i128,
    watch_thread: ?std.Thread = null,
    shutdown_signal: std.atomic.Value(bool),
    reload_callback: ?*const fn (zlog.LoggerConfig) void = null,

    pub fn init(
        allocator: std.mem.Allocator,
        file_path: []const u8,
        format: ConfigFormat,
    ) !ConfigManager {
        const config = try loadConfigFromFile(allocator, file_path, format);

        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();
        const stat = try file.stat();

        return ConfigManager{
            .allocator = allocator,
            .file_path = file_path,
            .format = format,
            .config = config,
            .last_modified = stat.mtime,
            .shutdown_signal = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *ConfigManager) void {
        if (self.watch_thread) |thread| {
            self.shutdown_signal.store(true, .release);
            thread.join();
        }
    }

    /// Enable hot-reload with callback on configuration changes
    pub fn enableHotReload(self: *ConfigManager, callback: *const fn (zlog.LoggerConfig) void) !void {
        self.reload_callback = callback;
        self.watch_thread = try std.Thread.spawn(.{}, watchConfigFile, .{self});
    }

    fn watchConfigFile(self: *ConfigManager) void {
        while (!self.shutdown_signal.load(.acquire)) {
            std.Thread.sleep(1 * std.time.ns_per_s); // Check every second

            const file = std.fs.cwd().openFile(self.file_path, .{}) catch continue;
            defer file.close();

            const stat = file.stat() catch continue;

            if (stat.mtime > self.last_modified) {
                // File has been modified, reload
                const new_config = loadConfigFromFile(
                    self.allocator,
                    self.file_path,
                    self.format,
                ) catch |err| {
                    std.debug.print("Failed to reload config: {}\n", .{err});
                    continue;
                };

                self.config = new_config;
                self.last_modified = stat.mtime;

                if (self.reload_callback) |callback| {
                    callback(new_config);
                }

                std.debug.print("Configuration reloaded from {s}\n", .{self.file_path});
            }
        }
    }

    pub fn getConfig(self: ConfigManager) zlog.LoggerConfig {
        return self.config;
    }

    pub fn reload(self: *ConfigManager) !void {
        const new_config = try loadConfigFromFile(
            self.allocator,
            self.file_path,
            self.format,
        );

        const file = try std.fs.cwd().openFile(self.file_path, .{});
        defer file.close();
        const stat = try file.stat();

        self.config = new_config;
        self.last_modified = stat.mtime;
    }
};

/// Load configuration from a JSON file
fn loadConfigFromFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    format: ConfigFormat,
) !zlog.LoggerConfig {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const contents = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(contents);

    return switch (format) {
        .json => try parseJsonConfig(allocator, contents),
        .yaml => error.NotImplemented, // Future
        .toml => error.NotImplemented, // Future
    };
}

/// Parse JSON configuration
fn parseJsonConfig(allocator: std.mem.Allocator, json_str: []const u8) !zlog.LoggerConfig {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_str,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value.object;

    var config = zlog.LoggerConfig{};

    // Parse level
    if (root.get("level")) |level_val| {
        const level_str = level_val.string;
        config.level = stringToLevel(level_str);
    }

    // Parse format
    if (root.get("format")) |format_val| {
        const format_str = format_val.string;
        config.format = stringToFormat(format_str);
    }

    // Parse output_target
    if (root.get("output_target")) |target_val| {
        const target_str = target_val.string;
        config.output_target = stringToOutputTarget(target_str);
    }

    // Parse file settings
    if (root.get("file_path")) |path_val| {
        config.file_path = try allocator.dupe(u8, path_val.string);
    }

    if (root.get("max_file_size")) |size_val| {
        config.max_file_size = @intCast(size_val.integer);
    }

    if (root.get("max_backup_files")) |backup_val| {
        config.max_backup_files = @intCast(backup_val.integer);
    }

    // Parse async settings
    if (root.get("async_io")) |async_val| {
        config.async_io = async_val.bool;
    }

    // Parse buffer settings
    if (root.get("buffer_size")) |buffer_val| {
        config.buffer_size = @intCast(buffer_val.integer);
    }

    if (root.get("sampling_rate")) |sample_val| {
        config.sampling_rate = @floatCast(sample_val.float);
    }

    // Parse aggregation settings
    if (root.get("enable_batching")) |batch_val| {
        config.enable_batching = batch_val.bool;
    }

    if (root.get("batch_size")) |size_val| {
        config.batch_size = @intCast(size_val.integer);
    }

    if (root.get("enable_deduplication")) |dedup_val| {
        config.enable_deduplication = dedup_val.bool;
    }

    return config;
}

/// Convert string to Level enum
fn stringToLevel(str: []const u8) zlog.Level {
    if (std.mem.eql(u8, str, "debug")) return .debug;
    if (std.mem.eql(u8, str, "info")) return .info;
    if (std.mem.eql(u8, str, "warn")) return .warn;
    if (std.mem.eql(u8, str, "error")) return .err;
    if (std.mem.eql(u8, str, "fatal")) return .fatal;
    return .info; // default
}

/// Convert string to Format enum
fn stringToFormat(str: []const u8) zlog.Format {
    if (std.mem.eql(u8, str, "text")) return .text;
    if (std.mem.eql(u8, str, "json")) return .json;
    if (std.mem.eql(u8, str, "binary")) return .binary;
    return .text; // default
}

/// Convert string to OutputTarget enum
fn stringToOutputTarget(str: []const u8) zlog.OutputTarget {
    if (std.mem.eql(u8, str, "stdout")) return .stdout;
    if (std.mem.eql(u8, str, "stderr")) return .stderr;
    if (std.mem.eql(u8, str, "file")) return .file;
    if (std.mem.eql(u8, str, "network")) return .network;
    return .stdout; // default
}

/// Save configuration to JSON file
pub fn saveConfigToFile(
    allocator: std.mem.Allocator,
    config: zlog.LoggerConfig,
    file_path: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    // Build JSON manually for simplicity
    try buffer.appendSlice("{\n");
    try buffer.writer().print("  \"level\": \"{s}\",\n", .{config.level.toString()});
    try buffer.writer().print("  \"format\": \"{s}\",\n", .{formatToString(config.format)});
    try buffer.writer().print("  \"output_target\": \"{s}\",\n", .{outputTargetToString(config.output_target)});

    if (config.file_path) |path| {
        try buffer.writer().print("  \"file_path\": \"{s}\",\n", .{path});
    }

    try buffer.writer().print("  \"max_file_size\": {d},\n", .{config.max_file_size});
    try buffer.writer().print("  \"max_backup_files\": {d},\n", .{config.max_backup_files});
    try buffer.writer().print("  \"async_io\": {},\n", .{config.async_io});
    try buffer.writer().print("  \"buffer_size\": {d},\n", .{config.buffer_size});
    try buffer.writer().print("  \"sampling_rate\": {d:.2},\n", .{config.sampling_rate});
    try buffer.writer().print("  \"enable_batching\": {},\n", .{config.enable_batching});
    try buffer.writer().print("  \"batch_size\": {d},\n", .{config.batch_size});
    try buffer.writer().print("  \"enable_deduplication\": {}\n", .{config.enable_deduplication});
    try buffer.appendSlice("}\n");

    try file.writeAll(buffer.items);
}

fn formatToString(format: zlog.Format) []const u8 {
    return switch (format) {
        .text => "text",
        .json => "json",
        .binary => "binary",
    };
}

fn outputTargetToString(target: zlog.OutputTarget) []const u8 {
    return switch (target) {
        .stdout => "stdout",
        .stderr => "stderr",
        .file => "file",
        .network => "network",
    };
}

/// Environment variable configuration overlay
pub fn loadFromEnv(base_config: zlog.LoggerConfig) zlog.LoggerConfig {
    var config = base_config;

    // ZLOG_LEVEL
    if (std.process.getEnvVarOwned(
        std.heap.page_allocator,
        "ZLOG_LEVEL",
    )) |level_str| {
        defer std.heap.page_allocator.free(level_str);
        config.level = stringToLevel(level_str);
    } else |_| {}

    // ZLOG_FORMAT
    if (std.process.getEnvVarOwned(
        std.heap.page_allocator,
        "ZLOG_FORMAT",
    )) |format_str| {
        defer std.heap.page_allocator.free(format_str);
        config.format = stringToFormat(format_str);
    } else |_| {}

    // ZLOG_OUTPUT
    if (std.process.getEnvVarOwned(
        std.heap.page_allocator,
        "ZLOG_OUTPUT",
    )) |output_str| {
        defer std.heap.page_allocator.free(output_str);
        config.output_target = stringToOutputTarget(output_str);
    } else |_| {}

    // ZLOG_FILE
    if (std.process.getEnvVarOwned(
        std.heap.page_allocator,
        "ZLOG_FILE",
    )) |file_str| {
        config.file_path = file_str;
    } else |_| {}

    return config;
}

// Tests
const testing = std.testing;

test "config: level string conversion" {
    try testing.expect(stringToLevel("debug") == .debug);
    try testing.expect(stringToLevel("info") == .info);
    try testing.expect(stringToLevel("warn") == .warn);
    try testing.expect(stringToLevel("error") == .err);
    try testing.expect(stringToLevel("fatal") == .fatal);
    try testing.expect(stringToLevel("invalid") == .info);
}

test "config: format string conversion" {
    try testing.expect(stringToFormat("text") == .text);
    try testing.expect(stringToFormat("json") == .json);
    try testing.expect(stringToFormat("binary") == .binary);
    try testing.expect(stringToFormat("invalid") == .text);
}

test "config: save and load JSON" {
    const config = zlog.LoggerConfig{
        .level = .debug,
        .format = .json,
        .output_target = .stdout,
        .buffer_size = 8192,
    };

    const test_file = "test_config.json";
    defer std.fs.cwd().deleteFile(test_file) catch {};

    try saveConfigToFile(testing.allocator, config, test_file);

    const loaded = try loadConfigFromFile(testing.allocator, test_file, .json);
    try testing.expect(loaded.level == .debug);
    try testing.expect(loaded.format == .json);
    try testing.expect(loaded.buffer_size == 8192);
}
