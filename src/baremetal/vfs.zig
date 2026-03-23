// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const mount_table = @import("mount_table.zig");
const mounted_external_fs = @import("mounted_external_fs.zig");
const tmpfs = @import("tmpfs.zig");
const virtual_fs = @import("virtual_fs.zig");

pub const SimpleStat = struct {
    kind: std.Io.File.Kind,
    size: u64,
    checksum: u32,
    modified_tick: u64,
    entry_id: u64,
};

pub const RouteKind = enum {
    persistent,
    tmpfs,
    virtual,
    external,
    mount_root,
};

pub const Route = struct {
    kind: RouteKind,
    full: []const u8,
};

pub fn route(path: []const u8, normalized_buf: []u8, resolved_buf: []u8) !Route {
    const normalized = try normalizePath(path, normalized_buf);
    if (std.mem.eql(u8, normalized, mount_table.mount_root)) {
        return .{ .kind = .mount_root, .full = mount_table.mount_root };
    }

    const full = if (mount_table.resolve(normalized, resolved_buf)) |aliased|
        aliased
    else blk: {
        if (isMountPath(normalized)) return error.FileNotFound;
        break :blk normalized;
    };

    if (tmpfs.handles(full)) return .{ .kind = .tmpfs, .full = full };
    if (virtual_fs.handles(full)) return .{ .kind = .virtual, .full = full };
    if (mounted_external_fs.handles(full)) return .{ .kind = .external, .full = full };
    return .{ .kind = .persistent, .full = full };
}

pub fn createDirPath(persistent: anytype, path: []const u8, normalized_buf: []u8, resolved_buf: []u8) !void {
    const routed = try route(path, normalized_buf, resolved_buf);
    switch (routed.kind) {
        .mount_root => return error.ReadOnlyPath,
        .tmpfs => return tmpfs.createDirPath(routed.full) catch |err| switch (err) {
            error.InvalidPath => error.InvalidPath,
            error.NotDirectory => error.NotDirectory,
            error.NoSpace => error.NoSpace,
            else => error.InvalidPath,
        },
        .virtual => return error.ReadOnlyPath,
        .external => return error.ReadOnlyPath,
        .persistent => return persistent.createDirPath(routed.full),
    }
}

pub fn writeFile(persistent: anytype, path: []const u8, data: []const u8, tick: u64, normalized_buf: []u8, resolved_buf: []u8) !void {
    const routed = try route(path, normalized_buf, resolved_buf);
    switch (routed.kind) {
        .mount_root => return error.ReadOnlyPath,
        .tmpfs => return tmpfs.writeFile(routed.full, data, tick) catch |err| switch (err) {
            error.InvalidPath => error.InvalidPath,
            error.FileNotFound => error.FileNotFound,
            error.NotDirectory => error.NotDirectory,
            error.IsDirectory => error.IsDirectory,
            error.NoSpace => error.NoSpace,
            else => error.InvalidPath,
        },
        .virtual => return error.ReadOnlyPath,
        .external => return error.ReadOnlyPath,
        .persistent => return persistent.writeFile(routed.full, data, tick),
    }
}

pub fn deleteFile(persistent: anytype, path: []const u8, tick: u64, normalized_buf: []u8, resolved_buf: []u8) !void {
    const routed = try route(path, normalized_buf, resolved_buf);
    switch (routed.kind) {
        .mount_root => return error.ReadOnlyPath,
        .tmpfs => return tmpfs.deleteFile(routed.full) catch |err| switch (err) {
            error.InvalidPath => error.InvalidPath,
            error.FileNotFound => error.FileNotFound,
            error.IsDirectory => error.IsDirectory,
            else => error.InvalidPath,
        },
        .virtual => return error.ReadOnlyPath,
        .external => return error.ReadOnlyPath,
        .persistent => return persistent.deleteFile(routed.full, tick),
    }
}

pub fn deleteTree(persistent: anytype, path: []const u8, tick: u64, normalized_buf: []u8, resolved_buf: []u8) !void {
    const routed = try route(path, normalized_buf, resolved_buf);
    switch (routed.kind) {
        .mount_root => return error.ReadOnlyPath,
        .tmpfs => return tmpfs.deleteTree(routed.full) catch |err| switch (err) {
            error.InvalidPath => error.InvalidPath,
            error.FileNotFound => error.FileNotFound,
            else => error.InvalidPath,
        },
        .virtual => return error.ReadOnlyPath,
        .external => return error.ReadOnlyPath,
        .persistent => return persistent.deleteTree(routed.full, tick),
    }
}

