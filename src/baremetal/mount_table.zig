// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const max_mounts: usize = 16;
pub const max_name_len: usize = 32;
pub const max_target_len: usize = 224;
pub const mount_root = "/mnt";

pub const Error = error{
    InvalidMountName,
    InvalidTarget,
    NoSpace,
};

pub const Entry = struct {
    name_len: u8 = 0,
    target_len: u16 = 0,
    modified_tick: u64 = 0,
    name: [max_name_len]u8 = std.mem.zeroes([max_name_len]u8),
    target: [max_target_len]u8 = std.mem.zeroes([max_target_len]u8),
};

var entries: [max_mounts]Entry = std.mem.zeroes([max_mounts]Entry);

pub fn resetForTest() void {
    @memset(&entries, std.mem.zeroes(Entry));
}

pub fn clear() void {
    resetForTest();
}

pub fn hasEntries() bool {
    return count() != 0;
}

pub fn count() usize {
    var total: usize = 0;
    for (entries) |entry_value| {
        if (entry_value.name_len != 0) total += 1;
    }
    return total;
}

pub fn entry(index: usize) ?Entry {
    if (index >= max_mounts) return null;
    const value = entries[index];
    if (value.name_len == 0) return null;
    return value;
}

pub fn validateName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > max_name_len) return error.InvalidMountName;
    for (name) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_') continue;
        return error.InvalidMountName;
    }
}

pub fn validateTarget(target: []const u8) Error!void {
    if (target.len == 0 or target.len > max_target_len) return error.InvalidTarget;
    if (target[0] != '/') return error.InvalidTarget;
    if (std.mem.eql(u8, target, mount_root)) return error.InvalidTarget;
    if (std.mem.startsWith(u8, target, mount_root) and (target.len == mount_root.len or target[mount_root.len] == '/')) {
        return error.InvalidTarget;
    }
}

pub fn set(name: []const u8, target: []const u8, tick: u64) Error!void {
    try validateName(name);
    try validateTarget(target);

    const existing = findIndex(name);
    const index = existing orelse findFreeIndex() orelse return error.NoSpace;
    entries[index] = .{
        .name_len = @as(u8, @intCast(name.len)),
        .target_len = @as(u16, @intCast(target.len)),
        .modified_tick = tick,
    };
    @memcpy(entries[index].name[0..name.len], name);
    @memcpy(entries[index].target[0..target.len], target);
}

pub fn remove(name: []const u8) bool {
    const index = findIndex(name) orelse return false;
    entries[index] = std.mem.zeroes(Entry);
    return true;
}

pub fn targetForName(name: []const u8) ?[]const u8 {
    const index = findIndex(name) orelse return null;
    const value = &entries[index];
    return value.target[0..value.target_len];
}

pub fn resolve(path: []const u8, out: []u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, mount_root)) return null;
    if (path.len == mount_root.len) return null;
    if (path[mount_root.len] != '/') return null;

    const tail = path[mount_root.len + 1 ..];
    if (tail.len == 0) return null;

    const slash_index = std.mem.indexOfScalar(u8, tail, '/');
    const mount_name = if (slash_index) |value| tail[0..value] else tail;
    const target = targetForName(mount_name) orelse return null;

    const remainder = if (slash_index) |value| tail[value..] else "";
    if (target.len + remainder.len > out.len) return null;
    @memcpy(out[0..target.len], target);
    @memcpy(out[target.len .. target.len + remainder.len], remainder);
    return out[0 .. target.len + remainder.len];
}

fn findIndex(name: []const u8) ?usize {
    for (entries, 0..) |entry_value, index| {
        if (entry_value.name_len != name.len) continue;
        if (std.mem.eql(u8, entry_value.name[0..entry_value.name_len], name)) return index;
    }
    return null;
}

fn findFreeIndex() ?usize {
    for (entries, 0..) |entry_value, index| {
        if (entry_value.name_len == 0) return index;
    }
    return null;
}

test "mount table stores, resolves, and removes aliases" {
    resetForTest();

    try set("boot", "/boot", 1);
    try set("runtime", "/runtime", 2);

    try std.testing.expectEqual(@as(usize, 2), count());
    try std.testing.expectEqualStrings("/boot", targetForName("boot").?);
    try std.testing.expectEqualStrings("/runtime", targetForName("runtime").?);

    var resolved_buf: [max_target_len]u8 = undefined;
    const loader = resolve("/mnt/boot/loader.cfg", resolved_buf[0..]).?;
    try std.testing.expectEqualStrings("/boot/loader.cfg", loader);

    try std.testing.expect(remove("boot"));
    try std.testing.expectEqual(@as(usize, 1), count());
    try std.testing.expect(targetForName("boot") == null);
}

test "mount table rejects invalid names and recursive targets" {
    resetForTest();

    try std.testing.expectError(error.InvalidMountName, set("bad/name", "/boot", 1));
    try std.testing.expectError(error.InvalidMountName, set(".", "/boot", 1));
    try std.testing.expectError(error.InvalidTarget, set("boot", "boot", 1));
    try std.testing.expectError(error.InvalidTarget, set("boot", "/mnt/runtime", 1));
}
