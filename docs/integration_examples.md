# zlog Integration Examples

This document provides practical examples of integrating zlog with popular frameworks and systems. Each example includes complete, working code that demonstrates best practices for specific use cases.

## Table of Contents

1. [Web Frameworks](#web-frameworks)
2. [HTTP Servers](#http-servers)
3. [Database Integration](#database-integration)
4. [Microservices](#microservices)
5. [Game Development](#game-development)
6. [CLI Applications](#cli-applications)
7. [Systems Programming](#systems-programming)
8. [Testing Frameworks](#testing-frameworks)

## Web Frameworks

### HTTP Server with Zig's std.http

```zig
const std = @import("std");
const zlog = @import("zlog");

const ServerLogger = struct {
    request_logger: zlog.Logger,
    error_logger: zlog.Logger,
    access_logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator) !ServerLogger {
        return ServerLogger{
            .request_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = "/var/log/app/requests.log" },
                .async_io = true,
                .level = .info,
            }),
            .error_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = "/var/log/app/errors.log" },
                .level = .warn,
            }),
            .access_logger = try zlog.Logger.init(allocator, .{
                .format = .text,
                .output_target = .{ .file = "/var/log/app/access.log" },
                .async_io = true,
                .level = .info,
            }),
        };
    }

    pub fn deinit(self: *ServerLogger) void {
        self.request_logger.deinit();
        self.error_logger.deinit();
        self.access_logger.deinit();
    }

    pub fn logRequest(
        self: *ServerLogger,
        method: []const u8,
        path: []const u8,
        status: u32,
        duration_ms: f64,
        user_id: ?u64,
        ip: []const u8,
    ) void {
        // Structured request logging
        var fields = std.ArrayList(zlog.Field).init(std.heap.page_allocator);
        defer fields.deinit();

        fields.appendSlice(&[_]zlog.Field{
            zlog.str("method", method),
            zlog.str("path", path),
            zlog.uint("status", status),
            zlog.float("duration_ms", duration_ms),
            zlog.str("ip", ip),
            zlog.uint("timestamp", @intCast(std.time.timestamp())),
        }) catch return;

        if (user_id) |uid| {
            fields.append(zlog.uint("user_id", uid)) catch return;
        }

        self.request_logger.logWithFields(.info, "HTTP request", fields.items);

        // Simple access log
        self.access_logger.info("{s} {s} {d} {d:.2}ms", .{ method, path, status, duration_ms });
    }

    pub fn logError(self: *ServerLogger, err: anyerror, context: []const u8, request_id: []const u8) void {
        self.error_logger.logWithFields(.err, "Request error", &[_]zlog.Field{
            zlog.str("error", @errorName(err)),
            zlog.str("context", context),
            zlog.str("request_id", request_id),
            zlog.uint("timestamp", @intCast(std.time.timestamp())),
        });
    }
};

const RequestHandler = struct {
    logger: *ServerLogger,
    allocator: std.mem.Allocator,

    pub fn handleRequest(self: *RequestHandler, request: *std.http.Server.Request) !void {
        const start_time = std.time.nanoTimestamp();
        const request_id = try self.generateRequestId();
        defer self.allocator.free(request_id);

        // Add request ID to thread-local storage for contextual logging
        const method = @tagName(request.head.method);
        const path = request.head.target;

        var status: u32 = 200;
        var user_id: ?u64 = null;

        // Process request with error handling
        self.processRequest(request, &status, &user_id) catch |err| {
            status = 500;
            self.logger.logError(err, "Request processing failed", request_id);
        };

        // Calculate duration and log
        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

        self.logger.logRequest(
            method,
            path,
            status,
            duration_ms,
            user_id,
            "127.0.0.1", // Get real IP from request
        );
    }

    fn processRequest(self: *RequestHandler, request: *std.http.Server.Request, status: *u32, user_id: *?u64) !void {
        // Route handling logic here
        _ = self;
        _ = request;
        _ = status;
        _ = user_id;
    }

    fn generateRequestId(self: *RequestHandler) ![]u8 {
        var buf: [16]u8 = undefined;
        std.crypto.random.bytes(&buf);
        return try std.fmt.allocPrint(self.allocator, "{}", .{std.fmt.fmtSliceHexLower(&buf)});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server_logger = try ServerLogger.init(allocator);
    defer server_logger.deinit();

    server_logger.request_logger.info("HTTP server starting", .{});

    // Initialize HTTP server
    const address = std.net.Address.parseIp("127.0.0.1", 8080) catch unreachable;
    var server = std.http.Server.init(allocator, .{ .reuse_address = true });
    defer server.deinit();

    try server.listen(address);
    server_logger.request_logger.info("Server listening on {}", .{address});

    // Request handling loop
    while (true) {
        var response = try server.accept(.{
            .allocator = allocator,
        });
        defer response.deinit();

        var handler = RequestHandler{
            .logger = &server_logger,
            .allocator = allocator,
        };

        try handler.handleRequest(&response.request);
    }
}
```

### WebSocket Server Integration

```zig
const std = @import("std");
const zlog = @import("zlog");

const WebSocketLogger = struct {
    connection_logger: zlog.Logger,
    message_logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator) !WebSocketLogger {
        return WebSocketLogger{
            .connection_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = "/var/log/app/websockets.log" },
                .async_io = true,
                .level = .info,
            }),
            .message_logger = try zlog.Logger.init(allocator, .{
                .format = .binary,
                .output_target = .{ .file = "/var/log/app/ws_messages.log" },
                .async_io = true,
                .level = .debug,
                .sampling_rate = 0.1, // Sample 10% of messages
            }),
        };
    }

    pub fn deinit(self: *WebSocketLogger) void {
        self.connection_logger.deinit();
        self.message_logger.deinit();
    }

    pub fn logConnection(self: *WebSocketLogger, event: []const u8, client_id: []const u8, ip: []const u8) void {
        self.connection_logger.logWithFields(.info, "WebSocket connection event", &[_]zlog.Field{
            zlog.str("event", event),
            zlog.str("client_id", client_id),
            zlog.str("ip", ip),
            zlog.uint("timestamp", @intCast(std.time.timestamp())),
        });
    }

    pub fn logMessage(
        self: *WebSocketLogger,
        direction: []const u8,
        client_id: []const u8,
        message_type: []const u8,
        size: usize,
    ) void {
        self.message_logger.logWithFields(.debug, "WebSocket message", &[_]zlog.Field{
            zlog.str("direction", direction),
            zlog.str("client_id", client_id),
            zlog.str("type", message_type),
            zlog.uint("size", size),
        });
    }
};

const WebSocketConnection = struct {
    id: []const u8,
    logger: *WebSocketLogger,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, logger: *WebSocketLogger) !WebSocketConnection {
        const id = try generateConnectionId(allocator);
        return WebSocketConnection{
            .id = id,
            .logger = logger,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WebSocketConnection) void {
        self.allocator.free(self.id);
    }

    pub fn onConnect(self: *WebSocketConnection, ip: []const u8) void {
        self.logger.logConnection("connect", self.id, ip);
    }

    pub fn onDisconnect(self: *WebSocketConnection, reason: []const u8) void {
        self.logger.connection_logger.logWithFields(.info, "WebSocket disconnection", &[_]zlog.Field{
            zlog.str("event", "disconnect"),
            zlog.str("client_id", self.id),
            zlog.str("reason", reason),
        });
    }

    pub fn onMessage(self: *WebSocketConnection, message: []const u8, msg_type: []const u8) void {
        self.logger.logMessage("receive", self.id, msg_type, message.len);
    }

    pub fn sendMessage(self: *WebSocketConnection, message: []const u8, msg_type: []const u8) void {
        self.logger.logMessage("send", self.id, msg_type, message.len);
        // Send message implementation...
    }

    fn generateConnectionId(allocator: std.mem.Allocator) ![]u8 {
        var buf: [8]u8 = undefined;
        std.crypto.random.bytes(&buf);
        return try std.fmt.allocPrint(allocator, "ws_{}", .{std.fmt.fmtSliceHexLower(&buf)});
    }
};
```

## HTTP Servers

### RESTful API Server

```zig
const std = @import("std");
const zlog = @import("zlog");

const ApiLogger = struct {
    api_logger: zlog.Logger,
    audit_logger: zlog.Logger,
    performance_logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator) !ApiLogger {
        return ApiLogger{
            .api_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = "/var/log/api/requests.log" },
                .async_io = true,
                .level = .info,
            }),
            .audit_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = "/var/log/api/audit.log" },
                .level = .info,
                .async_io = false, // Audit logs need immediate persistence
            }),
            .performance_logger = try zlog.Logger.init(allocator, .{
                .format = .binary,
                .output_target = .{ .file = "/var/log/api/performance.log" },
                .async_io = true,
                .level = .debug,
            }),
        };
    }

    pub fn deinit(self: *ApiLogger) void {
        self.api_logger.deinit();
        self.audit_logger.deinit();
        self.performance_logger.deinit();
    }
};

const ApiEndpoint = struct {
    path: []const u8,
    method: []const u8,
    handler: *const fn (*ApiContext) anyerror!void,
    requires_auth: bool,
    rate_limit: ?u32,
};

const ApiContext = struct {
    request_id: []const u8,
    user_id: ?u64,
    logger: *ApiLogger,
    start_time: i64,
    path: []const u8,
    method: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        logger: *ApiLogger,
        path: []const u8,
        method: []const u8,
    ) !ApiContext {
        const request_id = try generateRequestId(allocator);
        return ApiContext{
            .request_id = request_id,
            .user_id = null,
            .logger = logger,
            .start_time = std.time.nanoTimestamp(),
            .path = path,
            .method = method,
        };
    }

    pub fn deinit(self: *ApiContext, allocator: std.mem.Allocator) void {
        allocator.free(self.request_id);
    }

    pub fn logApiCall(self: *ApiContext, status: u32, response_size: usize) void {
        const duration_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - self.start_time)) / 1_000_000.0;

        // API access log
        var fields = std.ArrayList(zlog.Field).init(std.heap.page_allocator);
        defer fields.deinit();

        fields.appendSlice(&[_]zlog.Field{
            zlog.str("request_id", self.request_id),
            zlog.str("method", self.method),
            zlog.str("path", self.path),
            zlog.uint("status", status),
            zlog.float("duration_ms", duration_ms),
            zlog.uint("response_size", response_size),
        }) catch return;

        if (self.user_id) |uid| {
            fields.append(zlog.uint("user_id", uid)) catch return;
        }

        self.logger.api_logger.logWithFields(.info, "API request", fields.items);

        // Performance logging
        self.logger.performance_logger.logWithFields(.debug, "API performance", &[_]zlog.Field{
            zlog.str("endpoint", self.path),
            zlog.float("response_time_ms", duration_ms),
            zlog.uint("response_size", response_size),
        });
    }

    pub fn logAuditEvent(self: *ApiContext, action: []const u8, resource: []const u8, details: ?[]const u8) void {
        self.logger.audit_logger.logWithFields(.info, "Audit event", &[_]zlog.Field{
            zlog.str("request_id", self.request_id),
            zlog.str("action", action),
            zlog.str("resource", resource),
            zlog.str("details", details orelse ""),
            zlog.uint("user_id", self.user_id orelse 0),
            zlog.uint("timestamp", @intCast(std.time.timestamp())),
        });
    }

    pub fn logError(self: *ApiContext, err: anyerror, context: []const u8) void {
        self.logger.api_logger.logWithFields(.err, "API error", &[_]zlog.Field{
            zlog.str("request_id", self.request_id),
            zlog.str("error", @errorName(err)),
            zlog.str("context", context),
            zlog.str("path", self.path),
            zlog.str("method", self.method),
        });
    }

    fn generateRequestId(allocator: std.mem.Allocator) ![]u8 {
        var buf: [16]u8 = undefined;
        std.crypto.random.bytes(&buf);
        return try std.fmt.allocPrint(allocator, "req_{}", .{std.fmt.fmtSliceHexLower(&buf)});
    }
};

// Example API endpoints
fn getUserProfile(ctx: *ApiContext) !void {
    ctx.logAuditEvent("read", "user_profile", null);

    // Simulate processing
    std.time.sleep(50 * std.time.ns_per_ms); // 50ms processing time

    ctx.logApiCall(200, 1024);
}

fn updateUserProfile(ctx: *ApiContext) !void {
    ctx.logAuditEvent("update", "user_profile", "Profile updated successfully");

    // Simulate processing
    std.time.sleep(100 * std.time.ns_per_ms); // 100ms processing time

    ctx.logApiCall(200, 512);
}

fn deleteUser(ctx: *ApiContext) !void {
    ctx.logAuditEvent("delete", "user", "User account permanently deleted");

    // Simulate processing
    std.time.sleep(200 * std.time.ns_per_ms); // 200ms processing time

    ctx.logApiCall(204, 0);
}

const api_endpoints = [_]ApiEndpoint{
    .{ .path = "/api/users/profile", .method = "GET", .handler = getUserProfile, .requires_auth = true, .rate_limit = 100 },
    .{ .path = "/api/users/profile", .method = "PUT", .handler = updateUserProfile, .requires_auth = true, .rate_limit = 10 },
    .{ .path = "/api/users", .method = "DELETE", .handler = deleteUser, .requires_auth = true, .rate_limit = 1 },
};
```

## Database Integration

### Database Connection Pool with Logging

```zig
const std = @import("std");
const zlog = @import("zlog");

const DatabaseLogger = struct {
    query_logger: zlog.Logger,
    connection_logger: zlog.Logger,
    slow_query_logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator) !DatabaseLogger {
        return DatabaseLogger{
            .query_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = "/var/log/db/queries.log" },
                .async_io = true,
                .level = .debug,
                .sampling_rate = 0.1, // Sample 10% of queries
            }),
            .connection_logger = try zlog.Logger.init(allocator, .{
                .format = .text,
                .output_target = .{ .file = "/var/log/db/connections.log" },
                .level = .info,
            }),
            .slow_query_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = "/var/log/db/slow_queries.log" },
                .level = .warn,
                .async_io = false, // Immediate logging for slow queries
            }),
        };
    }

    pub fn deinit(self: *DatabaseLogger) void {
        self.query_logger.deinit();
        self.connection_logger.deinit();
        self.slow_query_logger.deinit();
    }
};

const DatabaseConnection = struct {
    id: u32,
    created_at: i64,
    last_used: std.atomic.Atomic(i64),
    is_busy: std.atomic.Atomic(bool),
    logger: *DatabaseLogger,

    pub fn init(id: u32, logger: *DatabaseLogger) DatabaseConnection {
        const now = std.time.timestamp();
        logger.connection_logger.info("Database connection {} created", .{id});

        return DatabaseConnection{
            .id = id,
            .created_at = now,
            .last_used = std.atomic.Atomic(i64).init(now),
            .is_busy = std.atomic.Atomic(bool).init(false),
            .logger = logger,
        };
    }

    pub fn executeQuery(self: *DatabaseConnection, query: []const u8, params: []const []const u8) !QueryResult {
        const start_time = std.time.nanoTimestamp();
        const query_id = generateQueryId();

        self.is_busy.store(true, .Monotonic);
        defer self.is_busy.store(false, .Monotonic);

        self.logger.query_logger.logWithFields(.debug, "Query started", &[_]zlog.Field{
            zlog.str("query_id", query_id),
            zlog.uint("connection_id", self.id),
            zlog.str("query", query),
            zlog.uint("param_count", params.len),
        });

        // Simulate query execution
        const result = try self.simulateQuery(query, params);

        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

        // Log query completion
        self.logger.query_logger.logWithFields(.debug, "Query completed", &[_]zlog.Field{
            zlog.str("query_id", query_id),
            zlog.uint("connection_id", self.id),
            zlog.float("duration_ms", duration_ms),
            zlog.uint("rows_affected", result.rows_affected),
        });

        // Log slow queries
        if (duration_ms > 1000.0) { // Slow query threshold: 1 second
            self.logger.slow_query_logger.logWithFields(.warn, "Slow query detected", &[_]zlog.Field{
                zlog.str("query_id", query_id),
                zlog.str("query", query),
                zlog.float("duration_ms", duration_ms),
                zlog.uint("connection_id", self.id),
            });
        }

        self.last_used.store(std.time.timestamp(), .Monotonic);
        return result;
    }

    fn simulateQuery(self: *DatabaseConnection, query: []const u8, params: []const []const u8) !QueryResult {
        _ = self;
        _ = params;

        // Simulate different query types and their execution times
        if (std.mem.indexOf(u8, query, "SELECT") != null) {
            std.time.sleep(10 * std.time.ns_per_ms); // 10ms for SELECT
            return QueryResult{ .rows_affected = 5 };
        } else if (std.mem.indexOf(u8, query, "INSERT") != null) {
            std.time.sleep(50 * std.time.ns_per_ms); // 50ms for INSERT
            return QueryResult{ .rows_affected = 1 };
        } else if (std.mem.indexOf(u8, query, "UPDATE") != null) {
            std.time.sleep(75 * std.time.ns_per_ms); // 75ms for UPDATE
            return QueryResult{ .rows_affected = 3 };
        } else {
            std.time.sleep(100 * std.time.ns_per_ms); // 100ms for other queries
            return QueryResult{ .rows_affected = 0 };
        }
    }

    fn generateQueryId() []const u8 {
        // Simple counter-based ID for demo
        const static = struct {
            var counter: std.atomic.Atomic(u64) = std.atomic.Atomic(u64).init(0);
        };
        const id = static.counter.fetchAdd(1, .Monotonic);
        return std.fmt.comptimePrint("q{d}", .{id});
    }
};

const QueryResult = struct {
    rows_affected: u64,
};

const DatabasePool = struct {
    connections: std.ArrayList(DatabaseConnection),
    logger: DatabaseLogger,
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, pool_size: u32) !DatabasePool {
        var logger = try DatabaseLogger.init(allocator);
        var connections = std.ArrayList(DatabaseConnection).init(allocator);

        logger.connection_logger.info("Creating database pool with {} connections", .{pool_size});

        for (0..pool_size) |i| {
            const conn = DatabaseConnection.init(@intCast(i), &logger);
            try connections.append(conn);
        }

        return DatabasePool{
            .connections = connections,
            .logger = logger,
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *DatabasePool) void {
        self.logger.connection_logger.info("Shutting down database pool", .{});
        self.connections.deinit();
        self.logger.deinit();
    }

    pub fn getConnection(self: *DatabasePool) ?*DatabaseConnection {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.connections.items) |*conn| {
            if (!conn.is_busy.load(.Monotonic)) {
                return conn;
            }
        }

        self.logger.connection_logger.warn("No available database connections", .{});
        return null;
    }

    pub fn executeQuery(self: *DatabasePool, query: []const u8, params: []const []const u8) !QueryResult {
        const conn = self.getConnection() orelse return error.NoAvailableConnections;
        return try conn.executeQuery(query, params);
    }
};
```

## Microservices

### Service Discovery and Communication

```zig
const std = @import("std");
const zlog = @import("zlog");

const ServiceLogger = struct {
    service_logger: zlog.Logger,
    discovery_logger: zlog.Logger,
    communication_logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator, service_name: []const u8) !ServiceLogger {
        const service_log_file = try std.fmt.allocPrint(allocator, "/var/log/services/{s}.log", .{service_name});
        defer allocator.free(service_log_file);

        return ServiceLogger{
            .service_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = service_log_file },
                .async_io = true,
                .level = .info,
            }),
            .discovery_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = "/var/log/services/discovery.log" },
                .level = .info,
            }),
            .communication_logger = try zlog.Logger.init(allocator, .{
                .format = .binary,
                .output_target = .{ .file = "/var/log/services/communication.log" },
                .async_io = true,
                .level = .debug,
                .sampling_rate = 0.05, // Sample 5% of communications
            }),
        };
    }

    pub fn deinit(self: *ServiceLogger) void {
        self.service_logger.deinit();
        self.discovery_logger.deinit();
        self.communication_logger.deinit();
    }
};

const ServiceInstance = struct {
    id: []const u8,
    name: []const u8,
    version: []const u8,
    host: []const u8,
    port: u16,
    health_check_url: []const u8,
    logger: *ServiceLogger,

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        version: []const u8,
        host: []const u8,
        port: u16,
        logger: *ServiceLogger,
    ) !ServiceInstance {
        const id = try std.fmt.allocPrint(allocator, "{s}-{d}-{d}", .{ name, port, std.time.timestamp() });
        const health_url = try std.fmt.allocPrint(allocator, "http://{s}:{d}/health", .{ host, port });

        return ServiceInstance{
            .id = id,
            .name = name,
            .version = version,
            .host = host,
            .port = port,
            .health_check_url = health_url,
            .logger = logger,
        };
    }

    pub fn deinit(self: *ServiceInstance, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.health_check_url);
    }

    pub fn start(self: *ServiceInstance) void {
        self.logger.service_logger.logWithFields(.info, "Service starting", &[_]zlog.Field{
            zlog.str("service_id", self.id),
            zlog.str("service_name", self.name),
            zlog.str("version", self.version),
            zlog.str("host", self.host),
            zlog.uint("port", self.port),
        });
    }

    pub fn stop(self: *ServiceInstance) void {
        self.logger.service_logger.logWithFields(.info, "Service stopping", &[_]zlog.Field{
            zlog.str("service_id", self.id),
            zlog.str("service_name", self.name),
        });
    }

    pub fn registerWithDiscovery(self: *ServiceInstance) !void {
        self.logger.discovery_logger.logWithFields(.info, "Service registration", &[_]zlog.Field{
            zlog.str("action", "register"),
            zlog.str("service_id", self.id),
            zlog.str("service_name", self.name),
            zlog.str("endpoint", self.health_check_url),
        });

        // Simulate registration process
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    pub fn deregisterFromDiscovery(self: *ServiceInstance) void {
        self.logger.discovery_logger.logWithFields(.info, "Service deregistration", &[_]zlog.Field{
            zlog.str("action", "deregister"),
            zlog.str("service_id", self.id),
            zlog.str("service_name", self.name),
        });
    }

    pub fn callService(
        self: *ServiceInstance,
        target_service: []const u8,
        endpoint: []const u8,
        request_data: []const u8,
    ) ![]const u8 {
        const call_id = try generateCallId();
        const start_time = std.time.nanoTimestamp();

        self.logger.communication_logger.logWithFields(.debug, "Service call started", &[_]zlog.Field{
            zlog.str("call_id", call_id),
            zlog.str("from_service", self.name),
            zlog.str("to_service", target_service),
            zlog.str("endpoint", endpoint),
            zlog.uint("request_size", request_data.len),
        });

        // Simulate service call
        std.time.sleep(50 * std.time.ns_per_ms);
        const response = "mock response data";

        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

        self.logger.communication_logger.logWithFields(.debug, "Service call completed", &[_]zlog.Field{
            zlog.str("call_id", call_id),
            zlog.str("from_service", self.name),
            zlog.str("to_service", target_service),
            zlog.float("duration_ms", duration_ms),
            zlog.uint("response_size", response.len),
            zlog.boolean("success", true),
        });

        return response;
    }

    pub fn handleIncomingCall(
        self: *ServiceInstance,
        from_service: []const u8,
        endpoint: []const u8,
        request_data: []const u8,
    ) ![]const u8 {
        const call_id = try generateCallId();

        self.logger.communication_logger.logWithFields(.debug, "Incoming service call", &[_]zlog.Field{
            zlog.str("call_id", call_id),
            zlog.str("from_service", from_service),
            zlog.str("to_service", self.name),
            zlog.str("endpoint", endpoint),
            zlog.uint("request_size", request_data.len),
        });

        // Process request
        const response = try self.processRequest(endpoint, request_data);

        self.logger.communication_logger.logWithFields(.debug, "Service call response", &[_]zlog.Field{
            zlog.str("call_id", call_id),
            zlog.uint("response_size", response.len),
        });

        return response;
    }

    fn processRequest(self: *ServiceInstance, endpoint: []const u8, request_data: []const u8) ![]const u8 {
        _ = self;
        _ = endpoint;
        _ = request_data;

        // Simulate request processing
        std.time.sleep(25 * std.time.ns_per_ms);
        return "processed response";
    }

    fn generateCallId() ![]const u8 {
        const static = struct {
            var counter: std.atomic.Atomic(u64) = std.atomic.Atomic(u64).init(0);
        };
        const id = static.counter.fetchAdd(1, .Monotonic);
        return std.fmt.comptimePrint("call_{d}", .{id});
    }
};

// Example usage
pub fn runMicroservice() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try ServiceLogger.init(allocator, "user-service");
    defer logger.deinit();

    var service = try ServiceInstance.init(allocator, "user-service", "1.0.0", "localhost", 8080, &logger);
    defer service.deinit(allocator);

    service.start();
    try service.registerWithDiscovery();

    // Simulate service operation
    _ = try service.callService("auth-service", "/validate", "user_token_data");
    _ = try service.handleIncomingCall("api-gateway", "/users/123", "get_user_request");

    service.deregisterFromDiscovery();
    service.stop();
}
```

## Game Development

### Game Engine Logging

```zig
const std = @import("std");
const zlog = @import("zlog");

const GameLogger = struct {
    engine_logger: zlog.Logger,
    gameplay_logger: zlog.Logger,
    performance_logger: zlog.Logger,
    debug_logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator) !GameLogger {
        return GameLogger{
            .engine_logger = try zlog.Logger.init(allocator, .{
                .format = .text,
                .output_target = .{ .file = "logs/engine.log" },
                .level = .info,
            }),
            .gameplay_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = "logs/gameplay.log" },
                .async_io = true,
                .level = .debug,
                .sampling_rate = 0.1, // Sample gameplay events
            }),
            .performance_logger = try zlog.Logger.init(allocator, .{
                .format = .binary,
                .output_target = .{ .file = "logs/performance.log" },
                .async_io = true,
                .level = .debug,
            }),
            .debug_logger = try zlog.Logger.init(allocator, .{
                .format = .text,
                .output_target = .stderr,
                .level = .debug,
                .async_io = false, // Immediate debug output
            }),
        };
    }

    pub fn deinit(self: *GameLogger) void {
        self.engine_logger.deinit();
        self.gameplay_logger.deinit();
        self.performance_logger.deinit();
        self.debug_logger.deinit();
    }
};

const GameEngine = struct {
    logger: GameLogger,
    frame_count: u64,
    last_frame_time: i64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !GameEngine {
        var logger = try GameLogger.init(allocator);
        logger.engine_logger.info("Game engine initializing", .{});

        return GameEngine{
            .logger = logger,
            .frame_count = 0,
            .last_frame_time = std.time.nanoTimestamp(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GameEngine) void {
        self.logger.engine_logger.info("Game engine shutting down", .{});
        self.logger.deinit();
    }

    pub fn runGameLoop(self: *GameEngine) !void {
        self.logger.engine_logger.info("Starting game loop", .{});

        while (self.frame_count < 1000) { // Run for 1000 frames
            try self.updateFrame();
        }

        self.logger.engine_logger.info("Game loop completed", .{});
    }

    fn updateFrame(self: *GameEngine) !void {
        const frame_start = std.time.nanoTimestamp();
        self.frame_count += 1;

        // Simulate game systems
        try self.updatePhysics();
        try self.updateGameplay();
        try self.updateRendering();

        const frame_end = std.time.nanoTimestamp();
        const frame_time_ms = @as(f64, @floatFromInt(frame_end - frame_start)) / 1_000_000.0;
        const fps = 1000.0 / frame_time_ms;

        // Log performance metrics
        if (self.frame_count % 60 == 0) { // Every 60 frames
            self.logger.performance_logger.logWithFields(.debug, "Frame performance", &[_]zlog.Field{
                zlog.uint("frame", self.frame_count),
                zlog.float("frame_time_ms", frame_time_ms),
                zlog.float("fps", fps),
            });
        }

        // Log performance warnings
        if (frame_time_ms > 16.67) { // >60fps target
            self.logger.debug_logger.warn("Frame time exceeded target: {d:.2}ms (target: 16.67ms)", .{frame_time_ms});
        }

        self.last_frame_time = frame_start;
    }

    fn updatePhysics(self: *GameEngine) !void {
        // Simulate physics update
        std.time.sleep(5 * std.time.ns_per_ms);

        if (self.frame_count % 300 == 0) { // Log physics state periodically
            self.logger.gameplay_logger.logWithFields(.debug, "Physics update", &[_]zlog.Field{
                zlog.uint("frame", self.frame_count),
                zlog.str("system", "physics"),
                zlog.uint("active_bodies", 150),
                zlog.uint("collision_checks", 75),
            });
        }
    }

    fn updateGameplay(self: *GameEngine) !void {
        // Simulate gameplay events
        std.time.sleep(3 * std.time.ns_per_ms);

        // Log player actions
        if (self.frame_count % 120 == 0) { // Every 2 seconds at 60fps
            self.logPlayerAction("move", 100, 200);
        }

        if (self.frame_count % 600 == 0) { // Every 10 seconds
            self.logGameEvent("enemy_spawn", "goblin", 150, 250);
        }
    }

    fn updateRendering(self: *GameEngine) !void {
        // Simulate rendering
        std.time.sleep(8 * std.time.ns_per_ms);

        if (self.frame_count % 180 == 0) { // Every 3 seconds
            self.logger.performance_logger.logWithFields(.debug, "Render stats", &[_]zlog.Field{
                zlog.uint("frame", self.frame_count),
                zlog.str("system", "renderer"),
                zlog.uint("draw_calls", 45),
                zlog.uint("triangles", 15000),
                zlog.uint("texture_memory_mb", 128),
            });
        }
    }

    pub fn logPlayerAction(self: *GameEngine, action: []const u8, x: i32, y: i32) void {
        self.logger.gameplay_logger.logWithFields(.info, "Player action", &[_]zlog.Field{
            zlog.str("action", action),
            zlog.uint("frame", self.frame_count),
            zlog.uint("x", @intCast(x)),
            zlog.uint("y", @intCast(y)),
            zlog.str("player_id", "player_1"),
        });
    }

    pub fn logGameEvent(self: *GameEngine, event_type: []const u8, entity: []const u8, x: i32, y: i32) void {
        self.logger.gameplay_logger.logWithFields(.info, "Game event", &[_]zlog.Field{
            zlog.str("event", event_type),
            zlog.str("entity", entity),
            zlog.uint("frame", self.frame_count),
            zlog.uint("x", @intCast(x)),
            zlog.uint("y", @intCast(y)),
        });
    }

    pub fn logError(self: *GameEngine, err: anyerror, context: []const u8) void {
        self.logger.engine_logger.logWithFields(.err, "Game engine error", &[_]zlog.Field{
            zlog.str("error", @errorName(err)),
            zlog.str("context", context),
            zlog.uint("frame", self.frame_count),
        });
    }
};

pub fn runGame() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try GameEngine.init(allocator);
    defer engine.deinit();

    try engine.runGameLoop();
}
```

## CLI Applications

### Command-Line Tool with Structured Logging

```zig
const std = @import("std");
const zlog = @import("zlog");

const CliLogger = struct {
    user_logger: zlog.Logger,
    debug_logger: zlog.Logger,
    audit_logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator, verbose: bool, log_file: ?[]const u8) !CliLogger {
        const debug_level: zlog.Level = if (verbose) .debug else .warn;

        return CliLogger{
            .user_logger = try zlog.Logger.init(allocator, .{
                .format = .text,
                .output_target = .stderr,
                .level = .info,
                .enable_colors = true,
            }),
            .debug_logger = try zlog.Logger.init(allocator, .{
                .format = .text,
                .output_target = if (log_file) |file| .{ .file = file } else .stderr,
                .level = debug_level,
            }),
            .audit_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = log_file orelse "cli_audit.log" },
                .level = .info,
            }),
        };
    }

    pub fn deinit(self: *CliLogger) void {
        self.user_logger.deinit();
        self.debug_logger.deinit();
        self.audit_logger.deinit();
    }
};

const CliCommand = struct {
    name: []const u8,
    description: []const u8,
    handler: *const fn (*CliContext, [][]const u8) anyerror!void,
};

const CliContext = struct {
    logger: *CliLogger,
    allocator: std.mem.Allocator,
    start_time: i64,
    command_name: []const u8,

    pub fn init(allocator: std.mem.Allocator, logger: *CliLogger, command_name: []const u8) CliContext {
        return CliContext{
            .logger = logger,
            .allocator = allocator,
            .start_time = std.time.nanoTimestamp(),
            .command_name = command_name,
        };
    }

    pub fn info(self: *CliContext, comptime fmt: []const u8, args: anytype) void {
        self.logger.user_logger.info(fmt, args);
    }

    pub fn warn(self: *CliContext, comptime fmt: []const u8, args: anytype) void {
        self.logger.user_logger.warn(fmt, args);
    }

    pub fn err(self: *CliContext, comptime fmt: []const u8, args: anytype) void {
        self.logger.user_logger.err(fmt, args);
    }

    pub fn debug(self: *CliContext, comptime fmt: []const u8, args: anytype) void {
        self.logger.debug_logger.debug(fmt, args);
    }

    pub fn logCommandStart(self: *CliContext, args: [][]const u8) void {
        self.logger.audit_logger.logWithFields(.info, "Command started", &[_]zlog.Field{
            zlog.str("command", self.command_name),
            zlog.uint("arg_count", args.len),
            zlog.uint("start_timestamp", @intCast(std.time.timestamp())),
        });

        self.debug("Starting command '{s}' with {d} arguments", .{ self.command_name, args.len });
    }

    pub fn logCommandEnd(self: *CliContext, success: bool, exit_code: u8) void {
        const duration_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - self.start_time)) / 1_000_000.0;

        self.logger.audit_logger.logWithFields(.info, "Command completed", &[_]zlog.Field{
            zlog.str("command", self.command_name),
            zlog.boolean("success", success),
            zlog.uint("exit_code", exit_code),
            zlog.float("duration_ms", duration_ms),
        });

        if (success) {
            self.debug("Command '{s}' completed successfully in {d:.2}ms", .{ self.command_name, duration_ms });
        } else {
            self.debug("Command '{s}' failed with exit code {d} after {d:.2}ms", .{ self.command_name, exit_code, duration_ms });
        }
    }

    pub fn logFileOperation(self: *CliContext, operation: []const u8, file_path: []const u8, success: bool) void {
        self.logger.audit_logger.logWithFields(.info, "File operation", &[_]zlog.Field{
            zlog.str("operation", operation),
            zlog.str("file_path", file_path),
            zlog.boolean("success", success),
            zlog.str("command", self.command_name),
        });
    }
};

// Example CLI commands
fn listCommand(ctx: *CliContext, args: [][]const u8) !void {
    ctx.debug("List command processing {d} arguments", .{args.len});

    const path = if (args.len > 0) args[0] else ".";
    ctx.info("Listing directory: {s}", .{path});

    // Simulate directory listing
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
        ctx.err("Failed to open directory '{s}': {}", .{ path, err });
        ctx.logFileOperation("list", path, false);
        return err;
    };
    defer dir.close();

    var file_count: u32 = 0;
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        ctx.info("  {s}", .{entry.name});
        file_count += 1;
    }

    ctx.info("Found {d} entries", .{file_count});
    ctx.logFileOperation("list", path, true);
}

fn copyCommand(ctx: *CliContext, args: [][]const u8) !void {
    if (args.len < 2) {
        ctx.err("Copy command requires source and destination arguments");
        return error.InvalidArguments;
    }

    const src = args[0];
    const dst = args[1];

    ctx.info("Copying '{s}' to '{s}'", .{ src, dst });
    ctx.debug("Copy operation: source={s}, destination={s}", .{ src, dst });

    // Simulate file copy
    std.fs.cwd().copyFile(src, std.fs.cwd(), dst, .{}) catch |err| {
        ctx.err("Failed to copy file: {}", .{err});
        ctx.logFileOperation("copy", src, false);
        return err;
    };

    ctx.info("File copied successfully");
    ctx.logFileOperation("copy", src, true);
}

fn deleteCommand(ctx: *CliContext, args: [][]const u8) !void {
    if (args.len < 1) {
        ctx.err("Delete command requires file path argument");
        return error.InvalidArguments;
    }

    const file_path = args[0];
    ctx.warn("Deleting file: {s}", .{file_path});
    ctx.debug("Delete operation: file={s}", .{file_path});

    // Simulate file deletion
    std.fs.cwd().deleteFile(file_path) catch |err| {
        ctx.err("Failed to delete file '{s}': {}", .{ file_path, err });
        ctx.logFileOperation("delete", file_path, false);
        return err;
    };

    ctx.info("File deleted successfully");
    ctx.logFileOperation("delete", file_path, true);
}

const commands = [_]CliCommand{
    .{ .name = "list", .description = "List directory contents", .handler = listCommand },
    .{ .name = "copy", .description = "Copy file from source to destination", .handler = copyCommand },
    .{ .name = "delete", .description = "Delete specified file", .handler = deleteCommand },
};

pub fn runCli() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <command> [args...]\n", .{args[0]});
        std.debug.print("Available commands:\n");
        for (commands) |cmd| {
            std.debug.print("  {s}: {s}\n", .{ cmd.name, cmd.description });
        }
        return;
    }

    const verbose = std.mem.eql(u8, std.os.getenv("VERBOSE") orelse "", "1");
    var logger = try CliLogger.init(allocator, verbose, "cli.log");
    defer logger.deinit();

    const command_name = args[1];
    const command_args = args[2..];

    // Find and execute command
    for (commands) |cmd| {
        if (std.mem.eql(u8, cmd.name, command_name)) {
            var ctx = CliContext.init(allocator, &logger, command_name);
            ctx.logCommandStart(command_args);

            var success = true;
            var exit_code: u8 = 0;

            cmd.handler(&ctx, command_args) catch |err| {
                ctx.err("Command failed: {}", .{err});
                success = false;
                exit_code = 1;
            };

            ctx.logCommandEnd(success, exit_code);
            std.process.exit(exit_code);
        }
    }

    logger.user_logger.err("Unknown command: {s}", .{command_name});
    std.process.exit(1);
}
```

## Systems Programming

### System Monitor with zlog

```zig
const std = @import("std");
const zlog = @import("zlog");

const SystemLogger = struct {
    metrics_logger: zlog.Logger,
    alerts_logger: zlog.Logger,
    status_logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator) !SystemLogger {
        return SystemLogger{
            .metrics_logger = try zlog.Logger.init(allocator, .{
                .format = .binary,
                .output_target = .{ .file = "/var/log/system/metrics.log" },
                .async_io = true,
                .level = .debug,
            }),
            .alerts_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = "/var/log/system/alerts.log" },
                .level = .warn,
                .async_io = false, // Immediate alert logging
            }),
            .status_logger = try zlog.Logger.init(allocator, .{
                .format = .text,
                .output_target = .stdout,
                .level = .info,
            }),
        };
    }

    pub fn deinit(self: *SystemLogger) void {
        self.metrics_logger.deinit();
        self.alerts_logger.deinit();
        self.status_logger.deinit();
    }
};

const SystemMetrics = struct {
    cpu_usage: f64,
    memory_usage: f64,
    disk_usage: f64,
    network_in: u64,
    network_out: u64,
    load_average: f64,
    uptime: u64,
};

const SystemMonitor = struct {
    logger: SystemLogger,
    allocator: std.mem.Allocator,
    monitoring: bool,

    pub fn init(allocator: std.mem.Allocator) !SystemMonitor {
        return SystemMonitor{
            .logger = try SystemLogger.init(allocator),
            .allocator = allocator,
            .monitoring = false,
        };
    }

    pub fn deinit(self: *SystemMonitor) void {
        self.logger.deinit();
    }

    pub fn startMonitoring(self: *SystemMonitor) !void {
        self.monitoring = true;
        self.logger.status_logger.info("System monitoring started", .{});

        while (self.monitoring) {
            const metrics = try self.collectMetrics();
            self.logMetrics(metrics);
            self.checkThresholds(metrics);

            std.time.sleep(5 * std.time.ns_per_s); // Monitor every 5 seconds
        }
    }

    pub fn stopMonitoring(self: *SystemMonitor) void {
        self.monitoring = false;
        self.logger.status_logger.info("System monitoring stopped", .{});
    }

    fn collectMetrics(self: *SystemMonitor) !SystemMetrics {
        _ = self;

        // Simulate metric collection (in real implementation, would read from /proc, etc.)
        return SystemMetrics{
            .cpu_usage = 45.2 + (std.crypto.random.float(f64) * 20.0), // 45-65%
            .memory_usage = 60.1 + (std.crypto.random.float(f64) * 15.0), // 60-75%
            .disk_usage = 78.5 + (std.crypto.random.float(f64) * 10.0), // 78-88%
            .network_in = 1024 * 1024 * @as(u64, @intFromFloat(std.crypto.random.float(f64) * 100)), // 0-100MB
            .network_out = 512 * 1024 * @as(u64, @intFromFloat(std.crypto.random.float(f64) * 50)), // 0-25MB
            .load_average = 1.2 + (std.crypto.random.float(f64) * 2.0), // 1.2-3.2
            .uptime = 86400 * 7, // 7 days
        };
    }

    fn logMetrics(self: *SystemMonitor, metrics: SystemMetrics) void {
        self.logger.metrics_logger.logWithFields(.debug, "System metrics", &[_]zlog.Field{
            zlog.float("cpu_usage", metrics.cpu_usage),
            zlog.float("memory_usage", metrics.memory_usage),
            zlog.float("disk_usage", metrics.disk_usage),
            zlog.uint("network_in", metrics.network_in),
            zlog.uint("network_out", metrics.network_out),
            zlog.float("load_average", metrics.load_average),
            zlog.uint("uptime", metrics.uptime),
            zlog.uint("timestamp", @intCast(std.time.timestamp())),
        });

        // Periodic status update
        if (@mod(std.time.timestamp(), 60) == 0) { // Every minute
            self.logger.status_logger.info(
                "System status: CPU: {d:.1}%, Memory: {d:.1}%, Disk: {d:.1}%, Load: {d:.2}",
                .{ metrics.cpu_usage, metrics.memory_usage, metrics.disk_usage, metrics.load_average },
            );
        }
    }

    fn checkThresholds(self: *SystemMonitor, metrics: SystemMetrics) void {
        // CPU usage threshold
        if (metrics.cpu_usage > 80.0) {
            self.logger.alerts_logger.logWithFields(.warn, "High CPU usage alert", &[_]zlog.Field{
                zlog.str("alert_type", "high_cpu"),
                zlog.float("cpu_usage", metrics.cpu_usage),
                zlog.float("threshold", 80.0),
                zlog.str("severity", "warning"),
            });
        }

        if (metrics.cpu_usage > 95.0) {
            self.logger.alerts_logger.logWithFields(.err, "Critical CPU usage alert", &[_]zlog.Field{
                zlog.str("alert_type", "critical_cpu"),
                zlog.float("cpu_usage", metrics.cpu_usage),
                zlog.float("threshold", 95.0),
                zlog.str("severity", "critical"),
            });
        }

        // Memory usage threshold
        if (metrics.memory_usage > 85.0) {
            self.logger.alerts_logger.logWithFields(.warn, "High memory usage alert", &[_]zlog.Field{
                zlog.str("alert_type", "high_memory"),
                zlog.float("memory_usage", metrics.memory_usage),
                zlog.float("threshold", 85.0),
                zlog.str("severity", "warning"),
            });
        }

        // Disk usage threshold
        if (metrics.disk_usage > 90.0) {
            self.logger.alerts_logger.logWithFields(.err, "High disk usage alert", &[_]zlog.Field{
                zlog.str("alert_type", "high_disk"),
                zlog.float("disk_usage", metrics.disk_usage),
                zlog.float("threshold", 90.0),
                zlog.str("severity", "critical"),
            });
        }

        // Load average threshold
        if (metrics.load_average > 5.0) {
            self.logger.alerts_logger.logWithFields(.warn, "High load average alert", &[_]zlog.Field{
                zlog.str("alert_type", "high_load"),
                zlog.float("load_average", metrics.load_average),
                zlog.float("threshold", 5.0),
                zlog.str("severity", "warning"),
            });
        }
    }
};

pub fn runSystemMonitor() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = try SystemMonitor.init(allocator);
    defer monitor.deinit();

    // Set up signal handling to stop monitoring gracefully
    // In a real implementation, you'd use signal handlers

    try monitor.startMonitoring();
}
```

## Testing Frameworks

### Test Runner with Structured Logging

```zig
const std = @import("std");
const zlog = @import("zlog");

const TestLogger = struct {
    test_logger: zlog.Logger,
    result_logger: zlog.Logger,
    debug_logger: zlog.Logger,

    pub fn init(allocator: std.mem.Allocator, verbose: bool) !TestLogger {
        return TestLogger{
            .test_logger = try zlog.Logger.init(allocator, .{
                .format = .text,
                .output_target = .stdout,
                .level = if (verbose) .debug else .info,
                .enable_colors = true,
            }),
            .result_logger = try zlog.Logger.init(allocator, .{
                .format = .json,
                .output_target = .{ .file = "test_results.log" },
                .level = .info,
            }),
            .debug_logger = try zlog.Logger.init(allocator, .{
                .format = .text,
                .output_target = .{ .file = "test_debug.log" },
                .level = .debug,
            }),
        };
    }

    pub fn deinit(self: *TestLogger) void {
        self.test_logger.deinit();
        self.result_logger.deinit();
        self.debug_logger.deinit();
    }
};

const TestCase = struct {
    name: []const u8,
    test_fn: *const fn (*TestContext) anyerror!void,
    timeout_ms: u32,
    expected_failure: bool,
};

const TestContext = struct {
    logger: *TestLogger,
    test_name: []const u8,
    start_time: i64,
    assertions: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, logger: *TestLogger, test_name: []const u8) TestContext {
        return TestContext{
            .logger = logger,
            .test_name = test_name,
            .start_time = std.time.nanoTimestamp(),
            .assertions = 0,
            .allocator = allocator,
        };
    }

    pub fn assert(self: *TestContext, condition: bool, message: []const u8) !void {
        self.assertions += 1;

        if (condition) {
            self.logger.debug_logger.debug("PASS: {s} - {s}", .{ self.test_name, message });
        } else {
            self.logger.debug_logger.err("FAIL: {s} - {s}", .{ self.test_name, message });
            self.logger.test_logger.err("  Assertion failed: {s}", .{message});
            return error.AssertionFailed;
        }
    }

    pub fn assertEqual(self: *TestContext, expected: anytype, actual: anytype, message: []const u8) !void {
        const equal = if (@TypeOf(expected) == []const u8 and @TypeOf(actual) == []const u8)
            std.mem.eql(u8, expected, actual)
        else
            expected == actual;

        if (equal) {
            self.logger.debug_logger.debug("PASS: {s} - {s} (expected: {any}, actual: {any})", .{ self.test_name, message, expected, actual });
        } else {
            self.logger.debug_logger.err("FAIL: {s} - {s} (expected: {any}, actual: {any})", .{ self.test_name, message, expected, actual });
            self.logger.test_logger.err("  Assertion failed: {s}", .{message});
            self.logger.test_logger.err("    Expected: {any}", .{expected});
            self.logger.test_logger.err("    Actual: {any}", .{actual});
            return error.AssertionFailed;
        }

        self.assertions += 1;
    }

    pub fn log(self: *TestContext, comptime fmt: []const u8, args: anytype) void {
        self.logger.test_logger.debug("  {s}: " ++ fmt, .{self.test_name} ++ args);
    }
};

const TestResult = struct {
    name: []const u8,
    passed: bool,
    duration_ms: f64,
    assertions: u32,
    error_message: ?[]const u8,
};

const TestRunner = struct {
    logger: TestLogger,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, verbose: bool) !TestRunner {
        return TestRunner{
            .logger = try TestLogger.init(allocator, verbose),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestRunner) void {
        self.logger.deinit();
    }

    pub fn runTests(self: *TestRunner, test_cases: []const TestCase) !void {
        self.logger.test_logger.info("Running {d} test cases", .{test_cases.len});

        var results = std.ArrayList(TestResult).init(self.allocator);
        defer results.deinit();

        var passed: u32 = 0;
        var failed: u32 = 0;

        for (test_cases) |test_case| {
            const result = try self.runSingleTest(test_case);
            try results.append(result);

            if (result.passed) {
                passed += 1;
                self.logger.test_logger.info("✓ {s} ({d:.2}ms)", .{ result.name, result.duration_ms });
            } else {
                failed += 1;
                self.logger.test_logger.err("✗ {s} ({d:.2}ms)", .{ result.name, result.duration_ms });
                if (result.error_message) |msg| {
                    self.logger.test_logger.err("  Error: {s}", .{msg});
                }
            }
        }

        // Log summary
        self.logger.test_logger.info("");
        self.logger.test_logger.info("Test Summary:");
        self.logger.test_logger.info("  Total: {d}", .{test_cases.len});
        self.logger.test_logger.info("  Passed: {d}", .{passed});
        self.logger.test_logger.info("  Failed: {d}", .{failed});

        // Log detailed results
        self.logger.result_logger.logWithFields(.info, "Test run completed", &[_]zlog.Field{
            zlog.uint("total_tests", test_cases.len),
            zlog.uint("passed", passed),
            zlog.uint("failed", failed),
            zlog.float("pass_rate", @as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(test_cases.len)) * 100.0),
        });

        for (results.items) |result| {
            self.logger.result_logger.logWithFields(.info, "Test result", &[_]zlog.Field{
                zlog.str("test_name", result.name),
                zlog.boolean("passed", result.passed),
                zlog.float("duration_ms", result.duration_ms),
                zlog.uint("assertions", result.assertions),
                zlog.str("error", result.error_message orelse ""),
            });
        }
    }

    fn runSingleTest(self: *TestRunner, test_case: TestCase) !TestResult {
        var ctx = TestContext.init(self.allocator, &self.logger, test_case.name);

        self.logger.debug_logger.debug("Starting test: {s}", .{test_case.name});

        var error_message: ?[]const u8 = null;
        var passed = false;

        // Run the test with timeout handling
        test_case.test_fn(&ctx) catch |err| {
            error_message = try std.fmt.allocPrint(self.allocator, "{}", .{err});
            passed = test_case.expected_failure; // Pass if we expected this to fail
        };

        if (error_message == null) {
            passed = !test_case.expected_failure; // Pass if we didn't expect failure
        }

        const duration_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - ctx.start_time)) / 1_000_000.0;

        return TestResult{
            .name = test_case.name,
            .passed = passed,
            .duration_ms = duration_ms,
            .assertions = ctx.assertions,
            .error_message = error_message,
        };
    }
};

// Example test cases
fn testMathOperations(ctx: *TestContext) !void {
    ctx.log("Testing basic math operations");

    try ctx.assertEqual(@as(i32, 4), 2 + 2, "Addition test");
    try ctx.assertEqual(@as(i32, 0), 5 - 5, "Subtraction test");
    try ctx.assertEqual(@as(i32, 15), 3 * 5, "Multiplication test");
    try ctx.assertEqual(@as(i32, 3), 9 / 3, "Division test");

    ctx.log("All math operations passed");
}

fn testStringOperations(ctx: *TestContext) !void {
    ctx.log("Testing string operations");

    const hello = "Hello";
    const world = "World";

    try ctx.assertEqual(@as(usize, 5), hello.len, "String length test");
    try ctx.assert(std.mem.eql(u8, hello, "Hello"), "String equality test");
    try ctx.assert(std.mem.startsWith(u8, hello, "Hel"), "String prefix test");

    ctx.log("String operations completed");
}

fn testFailingCase(ctx: *TestContext) !void {
    ctx.log("This test is expected to fail");

    try ctx.assertEqual(@as(i32, 1), 2, "This should fail");
}

const test_cases = [_]TestCase{
    .{ .name = "Math Operations", .test_fn = testMathOperations, .timeout_ms = 1000, .expected_failure = false },
    .{ .name = "String Operations", .test_fn = testStringOperations, .timeout_ms = 1000, .expected_failure = false },
    .{ .name = "Expected Failure", .test_fn = testFailingCase, .timeout_ms = 1000, .expected_failure = true },
};

pub fn runTestSuite() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const verbose = std.mem.eql(u8, std.os.getenv("VERBOSE") orelse "", "1");
    var runner = try TestRunner.init(allocator, verbose);
    defer runner.deinit();

    try runner.runTests(&test_cases);
}
```

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"content": "Set up comprehensive test suite structure", "status": "completed", "activeForm": "Setting up comprehensive test suite structure"}, {"content": "Create unit tests for all Logger methods and configurations", "status": "completed", "activeForm": "Creating unit tests for all Logger methods and configurations"}, {"content": "Add integration tests for file rotation and async I/O", "status": "completed", "activeForm": "Adding integration tests for file rotation and async I/O"}, {"content": "Implement property-based testing for structured logging", "status": "completed", "activeForm": "Implementing property-based testing for structured logging"}, {"content": "Add error handling and edge case coverage", "status": "completed", "activeForm": "Adding error handling and edge case coverage"}, {"content": "Implement memory leak detection and validation", "status": "completed", "activeForm": "Implementing memory leak detection and validation"}, {"content": "Add cross-platform compatibility tests", "status": "completed", "activeForm": "Adding cross-platform compatibility tests"}, {"content": "Set up continuous benchmarking infrastructure", "status": "completed", "activeForm": "Setting up continuous benchmarking infrastructure"}, {"content": "Add memory usage profiling and optimization", "status": "completed", "activeForm": "Adding memory usage profiling and optimization"}, {"content": "Optimize async I/O performance", "status": "completed", "activeForm": "Optimizing async I/O performance"}, {"content": "Optimize binary format for size and speed", "status": "completed", "activeForm": "Optimizing binary format for size and speed"}, {"content": "Create comparative benchmarks vs spdlog/log4c", "status": "completed", "activeForm": "Creating comparative benchmarks vs spdlog/log4c"}, {"content": "Review and stabilize public API surface", "status": "completed", "activeForm": "Reviewing and stabilizing public API surface"}, {"content": "Improve error types and handling", "status": "completed", "activeForm": "Improving error types and handling"}, {"content": "Standardize configuration validation", "status": "completed", "activeForm": "Standardizing configuration validation"}, {"content": "Add convenience macros for common patterns", "status": "completed", "activeForm": "Adding convenience macros for common patterns"}, {"content": "Improve compile-time feature detection", "status": "completed", "activeForm": "Improving compile-time feature detection"}, {"content": "Complete API documentation with examples", "status": "completed", "activeForm": "Completing API documentation with examples"}, {"content": "Create performance tuning guide", "status": "completed", "activeForm": "Creating performance tuning guide"}, {"content": "Write best practices documentation", "status": "completed", "activeForm": "Writing best practices documentation"}, {"content": "Create migration guides from C/C++ loggers", "status": "completed", "activeForm": "Creating migration guides from C/C++ loggers"}, {"content": "Add integration examples for common frameworks", "status": "completed", "activeForm": "Adding integration examples for common frameworks"}]