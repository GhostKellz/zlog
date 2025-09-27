// Compile-time feature detection and capability reporting for zlog
// Provides runtime introspection of enabled features and capabilities

const std = @import("std");
const build_options = @import("build_options");

// Feature flags enumeration
pub const Feature = enum {
    json_format,
    async_io,
    file_targets,
    binary_format,
    aggregation,
    network_targets,
    metrics,

    pub fn isEnabled(self: Feature) bool {
        return switch (self) {
            .json_format => build_options.enable_json,
            .async_io => build_options.enable_async,
            .file_targets => build_options.enable_file_targets,
            .binary_format => build_options.enable_binary_format,
            .aggregation => build_options.enable_aggregation,
            .network_targets => build_options.enable_network_targets,
            .metrics => build_options.enable_metrics,
        };
    }

    pub fn description(self: Feature) []const u8 {
        return switch (self) {
            .json_format => "JSON output format support",
            .async_io => "Asynchronous I/O with background threads",
            .file_targets => "File output with rotation and backup",
            .binary_format => "Compact binary format for high performance",
            .aggregation => "Log batching, deduplication, and sampling",
            .network_targets => "Network output targets (TCP/UDP/HTTP)",
            .metrics => "Performance metrics and monitoring",
        };
    }

    pub fn dependsOn(self: Feature) []const Feature {
        return switch (self) {
            .network_targets => &[_]Feature{.async_io},
            .metrics => &[_]Feature{.aggregation},
            else => &[_]Feature{},
        };
    }

    pub fn conflicts(self: Feature) []const Feature {
        // Currently no conflicts, but framework for future use
        _ = self;
        return &[_]Feature{};
    }
};

// Feature capability reporting
pub const Capabilities = struct {
    // Core capabilities (always available)
    pub const has_text_format = true;
    pub const has_stdout_output = true;
    pub const has_stderr_output = true;
    pub const has_basic_levels = true;
    pub const has_structured_logging = true;
    pub const has_thread_safety = true;

    // Optional capabilities (build-dependent)
    pub const has_json_format = build_options.enable_json;
    pub const has_async_io = build_options.enable_async;
    pub const has_file_targets = build_options.enable_file_targets;
    pub const has_binary_format = build_options.enable_binary_format;
    pub const has_aggregation = build_options.enable_aggregation;
    pub const has_network_targets = build_options.enable_network_targets;
    pub const has_metrics = build_options.enable_metrics;

    // Derived capabilities
    pub const has_file_rotation = has_file_targets;
    pub const has_log_sampling = has_aggregation;
    pub const has_batching = has_aggregation;
    pub const has_deduplication = has_aggregation;

    // Performance characteristics
    pub const supports_high_throughput = has_binary_format or has_async_io;
    pub const supports_low_latency = !has_async_io; // Sync I/O for immediate output
    pub const supports_minimal_footprint = !has_async_io and !has_aggregation;

    pub fn printSummary() void {
        std.debug.print("\n🚀 zlog Feature Summary\n");
        std.debug.print("=======================\n");

        std.debug.print("\n✅ Core Features (Always Available):\n");
        std.debug.print("   • Text format output\n");
        std.debug.print("   • Console output (stdout/stderr)\n");
        std.debug.print("   • All log levels (debug, info, warn, err, fatal)\n");
        std.debug.print("   • Structured logging with type-safe fields\n");
        std.debug.print("   • Thread-safe concurrent logging\n");
        std.debug.print("   • Configurable buffer sizes\n");

        std.debug.print("\n🔧 Optional Features:\n");
        printFeatureStatus(.json_format);
        printFeatureStatus(.async_io);
        printFeatureStatus(.file_targets);
        printFeatureStatus(.binary_format);
        printFeatureStatus(.aggregation);
        printFeatureStatus(.network_targets);
        printFeatureStatus(.metrics);

        std.debug.print("\n⚡ Performance Characteristics:\n");
        std.debug.print("   • High throughput: {s}\n", .{if (supports_high_throughput) "✅ Available" else "❌ Limited"});
        std.debug.print("   • Low latency: {s}\n", .{if (supports_low_latency) "✅ Available" else "❌ Async only"});
        std.debug.print("   • Minimal footprint: {s}\n", .{if (supports_minimal_footprint) "✅ Available" else "❌ Has overhead"});

        printBuildSize();
    }

    fn printFeatureStatus(feature: Feature) void {
        const status = if (feature.isEnabled()) "✅" else "❌";
        std.debug.print("   {s} {s}: {s}\n", .{ status, @tagName(feature), feature.description() });
    }

    fn printBuildSize() void {
        std.debug.print("\n📦 Estimated Build Characteristics:\n");

        var feature_count: u8 = 0;
        var estimated_size: u32 = 25; // Base size in KB

        inline for (@typeInfo(Feature).Enum.fields) |field| {
            const feature = @field(Feature, field.name);
            if (feature.isEnabled()) {
                feature_count += 1;
                estimated_size += switch (feature) {
                    .json_format => 8,
                    .async_io => 12,
                    .file_targets => 15,
                    .binary_format => 5,
                    .aggregation => 18,
                    .network_targets => 25,
                    .metrics => 10,
                };
            }
        }

        std.debug.print("   • Enabled features: {d}/7\n", .{feature_count});
        std.debug.print("   • Estimated binary size: ~{d}KB\n", .{estimated_size});

        if (feature_count <= 2) {
            std.debug.print("   • Build profile: Minimal 🟢\n");
        } else if (feature_count <= 4) {
            std.debug.print("   • Build profile: Balanced 🟡\n");
        } else {
            std.debug.print("   • Build profile: Full-featured 🔴\n");
        }
    }
};