pub fn readFileAlloc(persistent: anytype, allocator: std.mem.Allocator, path: []const u8, max_bytes: usize, normalized_buf: []u8, resolved_buf: []u8) ![]u8 {
    const routed = try route(path, normalized_buf, resolved_buf);
    switch (routed.kind) {
        .mount_root => return error.IsDirectory,
        .tmpfs => return tmpfs.readFileAlloc(allocator, routed.full, max_bytes) catch |err| switch (err) {
            error.InvalidPath => error.InvalidPath,
            error.FileNotFound => error.FileNotFound,
            error.FileTooBig => error.FileTooBig,
            error.IsDirectory => error.IsDirectory,
            else => error.InvalidPath,
        },
        .virtual => return virtual_fs.readFileAlloc(allocator, routed.full, max_bytes),
        .external => return mounted_external_fs.readFileAlloc(allocator, routed.full, max_bytes),
        .persistent => return persistent.readFileAlloc(allocator, routed.full, max_bytes),
    }
}

pub fn readFile(persistent: anytype, path: []const u8, buffer: []u8, normalized_buf: []u8, resolved_buf: []u8) ![]const u8 {
    const routed = try route(path, normalized_buf, resolved_buf);
    switch (routed.kind) {
        .mount_root => return error.IsDirectory,
        .tmpfs => return tmpfs.readFile(routed.full, buffer) catch |err| switch (err) {
            error.InvalidPath => error.InvalidPath,
            error.FileNotFound => error.FileNotFound,
            error.FileTooBig => error.FileTooBig,
            error.IsDirectory => error.IsDirectory,
            else => error.InvalidPath,
        },
        .virtual => return virtual_fs.readFile(routed.full, buffer),
        .external => return mounted_external_fs.readFile(routed.full, buffer),
        .persistent => return persistent.readFile(routed.full, buffer),
    }
}

pub fn listDirectoryAlloc(persistent: anytype, allocator: std.mem.Allocator, path: []const u8, max_bytes: usize, normalized_buf: []u8, resolved_buf: []u8) ![]u8 {
    const routed = try route(path, normalized_buf, resolved_buf);
    switch (routed.kind) {
        .mount_root => return listMountDirectoryAlloc(allocator, max_bytes),
        .tmpfs => return tmpfs.listDirectoryAlloc(allocator, routed.full, max_bytes) catch |err| switch (err) {
            error.InvalidPath => error.InvalidPath,
            error.FileNotFound => error.FileNotFound,
            error.NotDirectory => error.NotDirectory,
            error.ResponseTooLarge => error.ResponseTooLarge,
            else => error.InvalidPath,
        },
        .virtual => return virtual_fs.listDirectoryAlloc(allocator, routed.full, max_bytes),
        .external => return mounted_external_fs.listDirectoryAlloc(allocator, routed.full, max_bytes),
        .persistent => {
            if (std.mem.eql(u8, routed.full, "/")) return persistent.listRootDirectoryAlloc(allocator, max_bytes);
            return persistent.listDirectoryAlloc(allocator, routed.full, max_bytes);
        },
    }
}

pub fn statSummary(persistent: anytype, path: []const u8, normalized_buf: []u8, resolved_buf: []u8) !SimpleStat {
    const routed = try route(path, normalized_buf, resolved_buf);
    if (@hasDecl(@TypeOf(persistent), "beforeStat")) persistent.beforeStat();
    switch (routed.kind) {
        .mount_root => return .{
            .kind = .directory,
            .size = 0,
            .checksum = 0,
            .modified_tick = 0,
            .entry_id = 0,
        },
        .tmpfs => {
            const summary = try tmpfs.statSummary(routed.full);
            return .{
                .kind = summary.kind,
                .size = summary.size,
                .checksum = summary.checksum,
                .modified_tick = summary.modified_tick,
                .entry_id = summary.entry_id,
            };
        },
        .virtual => {
            const summary = try virtual_fs.statSummary(routed.full);
            return .{
                .kind = summary.kind,
                .size = summary.size,
                .checksum = summary.checksum,
                .modified_tick = summary.modified_tick,
                .entry_id = summary.entry_id,
            };
        },
        .external => {
            const summary = try mounted_external_fs.statSummary(routed.full);
            return .{
                .kind = summary.kind,
                .size = summary.size,
                .checksum = summary.checksum,
                .modified_tick = summary.modified_tick,
                .entry_id = summary.entry_id,
            };
        },
        .persistent => return persistent.statSummary(routed.full),
    }
}

