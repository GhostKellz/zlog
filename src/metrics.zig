// Performance metrics and monitoring for zlog
// Tracks throughput, latency, errors, and resource usage

const std = @import("std");
const zlog = @import("root.zig");
const build_options = @import("build_options");

// Helper function for getting Unix timestamp (Zig 0.16+ compatibility)
inline fn getUnixTimestamp() i64 {
    const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch unreachable;
    return ts.sec;
}

/// Metric types for different measurements
pub const MetricType = enum {
    counter, // Monotonically increasing value
    gauge, // Current value that can go up or down
    histogram, // Distribution of values
    summary, // Statistical summary (min, max, avg, percentiles)
};

/// Individual metric
pub const Metric = struct {
    name: []const u8,
    metric_type: MetricType,
    value: std.atomic.Value(u64),
    last_updated: std.atomic.Value(i64),
    description: []const u8,

    pub fn init(name: []const u8, metric_type: MetricType, description: []const u8) Metric {
        return Metric{
            .name = name,
            .metric_type = metric_type,
            .value = std.atomic.Value(u64).init(0),
            .last_updated = std.atomic.Value(i64).init(getUnixTimestamp()),
            .description = description,
        };
    }

    pub fn increment(self: *Metric) void {
        _ = self.value.fetchAdd(1, .monotonic);
        self.last_updated.store(getUnixTimestamp(), .monotonic);
    }

    pub fn add(self: *Metric, amount: u64) void {
        _ = self.value.fetchAdd(amount, .monotonic);
        self.last_updated.store(getUnixTimestamp(), .monotonic);
    }

    pub fn set(self: *Metric, value: u64) void {
        self.value.store(value, .monotonic);
        self.last_updated.store(getUnixTimestamp(), .monotonic);
    }

    pub fn get(self: *const Metric) u64 {
        return self.value.load(.monotonic);
    }
};

/// Histogram for tracking value distributions
pub const Histogram = struct {
    name: []const u8,
    buckets: []Bucket,
    allocator: std.mem.Allocator,
    total_count: std.atomic.Value(u64),
    sum: std.atomic.Value(u64),

    const Bucket = struct {
        upper_bound: u64,
        count: std.atomic.Value(u64),
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8, bounds: []const u64) !Histogram {
        var buckets = try allocator.alloc(Bucket, bounds.len);
        for (bounds, 0..) |bound, i| {
            buckets[i] = Bucket{
                .upper_bound = bound,
                .count = std.atomic.Value(u64).init(0),
            };
        }

        return Histogram{
            .name = name,
            .buckets = buckets,
            .allocator = allocator,
            .total_count = std.atomic.Value(u64).init(0),
            .sum = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Histogram) void {
        self.allocator.free(self.buckets);
    }

    pub fn observe(self: *Histogram, value: u64) void {
        _ = self.total_count.fetchAdd(1, .monotonic);
        _ = self.sum.fetchAdd(value, .monotonic);

        for (self.buckets) |*bucket| {
            if (value <= bucket.upper_bound) {
                _ = bucket.count.fetchAdd(1, .monotonic);
            }
        }
    }

    pub fn mean(self: *const Histogram) f64 {
        const count = self.total_count.load(.monotonic);
        if (count == 0) return 0.0;
        const total = self.sum.load(.monotonic);
        return @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(count));
    }
};