// Runtime feature checking
pub const FeatureChecker = struct {
    pub fn checkFeature(feature: Feature) bool {
        return feature.isEnabled();
    }

    pub fn requireFeature(feature: Feature) !void {
        if (!feature.isEnabled()) {
            std.debug.print("❌ Required feature '{s}' is not enabled\n", .{@tagName(feature)});
            return error.FeatureNotEnabled;
        }
    }

    pub fn validateDependencies(feature: Feature) !void {
        if (!feature.isEnabled()) return;

        for (feature.dependsOn()) |dep| {
            if (!dep.isEnabled()) {
                std.debug.print("❌ Feature '{s}' requires '{s}' but it's not enabled\n", .{ @tagName(feature), @tagName(dep) });
                return error.DependencyNotMet;
            }
        }
    }

    pub fn checkConflicts(feature: Feature) !void {
        if (!feature.isEnabled()) return;

        for (feature.conflicts()) |conflict| {
            if (conflict.isEnabled()) {
                std.debug.print("❌ Feature '{s}' conflicts with '{s}'\n", .{ @tagName(feature), @tagName(conflict) });
                return error.FeatureConflict;
            }
        }
    }

    pub fn validateAllFeatures() !void {
        inline for (@typeInfo(Feature).Enum.fields) |field| {
            const feature = @field(Feature, field.name);
            try validateDependencies(feature);
            try checkConflicts(feature);
        }
    }
};

// Feature configuration recommendations
pub const Recommendations = struct {
    pub const UseCase = enum {
        embedded,
        desktop_app,
        web_service,
        high_performance,
        development,
        production,
    };

    pub fn forUseCase(use_case: UseCase) []const Feature {
        return switch (use_case) {
            .embedded => &[_]Feature{},
            .desktop_app => &[_]Feature{ .json_format, .file_targets },
            .web_service => &[_]Feature{ .json_format, .async_io, .file_targets, .aggregation },
            .high_performance => &[_]Feature{ .binary_format, .async_io, .aggregation },
            .development => &[_]Feature{ .json_format, .file_targets },
            .production => &[_]Feature{ .json_format, .async_io, .file_targets, .aggregation, .metrics },
        };
    }

    pub fn printRecommendations(use_case: UseCase) void {
        const recommended = forUseCase(use_case);

        std.debug.print("\n💡 Recommendations for {s}:\n", .{@tagName(use_case)});
        std.debug.print("=================================\n");

        if (recommended.len == 0) {
            std.debug.print("   • Minimal build (text format only)\n");
            std.debug.print("   • Perfect for resource-constrained environments\n");
        } else {
            std.debug.print("   Recommended features:\n");
            for (recommended) |feature| {
                const status = if (feature.isEnabled()) "✅ Enabled" else "❌ Disabled";
                std.debug.print("   • {s}: {s}\n", .{ @tagName(feature), status });
            }
        }

        // Check current configuration against recommendations
        var matches: u8 = 0;
        for (recommended) |feature| {
            if (feature.isEnabled()) matches += 1;
        }

        const match_percentage = if (recommended.len > 0)
            (matches * 100) / @as(u8, @intCast(recommended.len))
        else
            100;

        std.debug.print("\n   Current configuration matches: {d}%\n", .{match_percentage});

        if (match_percentage < 100) {
            std.debug.print("\n   🔧 To optimize for {s}, consider:\n", .{@tagName(use_case)});
            for (recommended) |feature| {
                if (!feature.isEnabled()) {
                    std.debug.print("   • Enable -{s}\n", .{@tagName(feature)});
                }
            }
        }
    }
};

