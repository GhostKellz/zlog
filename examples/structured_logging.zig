// Structured logging example
// Shows how to use fields for rich, queryable logs

const std = @import("std");
const zlog = @import("zlog");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger with JSON format for structured output
    var logger = try zlog.Logger.init(allocator, .{
        .level = .info,
        .format = .json,
        .output_target = .stdout,
    });
    defer logger.deinit();

    // Log with structured fields
    const fields = [_]zlog.Field{
        .{ .key = "user_id", .value = .{ .uint = 12345 } },
        .{ .key = "username", .value = .{ .string = "alice" } },
        .{ .key = "email", .value = .{ .string = "alice@example.com" } },
        .{ .key = "login_attempts", .value = .{ .int = 1 } },
        .{ .key = "success", .value = .{ .boolean = true } },
    };
    logger.logWithFields(.info, "User logged in", &fields);

    // HTTP request logging
    const request_fields = [_]zlog.Field{
        .{ .key = "method", .value = .{ .string = "GET" } },
        .{ .key = "path", .value = .{ .string = "/api/users/123" } },
        .{ .key = "status_code", .value = .{ .uint = 200 } },
        .{ .key = "response_time_ms", .value = .{ .float = 45.23 } },
        .{ .key = "user_agent", .value = .{ .string = "Mozilla/5.0" } },
    };
    logger.logWithFields(.info, "HTTP request completed", &request_fields);

    // Database query logging
    const db_fields = [_]zlog.Field{
        .{ .key = "query_type", .value = .{ .string = "SELECT" } },
        .{ .key = "table", .value = .{ .string = "users" } },
        .{ .key = "rows_affected", .value = .{ .uint = 15 } },
        .{ .key = "duration_ms", .value = .{ .float = 12.5 } },
    };
    logger.logWithFields(.info, "Database query executed", &db_fields);
}
