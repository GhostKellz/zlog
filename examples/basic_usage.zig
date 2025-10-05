// Basic usage example for zlog
// Demonstrates simple logging with different levels and formats

const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a basic console logger
    var logger = try zlog.Logger.init(allocator, .{
        .level = .debug,
        .format = .text,
        .output_target = .stdout,
    });
    defer logger.deinit();

    // Simple logging at different levels
    logger.debug("This is a debug message", .{});
    logger.info("Application started successfully", .{});
    logger.warn("This is a warning message", .{});
    logger.err("This is an error message", .{});

    // Formatted logging
    const port = 8080;
    logger.info("Server listening on port {d}", .{port});

    const user_count = 42;
    const active_connections = 15;
    logger.info("Stats: {d} users, {d} active connections", .{user_count, active_connections});

    // Different numeric types
    logger.info("Integer: {d}, Float: {d:.2}, Boolean: {}", .{100, 3.14159, true});
}
