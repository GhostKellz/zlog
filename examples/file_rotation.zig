// File rotation example
// Demonstrates file logging with automatic rotation

const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger with file output and rotation
    var logger = try zlog.Logger.init(allocator, .{
        .level = .info,
        .format = .text,
        .output_target = .file,
        .file_path = "app.log",
        .max_file_size = 1024 * 1024, // 1MB for demonstration
        .max_backup_files = 5, // Keep 5 backup files
    });
    defer logger.deinit();

    logger.info("Application started", .{});

    // Simulate logging over time
    std.debug.print("Logging messages to app.log...\n", .{});
    std.debug.print("File will rotate when it reaches 1MB\n", .{});
    std.debug.print("Backup files will be named: app.log.0, app.log.1, etc.\n\n", .{});

    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        logger.info("Log entry number {d} - This is a sample log message with some content to fill up the file", .{i});

        // Progress indicator every 1000 messages
        if (i % 1000 == 0) {
            std.debug.print("Logged {d} messages...\n", .{i});
        }
    }

    std.debug.print("\nDone! Check app.log and app.log.* for rotated files\n", .{});
}
