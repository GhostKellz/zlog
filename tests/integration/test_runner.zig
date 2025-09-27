// Integration test runner - imports all integration test files

const std = @import("std");

// Import all integration test files
test {
    _ = @import("file_rotation_test.zig");
    _ = @import("async_io_test.zig");
}

// Test runner main function
pub fn main() !void {
    std.debug.print("Running zlog integration tests...\n", .{});
}