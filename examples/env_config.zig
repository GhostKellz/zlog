// Example: Configure logger using environment variables
// Run with: ZLOG_LEVEL=debug ZLOG_FORMAT=json ./zig-out/bin/env_config

const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Start with default configuration
    var config = zlog.LoggerConfig{};

    // Override with environment variables
    // Supports: ZLOG_LEVEL, ZLOG_FORMAT, ZLOG_OUTPUT, ZLOG_FILE
    config = zlog.configuration.loadFromEnv(config);

    // Create logger with environment-configured settings
    var logger = try zlog.Logger.init(allocator, config);
    defer logger.deinit();

    // Log some messages
    logger.debug("Debug message - only shown if ZLOG_LEVEL=debug", .{});
    logger.info("Application started with environment configuration", .{});

    const env_fields = [_]zlog.Field{
        .{ .key = "level", .value = .{ .string = @tagName(config.level) } },
        .{ .key = "format", .value = .{ .string = @tagName(config.format) } },
        .{ .key = "output", .value = .{ .string = @tagName(config.output_target) } },
    };

    logger.logWithFields(.info, "Current configuration", &env_fields);

    logger.warn("Configuration can be changed without recompiling!", .{});
}
