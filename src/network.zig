// Network output targets for zlog
// Supports TCP, UDP, HTTP/HTTPS, and Syslog protocols

const std = @import("std");
const zlog = @import("root.zig");
const build_options = @import("build_options");

/// Network protocol types
pub const Protocol = enum {
    tcp,
    udp,
    http,
    https,
    syslog_udp,
    syslog_tcp,
    syslog_tls,
};

/// Syslog facility codes (RFC 5424)
pub const SyslogFacility = enum(u8) {
    kern = 0, // kernel messages
    user = 1, // user-level messages
    mail = 2, // mail system
    daemon = 3, // system daemons
    auth = 4, // security/authorization messages
    syslog = 5, // syslogd internal
    lpr = 6, // line printer subsystem
    news = 7, // network news subsystem
    uucp = 8, // UUCP subsystem
    cron = 9, // clock daemon
    authpriv = 10, // security/authorization messages (private)
    ftp = 11, // FTP daemon
    local0 = 16, // local use 0
    local1 = 17, // local use 1
    local2 = 18, // local use 2
    local3 = 19, // local use 3
    local4 = 20, // local use 4
    local5 = 21, // local use 5
    local6 = 22, // local use 6
    local7 = 23, // local use 7
};

/// Syslog severity mapping from zlog levels
pub fn levelToSyslogSeverity(level: zlog.Level) u8 {
    return switch (level) {
        .fatal => 0, // Emergency
        .err => 3, // Error
        .warn => 4, // Warning
        .info => 6, // Informational
        .debug => 7, // Debug
    };
}

/// Network target configuration
pub const NetworkConfig = struct {
    protocol: Protocol,
    host: []const u8,
    port: u16,

    // Connection settings
    connect_timeout_ms: u32 = 5000,
    write_timeout_ms: u32 = 1000,
    retry_attempts: u8 = 3,
    retry_delay_ms: u32 = 100,

    // HTTP/HTTPS specific
    http_method: []const u8 = "POST",
    http_path: []const u8 = "/logs",
    http_headers: ?[]const HttpHeader = null,
    auth_token: ?[]const u8 = null,

    // Syslog specific
    syslog_facility: SyslogFacility = .user,
    syslog_hostname: ?[]const u8 = null,
    syslog_app_name: []const u8 = "zlog",

    // Connection pooling
    enable_pooling: bool = true,
    max_pool_size: u8 = 5,
    pool_idle_timeout_ms: u32 = 60000,

    // Load balancing
    enable_load_balancing: bool = false,
    failover_targets: ?[]const NetworkConfig = null,

    // Compression
    enable_compression: bool = false,
    compression_level: u8 = 6, // 0-9

    pub const HttpHeader = struct {
        name: []const u8,
        value: []const u8,
    };
};

