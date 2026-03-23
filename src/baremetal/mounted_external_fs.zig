// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const ext2_ro = @import("ext2_ro.zig");
const fat32_ro = @import("fat32_ro.zig");
const storage_backend = @import("storage_backend.zig");
const storage_registry = @import("storage_registry.zig");
const virtio_block = @import("virtio_block.zig");

pub const root_path = "/__storagefs";
pub const active_root = "/__storagefs/active";
pub const ext2_root = "/__storagefs/ext2";
pub const fat32_root = "/__storagefs/fat32";

pub const Error = std.mem.Allocator.Error || storage_backend.Error || ext2_ro.Error || fat32_ro.Error || error{
    FileNotFound,
    FileTooBig,
    NotDirectory,
    IsDirectory,
    ResponseTooLarge,
    ReadOnlyPath,
};

pub const SimpleStat = struct {
    kind: std.Io.File.Kind,
    size: u64,
    checksum: u32,
    modified_tick: u64,
    entry_id: u64,
};

const ExternalKind = enum {
    root,
    active,
    ext2,
    fat32,
};

const ParsedPath = struct {
    kind: ExternalKind,
    relative: []const u8,
};

pub fn handles(path: []const u8) bool {
    return std.mem.eql(u8, path, root_path) or
        std.mem.startsWith(u8, path, root_path ++ "/");
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
    const parsed = parsePath(path) orelse return error.FileNotFound;
    const kind = try resolveKind(parsed.kind);
    if (parsed.relative.len == 0 or std.mem.eql(u8, parsed.relative, "/")) return error.IsDirectory;
    return switch (kind) {
        .ext2 => ext2_ro.readFileAlloc(allocator, parsed.relative, max_bytes),
        .fat32 => fat32_ro.readFileAlloc(allocator, parsed.relative, max_bytes),
        else => error.FileNotFound,
    };
}

pub fn readFile(path: []const u8, buffer: []u8) Error![]const u8 {
    const parsed = parsePath(path) orelse return error.FileNotFound;
    const kind = try resolveKind(parsed.kind);
    if (parsed.relative.len == 0 or std.mem.eql(u8, parsed.relative, "/")) return error.IsDirectory;
    return switch (kind) {
        .ext2 => ext2_ro.readFile(parsed.relative, buffer),
        .fat32 => fat32_ro.readFile(parsed.relative, buffer),
        else => error.FileNotFound,
    };
}

pub fn listDirectoryAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
    const parsed = parsePath(path) orelse return error.FileNotFound;
    if (parsed.kind == .root) return listRouterRootAlloc(allocator, max_bytes);
    const kind = try resolveKind(parsed.kind);
    if (!(parsed.relative.len == 0 or std.mem.eql(u8, parsed.relative, "/"))) {
        const stat = try statSummary(path);
        if (stat.kind != .directory) return error.NotDirectory;
    }
    return switch (kind) {
        .ext2 => ext2_ro.listRootAlloc(allocator, max_bytes),
        .fat32 => fat32_ro.listRootAlloc(allocator, max_bytes),
        else => error.FileNotFound,
    };
}

pub fn statSummary(path: []const u8) Error!SimpleStat {
    const parsed = parsePath(path) orelse return error.FileNotFound;
    if (parsed.kind == .root) {
        return .{ .kind = .directory, .size = 0, .checksum = 0, .modified_tick = 0, .entry_id = 1 };
    }
    const kind = try resolveKind(parsed.kind);
    if (parsed.relative.len == 0 or std.mem.eql(u8, parsed.relative, "/")) {
        return .{ .kind = .directory, .size = 0, .checksum = 0, .modified_tick = 0, .entry_id = checksumBytes(path) };
    }
    return switch (kind) {
        .ext2 => mapStat(try ext2_ro.statSummary(parsed.relative)),
        .fat32 => mapStat(try fat32_ro.statSummary(parsed.relative)),
        else => error.FileNotFound,
    };
}

pub fn writeFile(path: []const u8, data: []const u8, tick: u64) Error!void {
    const parsed = parsePath(path) orelse return error.FileNotFound;
    const kind = try resolveKind(parsed.kind);
    if (parsed.relative.len == 0 or std.mem.eql(u8, parsed.relative, "/")) return error.IsDirectory;
    return switch (kind) {
        .fat32 => fat32_ro.writeFile(parsed.relative, data, tick),
        .ext2 => error.ReadOnlyPath,
        else => error.FileNotFound,
    };
}