/// Comprehensive metrics collector for a logger
pub const MetricsCollector = struct {
    allocator: std.mem.Allocator,

    // Throughput metrics
    messages_logged: Metric,
    messages_per_level: std.AutoHashMap(zlog.Level, Metric),
    bytes_written: Metric,

    // Performance metrics
    log_latency_ns: Histogram,
    flush_latency_ns: Histogram,

    // Error metrics
    write_errors: Metric,
    format_errors: Metric,
    buffer_overflows: Metric,

    // Resource metrics
    buffer_allocations: Metric,
    memory_used: Metric,

    // Sampling metrics
    messages_sampled: Metric,
    messages_dropped: Metric,

    // Async metrics (when enabled)
    queue_depth: if (build_options.enable_async) Metric else void,
    queue_full_events: if (build_options.enable_async) Metric else void,

    // File metrics (when enabled)
    file_rotations: if (build_options.enable_file_targets) Metric else void,
    files_written: if (build_options.enable_file_targets) Metric else void,

    // Network metrics (when enabled)
    network_sends: if (build_options.enable_network_targets) Metric else void,
    network_failures: if (build_options.enable_network_targets) Metric else void,

    // Start time for uptime calculation
    start_time: i64,

    pub fn init(allocator: std.mem.Allocator) !MetricsCollector {
        var per_level = std.AutoHashMap(zlog.Level, Metric).init(allocator);
        try per_level.put(.debug, Metric.init("messages_debug", .counter, "Debug level messages"));
        try per_level.put(.info, Metric.init("messages_info", .counter, "Info level messages"));
        try per_level.put(.warn, Metric.init("messages_warn", .counter, "Warn level messages"));
        try per_level.put(.err, Metric.init("messages_error", .counter, "Error level messages"));
        try per_level.put(.fatal, Metric.init("messages_fatal", .counter, "Fatal level messages"));

        // Default latency buckets in nanoseconds: 1µs, 10µs, 100µs, 1ms, 10ms, 100ms, 1s
        const latency_buckets = [_]u64{ 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000, 1_000_000_000 };

        return MetricsCollector{
            .allocator = allocator,
            .messages_logged = Metric.init("messages_total", .counter, "Total messages logged"),
            .messages_per_level = per_level,
            .bytes_written = Metric.init("bytes_written", .counter, "Total bytes written"),
            .log_latency_ns = try Histogram.init(allocator, "log_latency_ns", &latency_buckets),
            .flush_latency_ns = try Histogram.init(allocator, "flush_latency_ns", &latency_buckets),
            .write_errors = Metric.init("write_errors", .counter, "Write operation errors"),
            .format_errors = Metric.init("format_errors", .counter, "Format operation errors"),
            .buffer_overflows = Metric.init("buffer_overflows", .counter, "Buffer overflow events"),
            .buffer_allocations = Metric.init("buffer_allocations", .counter, "Buffer allocations"),
            .memory_used = Metric.init("memory_bytes", .gauge, "Current memory usage"),
            .messages_sampled = Metric.init("messages_sampled", .counter, "Messages sampled"),
            .messages_dropped = Metric.init("messages_dropped", .counter, "Messages dropped due to sampling"),
            .queue_depth = if (build_options.enable_async) Metric.init("queue_depth", .gauge, "Async queue depth") else {},
            .queue_full_events = if (build_options.enable_async) Metric.init("queue_full", .counter, "Queue full events") else {},
            .file_rotations = if (build_options.enable_file_targets) Metric.init("file_rotations", .counter, "File rotation events") else {},
            .files_written = if (build_options.enable_file_targets) Metric.init("files_written", .counter, "Files written") else {},
            .network_sends = if (build_options.enable_network_targets) Metric.init("network_sends", .counter, "Network send operations") else {},
            .network_failures = if (build_options.enable_network_targets) Metric.init("network_failures", .counter, "Network send failures") else {},
            .start_time = getUnixTimestamp(),
        };
    }

    pub fn deinit(self: *MetricsCollector) void {
        self.messages_per_level.deinit();
        self.log_latency_ns.deinit();
        self.flush_latency_ns.deinit();
    }

    pub fn recordMessage(self: *MetricsCollector, level: zlog.Level, bytes: usize) void {
        self.messages_logged.increment();
        self.bytes_written.add(bytes);

        if (self.messages_per_level.getPtr(level)) |metric| {
            metric.increment();
        }
    }

    pub fn recordLogLatency(self: *MetricsCollector, latency_ns: u64) void {
        self.log_latency_ns.observe(latency_ns);
    }

    pub fn recordFlushLatency(self: *MetricsCollector, latency_ns: u64) void {
        self.flush_latency_ns.observe(latency_ns);
    }

    pub fn recordError(self: *MetricsCollector, error_type: ErrorType) void {
        switch (error_type) {
            .write => self.write_errors.increment(),
            .format => self.format_errors.increment(),
            .buffer_overflow => self.buffer_overflows.increment(),
        }
    }

    pub const ErrorType = enum {
        write,
        format,
        buffer_overflow,
    };

    pub fn recordSampling(self: *MetricsCollector, sampled: bool) void {
        if (sampled) {
            self.messages_sampled.increment();
        } else {
            self.messages_dropped.increment();
        }
    }

    pub fn setMemoryUsage(self: *MetricsCollector, bytes: u64) void {
        self.memory_used.set(bytes);
    }

    pub fn getUptime(self: *const MetricsCollector) i64 {
        return getUnixTimestamp() - self.start_time;
    }

    pub fn getThroughput(self: *const MetricsCollector) f64 {
        const uptime = self.getUptime();
        if (uptime <= 0) return 0.0;

        const total_messages = self.messages_logged.get();
        return @as(f64, @floatFromInt(total_messages)) / @as(f64, @floatFromInt(uptime));
    }

    pub fn getAverageMessageSize(self: *const MetricsCollector) f64 {
        const total_messages = self.messages_logged.get();
        if (total_messages == 0) return 0.0;

        const total_bytes = self.bytes_written.get();
        return @as(f64, @floatFromInt(total_bytes)) / @as(f64, @floatFromInt(total_messages));
    }

    pub fn printReport(self: *const MetricsCollector) void {
        std.debug.print("\n📊 zlog Performance Metrics\n", .{});
        std.debug.print("===========================\n", .{});

        // Uptime
        const uptime = self.getUptime();
        std.debug.print("Uptime: {d} seconds\n\n", .{uptime});

        // Throughput
        std.debug.print("Throughput:\n", .{});
        std.debug.print("  Total messages: {d}\n", .{self.messages_logged.get()});
        std.debug.print("  Messages/second: {d:.2}\n", .{self.getThroughput()});
        std.debug.print("  Total bytes: {d}\n", .{self.bytes_written.get()});
        std.debug.print("  Avg message size: {d:.2} bytes\n\n", .{self.getAverageMessageSize()});

        // Messages per level
        std.debug.print("Messages by level:\n", .{});
        inline for (@typeInfo(zlog.Level).@"enum".fields) |field| {
            const level: zlog.Level = @enumFromInt(field.value);
            if (self.messages_per_level.get(level)) |metric| {
                std.debug.print("  {s}: {d}\n", .{ level.toString(), metric.get() });
            }
        }
        std.debug.print("\n", .{});

        // Latency
        std.debug.print("Latency:\n", .{});
        std.debug.print("  Avg log latency: {d:.2} µs\n", .{self.log_latency_ns.mean() / 1000.0});
        std.debug.print("  Avg flush latency: {d:.2} µs\n\n", .{self.flush_latency_ns.mean() / 1000.0});

        // Errors
        const total_errors = self.write_errors.get() + self.format_errors.get() + self.buffer_overflows.get();
        std.debug.print("Errors:\n", .{});
        std.debug.print("  Total: {d}\n", .{total_errors});
        std.debug.print("  Write errors: {d}\n", .{self.write_errors.get()});
        std.debug.print("  Format errors: {d}\n", .{self.format_errors.get()});
        std.debug.print("  Buffer overflows: {d}\n\n", .{self.buffer_overflows.get()});

        // Sampling
        const total_attempts = self.messages_sampled.get() + self.messages_dropped.get();
        if (total_attempts > 0) {
            const sample_rate = @as(f64, @floatFromInt(self.messages_sampled.get())) /
                @as(f64, @floatFromInt(total_attempts)) * 100.0;
            std.debug.print("Sampling:\n", .{});
            std.debug.print("  Sampled: {d}\n", .{self.messages_sampled.get()});
            std.debug.print("  Dropped: {d}\n", .{self.messages_dropped.get()});
            std.debug.print("  Rate: {d:.2}%\n\n", .{sample_rate});
        }

        // Resource usage
        std.debug.print("Resources:\n", .{});
        std.debug.print("  Memory used: {d} bytes\n", .{self.memory_used.get()});
        std.debug.print("  Buffer allocations: {d}\n\n", .{self.buffer_allocations.get()});

        // Async metrics
        if (build_options.enable_async) {
            std.debug.print("Async I/O:\n", .{});
            std.debug.print("  Queue depth: {d}\n", .{self.queue_depth.get()});
            std.debug.print("  Queue full events: {d}\n\n", .{self.queue_full_events.get()});
        }

        // File metrics
        if (build_options.enable_file_targets) {
            std.debug.print("File Operations:\n", .{});
            std.debug.print("  Files written: {d}\n", .{self.files_written.get()});
            std.debug.print("  Rotations: {d}\n\n", .{self.file_rotations.get()});
        }

        // Network metrics
        if (build_options.enable_network_targets) {
            std.debug.print("Network Operations:\n", .{});
            std.debug.print("  Sends: {d}\n", .{self.network_sends.get()});
            std.debug.print("  Failures: {d}\n", .{self.network_failures.get()});
            if (self.network_sends.get() > 0) {
                const success_rate = (@as(f64, @floatFromInt(self.network_sends.get() - self.network_failures.get())) /
                    @as(f64, @floatFromInt(self.network_sends.get()))) * 100.0;
                std.debug.print("  Success rate: {d:.2}%\n", .{success_rate});
            }
        }
    }

    /// Export metrics in Prometheus format
    pub fn exportPrometheus(self: *const MetricsCollector, writer: anytype) !void {
        try writer.print("# HELP zlog_messages_total Total messages logged\n", .{});
        try writer.print("# TYPE zlog_messages_total counter\n", .{});
        try writer.print("zlog_messages_total {d}\n\n", .{self.messages_logged.get()});

        try writer.print("# HELP zlog_bytes_written Total bytes written\n", .{});
        try writer.print("# TYPE zlog_bytes_written counter\n", .{});
        try writer.print("zlog_bytes_written {d}\n\n", .{self.bytes_written.get()});

        try writer.print("# HELP zlog_messages_by_level Messages logged by level\n", .{});
        try writer.print("# TYPE zlog_messages_by_level counter\n", .{});
        inline for (@typeInfo(zlog.Level).@"enum".fields) |field| {
            const level: zlog.Level = @enumFromInt(field.value);
            if (self.messages_per_level.get(level)) |metric| {
                try writer.print("zlog_messages_by_level{{level=\"{s}\"}} {d}\n", .{ level.toString(), metric.get() });
            }
        }
        try writer.print("\n", .{});

        try writer.print("# HELP zlog_log_latency_mean Average log latency in nanoseconds\n", .{});
        try writer.print("# TYPE zlog_log_latency_mean gauge\n", .{});
        try writer.print("zlog_log_latency_mean {d:.0}\n\n", .{self.log_latency_ns.mean()});

        try writer.print("# HELP zlog_throughput Messages per second\n", .{});
        try writer.print("# TYPE zlog_throughput gauge\n", .{});
        try writer.print("zlog_throughput {d:.2}\n\n", .{self.getThroughput()});
    }
};

