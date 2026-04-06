// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const time_util = @import("../util/time.zig");

pub fn stringifyJsonValue(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return out.toOwnedSlice();
}

pub fn stringifyParamsObject(allocator: std.mem.Allocator, params: ?std.json.ObjectMap) ![]u8 {
    if (params) |obj| {
        return stringifyJsonValue(allocator, .{ .object = obj });
    }
    return allocator.dupe(u8, "{}");
}

pub fn mintCanvasCapabilityToken(allocator: std.mem.Allocator) ![]u8 {
    const now: u64 = @intCast(@max(time_util.nowMs(), 0));
    var raw: [8]u8 = undefined;
    std.mem.writeInt(u64, &raw, now, .little);
    var hasher = std.hash.Wyhash.init(0xA11CE);
    hasher.update(&raw);
    const mixed = hasher.final();
    return std.fmt.allocPrint(allocator, "cap-{x}-{x}", .{ now, mixed });
}

pub fn buildScopedCanvasHostUrl(
    allocator: std.mem.Allocator,
    base_url: []const u8,
    capability: []const u8,
) ![]u8 {
    var trimmed = std.mem.trim(u8, base_url, " \t\r\n");
    while (trimmed.len > 0 and trimmed[trimmed.len - 1] == '/') {
        trimmed = trimmed[0 .. trimmed.len - 1];
    }
    return std.fmt.allocPrint(allocator, "{s}/__openclaw__/cap/{s}", .{ trimmed, capability });
}