fn listMountDirectoryAlloc(allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var index: usize = 0;
    while (index < mount_table.max_mounts) : (index += 1) {
        const record = mount_table.entry(index) orelse continue;
        const line = try std.fmt.allocPrint(allocator, "dir {s}\n", .{record.name[0..record.name_len]});
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

fn normalizePath(path: []const u8, out: []u8) ![]const u8 {
    if (path.len == 0) return error.InvalidPath;
    if (out.len == 0) return error.InvalidPath;

    out[0] = '/';
    var out_len: usize = 1;

    var index: usize = 0;
    while (index < path.len and path[index] == '/') : (index += 1) {}
    if (index == path.len) return out[0..out_len];

    while (index < path.len) {
        const start = index;
        while (index < path.len and path[index] != '/') : (index += 1) {}
        const segment = path[start..index];
        if (segment.len == 0) continue;
        if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return error.InvalidPath;

        if (out_len != 1) {
            if (out_len >= out.len) return error.InvalidPath;
            out[out_len] = '/';
            out_len += 1;
        }
        if (out_len + segment.len > out.len) return error.InvalidPath;
        @memcpy(out[out_len .. out_len + segment.len], segment);
        out_len += segment.len;

        while (index < path.len and path[index] == '/') : (index += 1) {}
    }

    return out[0..out_len];
}

fn isMountPath(path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, mount_table.mount_root)) return false;
    return path.len == mount_table.mount_root.len or
        (path.len > mount_table.mount_root.len and path[mount_table.mount_root.len] == '/');
}

test "vfs route normalizes and classifies core trees" {
    mount_table.resetForTest();
    tmpfs.resetForTest();

    var normalized_buf: [256]u8 = undefined;
    var resolved_buf: [256]u8 = undefined;

    const root = try route("////", normalized_buf[0..], resolved_buf[0..]);
    try std.testing.expectEqual(RouteKind.persistent, root.kind);
    try std.testing.expectEqualStrings("/", root.full);

    const tmp = try route("/tmp/cache/demo.txt", normalized_buf[0..], resolved_buf[0..]);
    try std.testing.expectEqual(RouteKind.tmpfs, tmp.kind);
    try std.testing.expectEqualStrings("/tmp/cache/demo.txt", tmp.full);

    const proc = try route("/proc/runtime/snapshot", normalized_buf[0..], resolved_buf[0..]);
    try std.testing.expectEqual(RouteKind.virtual, proc.kind);
    try std.testing.expectEqualStrings("/proc/runtime/snapshot", proc.full);

    const mount_root = try route("/mnt", normalized_buf[0..], resolved_buf[0..]);
    try std.testing.expectEqual(RouteKind.mount_root, mount_root.kind);
    try std.testing.expectEqualStrings("/mnt", mount_root.full);
}

test "vfs route resolves aliases into underlying layers" {
    mount_table.resetForTest();
    tmpfs.resetForTest();

    try mount_table.set("boot", "/boot", 1);
    try mount_table.set("cache", "/tmp/cache", 2);

    var normalized_buf: [256]u8 = undefined;
    var resolved_buf: [256]u8 = undefined;

    const boot = try route("/mnt/boot/loader.cfg", normalized_buf[0..], resolved_buf[0..]);
    try std.testing.expectEqual(RouteKind.persistent, boot.kind);
    try std.testing.expectEqualStrings("/boot/loader.cfg", boot.full);

    const cache = try route("/mnt/cache/state.txt", normalized_buf[0..], resolved_buf[0..]);
    try std.testing.expectEqual(RouteKind.tmpfs, cache.kind);
    try std.testing.expectEqualStrings("/tmp/cache/state.txt", cache.full);

    try std.testing.expectError(error.FileNotFound, route("/mnt/missing/state.txt", normalized_buf[0..], resolved_buf[0..]));
}