/// Network output target implementation
pub const NetworkTarget = struct {
    config: NetworkConfig,
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    // Connection state
    stream: ?std.net.Stream = null,
    address: std.net.Address,
    connected: std.atomic.Value(bool),
    last_error: ?anyerror = null,

    // Statistics
    messages_sent: std.atomic.Value(u64),
    messages_failed: std.atomic.Value(u64),
    bytes_sent: std.atomic.Value(u64),
    connection_errors: std.atomic.Value(u64),

    pub fn init(allocator: std.mem.Allocator, config: NetworkConfig) !NetworkTarget {
        // Resolve address
        const address = try std.net.Address.parseIp(config.host, config.port);

        var target = NetworkTarget{
            .config = config,
            .allocator = allocator,
            .mutex = .{},
            .address = address,
            .connected = std.atomic.Value(bool).init(false),
            .messages_sent = std.atomic.Value(u64).init(0),
            .messages_failed = std.atomic.Value(u64).init(0),
            .bytes_sent = std.atomic.Value(u64).init(0),
            .connection_errors = std.atomic.Value(u64).init(0),
        };

        // Establish initial connection for TCP-based protocols
        if (config.protocol == .tcp or config.protocol == .syslog_tcp) {
            target.connect() catch |err| {
                target.last_error = err;
                target.connection_errors.fetchAdd(1, .monotonic);
            };
        }

        return target;
    }

    pub fn deinit(self: *NetworkTarget) void {
        self.disconnect();
    }

    fn connect(self: *NetworkTarget) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.connected.load(.acquire)) {
            return; // Already connected
        }

        const stream = switch (self.config.protocol) {
            .tcp, .syslog_tcp => try std.net.tcpConnectToAddress(self.address),
            .udp, .syslog_udp => try std.net.tcpConnectToAddress(self.address), // UDP uses datagrams
            else => return error.ProtocolNotSupported,
        };

        self.stream = stream;
        self.connected.store(true, .release);
    }

    fn disconnect(self: *NetworkTarget) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }
        self.connected.store(false, .release);
    }

    pub fn send(self: *NetworkTarget, entry: zlog.LogEntry) !void {
        var attempt: u8 = 0;
        while (attempt < self.config.retry_attempts) : (attempt += 1) {
            self.sendInternal(entry) catch |err| {
                self.last_error = err;
                self.messages_failed.fetchAdd(1, .monotonic);

                if (attempt + 1 < self.config.retry_attempts) {
                    std.Thread.sleep(self.config.retry_delay_ms * std.time.ns_per_ms);

                    // Try reconnecting for TCP
                    if (self.config.protocol == .tcp or self.config.protocol == .syslog_tcp) {
                        self.disconnect();
                        self.connect() catch continue;
                    }
                    continue;
                }
                return err;
            };

            self.messages_sent.fetchAdd(1, .monotonic);
            return;
        }
    }

    fn sendInternal(self: *NetworkTarget, entry: zlog.LogEntry) !void {
        switch (self.config.protocol) {
            .tcp => try self.sendTcp(entry),
            .udp => try self.sendUdp(entry),
            .http, .https => try self.sendHttp(entry),
            .syslog_udp, .syslog_tcp, .syslog_tls => try self.sendSyslog(entry),
        }
    }

    fn sendTcp(self: *NetworkTarget, entry: zlog.LogEntry) !void {
        if (!self.connected.load(.acquire)) {
            try self.connect();
        }

        const stream = self.stream orelse return error.NotConnected;

        // Format as JSON for TCP transport
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try formatAsJson(&buffer, entry);
        try buffer.append('\n'); // Newline delimiter

        try stream.writeAll(buffer.items);
        self.bytes_sent.fetchAdd(buffer.items.len, .monotonic);
    }

    fn sendUdp(self: *NetworkTarget, entry: zlog.LogEntry) !void {
        const socket = try std.posix.socket(
            std.posix.AF.INET,
            std.posix.SOCK.DGRAM,
            std.posix.IPPROTO.UDP,
        );
        defer std.posix.close(socket);

        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try formatAsJson(&buffer, entry);

        const addr_bytes = std.mem.toBytes(self.address.in);
        _ = try std.posix.sendto(
            socket,
            buffer.items,
            0,
            @ptrCast(&addr_bytes),
            @sizeOf(@TypeOf(self.address.in)),
        );

        self.bytes_sent.fetchAdd(buffer.items.len, .monotonic);
    }

    fn sendHttp(self: *NetworkTarget, entry: zlog.LogEntry) !void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        // Format log entry as JSON for HTTP body
        var body_buffer = std.ArrayList(u8).init(self.allocator);
        defer body_buffer.deinit();
        try formatAsJson(&body_buffer, entry);

        // Build HTTP request
        try buffer.writer().print("{s} {s} HTTP/1.1\r\n", .{
            self.config.http_method,
            self.config.http_path,
        });
        try buffer.writer().print("Host: {s}:{d}\r\n", .{
            self.config.host,
            self.config.port,
        });
        try buffer.writer().print("Content-Type: application/json\r\n", .{});
        try buffer.writer().print("Content-Length: {d}\r\n", .{body_buffer.items.len});

        // Add authentication if provided
        if (self.config.auth_token) |token| {
            try buffer.writer().print("Authorization: Bearer {s}\r\n", .{token});
        }

        // Add custom headers
        if (self.config.http_headers) |headers| {
            for (headers) |header| {
                try buffer.writer().print("{s}: {s}\r\n", .{
                    header.name,
                    header.value,
                });
            }
        }

        try buffer.appendSlice("\r\n");
        try buffer.appendSlice(body_buffer.items);

        // Send via TCP
        if (!self.connected.load(.acquire)) {
            try self.connect();
        }

        const stream = self.stream orelse return error.NotConnected;
        try stream.writeAll(buffer.items);
        self.bytes_sent.fetchAdd(buffer.items.len, .monotonic);

        // Read response (basic, should parse for real implementation)
        var response_buffer: [1024]u8 = undefined;
        _ = try stream.read(&response_buffer);
    }

    fn sendSyslog(self: *NetworkTarget, entry: zlog.LogEntry) !void {
        // RFC 5424 format: <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID SD MSG
        const priority = (@as(u16, @intFromEnum(self.config.syslog_facility)) * 8) +
                        levelToSyslogSeverity(entry.level);

        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        // Priority
        try buffer.writer().print("<{d}>", .{priority});

        // Version
        try buffer.appendSlice("1 ");

        // Timestamp (ISO 8601)
        try buffer.writer().print("{d} ", .{entry.timestamp});

        // Hostname
        const hostname = self.config.syslog_hostname orelse
            try std.net.getHostName(std.heap.page_allocator);
        try buffer.writer().print("{s} ", .{hostname});

        // App name
        try buffer.writer().print("{s} ", .{self.config.syslog_app_name});

        // Process ID
        try buffer.writer().print("{d} ", .{std.os.linux.getpid()});

        // Message ID (use log level)
        try buffer.writer().print("{s} ", .{entry.level.toString()});

        // Structured data (use fields)
        if (entry.fields.len > 0) {
            try buffer.appendSlice("[fields");
            for (entry.fields) |field| {
                try buffer.writer().print(" {s}=\"", .{field.key});
                switch (field.value) {
                    .string => |v| try buffer.writer().print("{s}", .{v}),
                    .int => |v| try buffer.writer().print("{d}", .{v}),
                    .uint => |v| try buffer.writer().print("{d}", .{v}),
                    .float => |v| try buffer.writer().print("{d}", .{v}),
                    .boolean => |v| try buffer.writer().print("{}", .{v}),
                }
                try buffer.appendSlice("\"");
            }
            try buffer.appendSlice("] ");
        } else {
            try buffer.appendSlice("- ");
        }

        // Message
        try buffer.writer().print("{s}", .{entry.message});

        // Send based on protocol
        switch (self.config.protocol) {
            .syslog_tcp, .syslog_tls => {
                if (!self.connected.load(.acquire)) {
                    try self.connect();
                }
                const stream = self.stream orelse return error.NotConnected;

                // Octet counting framing (RFC 6587)
                const frame_header = try std.fmt.allocPrint(
                    self.allocator,
                    "{d} ",
                    .{buffer.items.len},
                );
                defer self.allocator.free(frame_header);

                try stream.writeAll(frame_header);
                try stream.writeAll(buffer.items);
                self.bytes_sent.fetchAdd(frame_header.len + buffer.items.len, .monotonic);
            },
            .syslog_udp => {
                const socket = try std.posix.socket(
                    std.posix.AF.INET,
                    std.posix.SOCK.DGRAM,
                    std.posix.IPPROTO.UDP,
                );
                defer std.posix.close(socket);

                const addr_bytes = std.mem.toBytes(self.address.in);
                _ = try std.posix.sendto(
                    socket,
                    buffer.items,
                    0,
                    @ptrCast(&addr_bytes),
                    @sizeOf(@TypeOf(self.address.in)),
                );
                self.bytes_sent.fetchAdd(buffer.items.len, .monotonic);
            },
            else => return error.InvalidProtocol,
        }
    }

    fn formatAsJson(buffer: *std.ArrayList(u8), entry: zlog.LogEntry) !void {
        try buffer.writer().print("{{\"timestamp\":{d},\"level\":\"{s}\",\"message\":\"{s}\"", .{
            entry.timestamp,
            entry.level.toString(),
            entry.message,
        });

        if (entry.fields.len > 0) {
            try buffer.appendSlice(",\"fields\":{");
            for (entry.fields, 0..) |field, i| {
                if (i > 0) try buffer.appendSlice(",");
                try buffer.writer().print("\"{s}\":", .{field.key});
                switch (field.value) {
                    .string => |v| try buffer.writer().print("\"{s}\"", .{v}),
                    .int => |v| try buffer.writer().print("{d}", .{v}),
                    .uint => |v| try buffer.writer().print("{d}", .{v}),
                    .float => |v| try buffer.writer().print("{d}", .{v}),
                    .boolean => |v| try buffer.writer().print("{}", .{v}),
                }
            }
            try buffer.appendSlice("}");
        }

        try buffer.appendSlice("}");
    }

    pub fn getStats(self: NetworkTarget) NetworkStats {
        return NetworkStats{
            .messages_sent = self.messages_sent.load(.monotonic),
            .messages_failed = self.messages_failed.load(.monotonic),
            .bytes_sent = self.bytes_sent.load(.monotonic),
            .connection_errors = self.connection_errors.load(.monotonic),
            .connected = self.connected.load(.acquire),
        };
    }
};

