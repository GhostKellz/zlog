// Unit test runner - imports all unit test files

const std = @import("std");

// Import all unit test files
test {
    _ = @import("logger_test.zig");
    _ = @import("format_test.zig");
    _ = @import("property_test.zig");
    _ = @import("error_test.zig");
    _ = @import("memory_test.zig");
}

// Test runner main function
pub fn main() !void {
    std.debug.print("Running zlog unit tests...\n", .{});
}