// Compile-time feature assertions
pub fn compileTimeChecks() void {
    // Ensure critical dependencies
    if (build_options.enable_network_targets and !build_options.enable_async) {
        @compileError("Network targets require async I/O to be enabled");
    }

    if (build_options.enable_metrics and !build_options.enable_aggregation) {
        @compileError("Metrics require aggregation features to be enabled");
    }

    // Warn about suboptimal configurations
    if (build_options.enable_async and !build_options.enable_aggregation) {
        @compileLog("Warning: Async I/O without aggregation may not provide optimal performance");
    }
}

// Build information
pub const BuildInfo = struct {
    pub const zig_version = @import("builtin").zig_version_string;
    pub const build_mode = @import("builtin").mode;
    pub const target_os = @import("builtin").target.os.tag;
    pub const target_arch = @import("builtin").target.cpu.arch;

    pub fn print() void {
        std.debug.print("\n🔨 Build Information\n");
        std.debug.print("===================\n");
        std.debug.print("   • Zig version: {s}\n", .{zig_version});
        std.debug.print("   • Build mode: {s}\n", .{@tagName(build_mode)});
        std.debug.print("   • Target OS: {s}\n", .{@tagName(target_os)});
        std.debug.print("   • Target arch: {s}\n", .{@tagName(target_arch)});

        // Feature summary
        var enabled_count: u8 = 0;
        inline for (@typeInfo(Feature).Enum.fields) |field| {
            const feature = @field(Feature, field.name);
            if (feature.isEnabled()) enabled_count += 1;
        }

        std.debug.print("   • Features enabled: {d}/7\n", .{enabled_count});
    }
};

// Complete feature report
pub fn printFeatureReport() void {
    BuildInfo.print();
    Capabilities.printSummary();

    std.debug.print("\n📋 Feature Details\n");
    std.debug.print("==================\n");
    inline for (@typeInfo(Feature).Enum.fields) |field| {
        const feature = @field(Feature, field.name);
        const status = if (feature.isEnabled()) "✅" else "❌";
        std.debug.print("{s} {s}\n", .{ status, feature.description() });

        if (feature.isEnabled() and feature.dependsOn().len > 0) {
            std.debug.print("    Dependencies: ");
            for (feature.dependsOn()) |dep| {
                std.debug.print("{s} ", .{@tagName(dep)});
            }
            std.debug.print("\n");
        }
    }
}

// Test feature detection
const testing = std.testing;

test "features: basic detection" {
    // These should always be true
    try testing.expect(Capabilities.has_text_format);
    try testing.expect(Capabilities.has_stdout_output);
    try testing.expect(Capabilities.has_structured_logging);
}

test "features: feature checking" {
    const json_enabled = FeatureChecker.checkFeature(.json_format);
    try testing.expect(json_enabled == build_options.enable_json);
}

test "features: validation" {
    // This should not fail if dependencies are correct
    try FeatureChecker.validateAllFeatures();
}

test "features: recommendations" {
    const embedded_features = Recommendations.forUseCase(.embedded);
    try testing.expect(embedded_features.len == 0); // Minimal for embedded

    const production_features = Recommendations.forUseCase(.production);
    try testing.expect(production_features.len > 0); // Should have recommendations
}