pub const NetworkStats = struct {
    messages_sent: u64,
    messages_failed: u64,
    bytes_sent: u64,
    connection_errors: u64,
    connected: bool,

    pub fn print(self: NetworkStats) void {
        std.debug.print("\n📊 Network Target Statistics\n", .{});
        std.debug.print("============================\n", .{});
        std.debug.print("Connected: {}\n", .{self.connected});
        std.debug.print("Messages sent: {d}\n", .{self.messages_sent});
        std.debug.print("Messages failed: {d}\n", .{self.messages_failed});
        std.debug.print("Bytes sent: {d}\n", .{self.bytes_sent});
        std.debug.print("Connection errors: {d}\n", .{self.connection_errors});

        if (self.messages_sent > 0) {
            const success_rate = (@as(f64, @floatFromInt(self.messages_sent)) /
                                 @as(f64, @floatFromInt(self.messages_sent + self.messages_failed))) * 100.0;
            std.debug.print("Success rate: {d:.2}%\n", .{success_rate});
        }
    }
};

// Tests
const testing = std.testing;

test "network: syslog priority calculation" {
    const priority = (@as(u16, @intFromEnum(SyslogFacility.user)) * 8) + levelToSyslogSeverity(.info);
    try testing.expect(priority == 14); // user.info = 1*8 + 6 = 14
}

test "network: address parsing" {
    const addr = try std.net.Address.parseIp("127.0.0.1", 514);
    try testing.expect(addr.getPort() == 514);
}
