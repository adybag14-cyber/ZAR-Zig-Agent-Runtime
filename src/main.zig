const std = @import("std");

pub fn main() !void {
    std.debug.print("openclaw-zig bootstrap ready\n", .{});
}

test "bootstrap string is non-empty" {
    const value = "openclaw-zig bootstrap ready";
    try std.testing.expect(value.len > 0);
}