/// Health check status
pub const HealthStatus = enum {
    healthy,
    degraded,
    unhealthy,
};

/// Health check result
pub const HealthCheck = struct {
    status: HealthStatus,
    uptime_seconds: i64,
    total_messages: u64,
    error_rate: f64,
    throughput: f64,
    checks: std.ArrayList(Check),

    const Check = struct {
        name: []const u8,
        status: HealthStatus,
        message: []const u8,
    };

    pub fn fromMetrics(allocator: std.mem.Allocator, metrics: *const MetricsCollector) !HealthCheck {
        var checks = std.ArrayList(Check).init(allocator);

        const uptime = metrics.getUptime();
        const total_messages = metrics.messages_logged.get();
        const total_errors = metrics.write_errors.get() + metrics.format_errors.get();
        const error_rate = if (total_messages > 0)
            (@as(f64, @floatFromInt(total_errors)) / @as(f64, @floatFromInt(total_messages))) * 100.0
        else
            0.0;
        const throughput = metrics.getThroughput();

        // Check error rate
        const error_status: HealthStatus = if (error_rate > 10.0)
            .unhealthy
        else if (error_rate > 1.0)
            .degraded
        else
            .healthy;

        try checks.append(.{
            .name = "error_rate",
            .status = error_status,
            .message = try std.fmt.allocPrint(allocator, "Error rate: {d:.2}%", .{error_rate}),
        });

        // Check throughput (should be > 0 if healthy)
        const throughput_status: HealthStatus = if (uptime > 10 and throughput < 0.1)
            .degraded
        else
            .healthy;

        try checks.append(.{
            .name = "throughput",
            .status = throughput_status,
            .message = try std.fmt.allocPrint(allocator, "Throughput: {d:.2} msg/s", .{throughput}),
        });

        // Determine overall status
        var overall_status = HealthStatus.healthy;
        for (checks.items) |check| {
            if (check.status == .unhealthy) {
                overall_status = .unhealthy;
                break;
            } else if (check.status == .degraded and overall_status == .healthy) {
                overall_status = .degraded;
            }
        }

        return HealthCheck{
            .status = overall_status,
            .uptime_seconds = uptime,
            .total_messages = total_messages,
            .error_rate = error_rate,
            .throughput = throughput,
            .checks = checks,
        };
    }

    pub fn deinit(self: *HealthCheck) void {
        for (self.checks.items) |check| {
            self.checks.allocator.free(check.message);
        }
        self.checks.deinit();
    }

    pub fn print(self: HealthCheck) void {
        const status_icon = switch (self.status) {
            .healthy => "✅",
            .degraded => "⚠️",
            .unhealthy => "❌",
        };

        std.debug.print("\n{s} Health Status: {s}\n", .{ status_icon, @tagName(self.status) });
        std.debug.print("====================\n", .{});
        std.debug.print("Uptime: {d} seconds\n", .{self.uptime_seconds});
        std.debug.print("Total messages: {d}\n", .{self.total_messages});
        std.debug.print("Error rate: {d:.2}%\n", .{self.error_rate});
        std.debug.print("Throughput: {d:.2} msg/s\n\n", .{self.throughput});

        std.debug.print("Individual Checks:\n", .{});
        for (self.checks.items) |check| {
            const check_icon = switch (check.status) {
                .healthy => "✅",
                .degraded => "⚠️",
                .unhealthy => "❌",
            };
            std.debug.print("  {s} {s}: {s}\n", .{ check_icon, check.name, check.message });
        }
    }

    /// Export health check in JSON format
    pub fn toJson(self: HealthCheck, writer: anytype) !void {
        try writer.print("{{\"status\":\"{s}\",", .{@tagName(self.status)});
        try writer.print("\"uptime\":{d},", .{self.uptime_seconds});
        try writer.print("\"total_messages\":{d},", .{self.total_messages});
        try writer.print("\"error_rate\":{d:.2},", .{self.error_rate});
        try writer.print("\"throughput\":{d:.2},", .{self.throughput});
        try writer.print("\"checks\":[", .{});

        for (self.checks.items, 0..) |check, i| {
            if (i > 0) try writer.print(",", .{});
            try writer.print("{{\"name\":\"{s}\",\"status\":\"{s}\",\"message\":\"{s}\"}}", .{
                check.name,
                @tagName(check.status),
                check.message,
            });
        }

        try writer.print("]}}", .{});
    }
};

// Tests
const testing = std.testing;

test "metrics: metric operations" {
    var metric = Metric.init("test", .counter, "Test metric");

    metric.increment();
    try testing.expect(metric.get() == 1);

    metric.add(5);
    try testing.expect(metric.get() == 6);

    metric.set(10);
    try testing.expect(metric.get() == 10);
}

test "metrics: histogram" {
    const buckets = [_]u64{ 10, 20, 30, 40, 50 };
    var hist = try Histogram.init(testing.allocator, "test_hist", &buckets);
    defer hist.deinit();

    hist.observe(5);
    hist.observe(15);
    hist.observe(25);
    hist.observe(35);

    try testing.expect(hist.total_count.load(.monotonic) == 4);
    try testing.expect(hist.mean() == 20.0);
}

test "metrics: collector" {
    var collector = try MetricsCollector.init(testing.allocator);
    defer collector.deinit();

    collector.recordMessage(.info, 100);
    collector.recordMessage(.warn, 150);

    try testing.expect(collector.messages_logged.get() == 2);
    try testing.expect(collector.bytes_written.get() == 250);
}