pub fn deleteFile(path: []const u8) Error!void {
    const parsed = parsePath(path) orelse return error.FileNotFound;
    const kind = try resolveKind(parsed.kind);
    if (parsed.relative.len == 0 or std.mem.eql(u8, parsed.relative, "/")) return error.IsDirectory;
    return switch (kind) {
        .fat32 => fat32_ro.deleteFile(parsed.relative),
        .ext2 => error.ReadOnlyPath,
        else => error.FileNotFound,
    };
}

fn listRouterRootAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const rows = [_][]const u8{
        "dir active\n",
        "dir ext2\n",
        "dir fat32\n",
    };
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (rows) |row| {
        if (out.items.len + row.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, row);
    }
    return out.toOwnedSlice(allocator);
}

fn parsePath(path: []const u8) ?ParsedPath {
    if (std.mem.eql(u8, path, root_path)) return .{ .kind = .root, .relative = "/" };
    if (std.mem.eql(u8, path, active_root)) return .{ .kind = .active, .relative = "/" };
    if (std.mem.eql(u8, path, ext2_root)) return .{ .kind = .ext2, .relative = "/" };
    if (std.mem.eql(u8, path, fat32_root)) return .{ .kind = .fat32, .relative = "/" };
    if (std.mem.startsWith(u8, path, active_root ++ "/")) return .{ .kind = .active, .relative = path[active_root.len..] };
    if (std.mem.startsWith(u8, path, ext2_root ++ "/")) return .{ .kind = .ext2, .relative = path[ext2_root.len..] };
    if (std.mem.startsWith(u8, path, fat32_root ++ "/")) return .{ .kind = .fat32, .relative = path[fat32_root.len..] };
    return null;
}

fn resolveKind(kind: ExternalKind) Error!storage_registry.FilesystemKind {
    const active = storage_registry.detectPersistentFilesystemKind();
    return switch (kind) {
        .root => error.FileNotFound,
        .active => switch (active) {
            .ext2, .fat32 => active,
            else => error.FileNotFound,
        },
        .ext2 => if (active == .ext2) .ext2 else error.FileNotFound,
        .fat32 => if (active == .fat32) .fat32 else error.FileNotFound,
    };
}

fn mapStat(stat: anytype) SimpleStat {
    return .{
        .kind = stat.kind,
        .size = stat.size,
        .checksum = stat.checksum,
        .modified_tick = stat.modified_tick,
        .entry_id = stat.entry_id,
    };
}

fn checksumBytes(bytes: []const u8) u32 {
    return std.hash.Crc32.hash(bytes);
}

test "mounted external fs routes ext2 reads through active root" {
    storage_backend.resetForTest();
    virtio_block.testEnableMockDevice(256);
    defer virtio_block.testDisableMockDevice();
    storage_backend.init();
    try ext2_ro.seedTestImage();

    const listing = try listDirectoryAlloc(std.testing.allocator, active_root, 256);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("file HELLO.TXT 15\n", listing);

    const file = try readFileAlloc(std.testing.allocator, active_root ++ "/HELLO.TXT", 64);
    defer std.testing.allocator.free(file);
    try std.testing.expectEqualStrings(ext2_ro.test_file_payload, file);
}

test "mounted external fs routes fat32 reads through active root" {
    storage_backend.resetForTest();
    virtio_block.testEnableMockDevice(256);
    defer virtio_block.testDisableMockDevice();
    storage_backend.init();
    try fat32_ro.seedTestImage();

    const listing = try listDirectoryAlloc(std.testing.allocator, active_root, 256);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("file HELLO.TXT 16\n", listing);

    const file = try readFileAlloc(std.testing.allocator, active_root ++ "/HELLO.TXT", 64);
    defer std.testing.allocator.free(file);
    try std.testing.expectEqualStrings(fat32_ro.test_file_payload, file);
}

test "mounted external fs routes bounded fat32 writes through active root" {
    storage_backend.resetForTest();
    virtio_block.testEnableMockDevice(256);
    defer virtio_block.testDisableMockDevice();
    storage_backend.init();
    try fat32_ro.seedTestImage();

    try writeFile(active_root ++ "/WRITE.TXT", "mounted-fat32", 9);
    const file = try readFileAlloc(std.testing.allocator, active_root ++ "/WRITE.TXT", 64);
    defer std.testing.allocator.free(file);
    try std.testing.expectEqualStrings("mounted-fat32", file);

    try deleteFile(active_root ++ "/WRITE.TXT");
    try std.testing.expectEqual(error.FileNotFound, readFileAlloc(std.testing.allocator, active_root ++ "/WRITE.TXT", 64));
}
