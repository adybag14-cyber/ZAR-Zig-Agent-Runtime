// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");

pub const max_entries: usize = 48;
pub const max_path_len: usize = 224;
pub const max_file_bytes: usize = 4096;
pub const root_path = "/tmp";

pub const Error = std.mem.Allocator.Error || error{
    InvalidPath,
    FileNotFound,
    FileTooBig,
    NotDirectory,
    IsDirectory,
    NoSpace,
    ResponseTooLarge,
};

pub const SimpleStat = struct {
    kind: std.Io.File.Kind,
    size: u64,
    checksum: u32,
    modified_tick: u64,
    entry_id: u64,
};

const Entry = struct {
    kind: u8 = 0,
    path_len: u16 = 0,
    byte_len: u32 = 0,
    checksum: u32 = 0,
    modified_tick: u64 = 0,
    entry_id: u64 = 0,
    path: [max_path_len]u8 = [_]u8{0} ** max_path_len,
    data: [max_file_bytes]u8 = [_]u8{0} ** max_file_bytes,
};

const DirectoryChild = struct {
    name: [max_path_len]u8 = undefined,
    name_len: usize,
    kind: u8,
    size: u32,
};

var entries: [max_entries]Entry = [_]Entry{.{}} ** max_entries;
var last_entry_id: u64 = 0;

pub fn resetForTest() void {
    @memset(&entries, .{});
    last_entry_id = 0;
}

pub fn handles(path: []const u8) bool {
    return std.mem.eql(u8, path, root_path) or std.mem.startsWith(u8, path, "/tmp/");
}

pub fn createDirPath(path: []const u8) Error!void {
    if (!handles(path)) return error.InvalidPath;
    if (std.mem.eql(u8, path, root_path)) return;

    var index: usize = root_path.len + 1;
    while (index <= path.len) : (index += 1) {
        const at_end = index == path.len;
        if (!at_end and path[index] != '/') continue;

        const prefix = path[0..index];
        if (std.mem.eql(u8, prefix, root_path)) continue;

        const existing = findEntryIndex(prefix);
        if (existing) |entry_index| {
            if (entries[entry_index].kind != abi.filesystem_kind_directory) return error.NotDirectory;
            continue;
        }

        const free_index = try findFreeEntryIndex();
        entries[free_index] = makeEntry(prefix, abi.filesystem_kind_directory, &.{}, 0);
    }
}

pub fn writeFile(path: []const u8, data: []const u8, tick: u64) Error!void {
    if (!handles(path) or std.mem.eql(u8, path, root_path)) return error.InvalidPath;
    if (data.len > max_file_bytes) return error.FileTooBig;

    const parent = parentSlice(path);
    if (!std.mem.eql(u8, parent, root_path)) {
        const parent_index = findEntryIndex(parent) orelse return error.FileNotFound;
        if (entries[parent_index].kind != abi.filesystem_kind_directory) return error.NotDirectory;
    }

    if (findEntryIndex(path)) |entry_index| {
        if (entries[entry_index].kind != abi.filesystem_kind_file) return error.IsDirectory;
        updateFileEntry(entry_index, data, tick);
        return;
    }

    const free_index = try findFreeEntryIndex();
    entries[free_index] = makeEntry(path, abi.filesystem_kind_file, data, tick);
}

pub fn deleteFile(path: []const u8) Error!void {
    if (!handles(path) or std.mem.eql(u8, path, root_path)) return error.InvalidPath;
    const entry_index = findEntryIndex(path) orelse return error.FileNotFound;
    if (entries[entry_index].kind != abi.filesystem_kind_file) return error.IsDirectory;
    entries[entry_index] = .{};
}

pub fn deleteTree(path: []const u8) Error!void {
    if (!handles(path)) return error.InvalidPath;
    if (std.mem.eql(u8, path, root_path)) {
        resetForTest();
        return;
    }
    _ = findEntryIndex(path) orelse return error.FileNotFound;

    var removed_any = false;
    for (&entries) |*record| {
        if (record.kind == 0) continue;
        const record_path = record.path[0..record.path_len];
        if (!pathMatchesTree(path, record_path)) continue;
        record.* = .{};
        removed_any = true;
    }
    if (!removed_any) return error.FileNotFound;
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
    if (!handles(path)) return error.FileNotFound;
    const entry_index = findEntryIndex(path) orelse return error.FileNotFound;
    const entry = entries[entry_index];
    if (entry.kind != abi.filesystem_kind_file) return error.IsDirectory;
    if (entry.byte_len > max_bytes) return error.FileTooBig;
    return allocator.dupe(u8, entry.data[0..entry.byte_len]);
}

pub fn readFile(path: []const u8, buffer: []u8) Error![]const u8 {
    if (!handles(path)) return error.FileNotFound;
    const entry_index = findEntryIndex(path) orelse return error.FileNotFound;
    const entry = entries[entry_index];
    if (entry.kind != abi.filesystem_kind_file) return error.IsDirectory;
    if (entry.byte_len > buffer.len) return error.FileTooBig;
    const byte_len: usize = @intCast(entry.byte_len);
    @memcpy(buffer[0..byte_len], entry.data[0..byte_len]);
    return buffer[0..byte_len];
}

pub fn listDirectoryAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
    if (!handles(path)) return error.FileNotFound;
    if (!std.mem.eql(u8, path, root_path)) {
        const entry_index = findEntryIndex(path) orelse return error.FileNotFound;
        if (entries[entry_index].kind != abi.filesystem_kind_directory) return error.NotDirectory;
    }

    var children: [max_entries]DirectoryChild = undefined;
    var child_count: usize = 0;

    for (&entries) |*record| {
        if (record.kind == 0) continue;
        const record_path = record.path[0..record.path_len];
        const child_name = directChildName(path, record_path) orelse continue;

        var existing_index: ?usize = null;
        for (children[0..child_count], 0..) |existing, index| {
            if (existing.name_len != child_name.len) continue;
            if (std.mem.eql(u8, existing.name[0..existing.name_len], child_name)) {
                existing_index = index;
                break;
            }
        }
        if (existing_index) |index| {
            if (record.kind == abi.filesystem_kind_directory) {
                children[index].kind = abi.filesystem_kind_directory;
                children[index].size = 0;
            }
            continue;
        }

        children[child_count] = .{
            .name_len = child_name.len,
            .kind = record.kind,
            .size = if (record.kind == abi.filesystem_kind_file) record.byte_len else 0,
        };
        @memcpy(children[child_count].name[0..child_name.len], child_name);
        child_count += 1;
    }

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (children[0..child_count]) |child| {
        const line = if (child.kind == abi.filesystem_kind_directory)
            try std.fmt.allocPrint(allocator, "dir {s}\n", .{child.name[0..child.name_len]})
        else
            try std.fmt.allocPrint(allocator, "file {s} {d}\n", .{ child.name[0..child.name_len], child.size });
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }
    return out.toOwnedSlice(allocator);
}

pub fn statSummary(path: []const u8) Error!SimpleStat {
    if (!handles(path)) return error.FileNotFound;
    if (std.mem.eql(u8, path, root_path)) {
        return .{
            .kind = .directory,
            .size = 0,
            .checksum = 0,
            .modified_tick = 0,
            .entry_id = checksumBytes(path),
        };
    }

    const entry_index = findEntryIndex(path) orelse return error.FileNotFound;
    const entry = entries[entry_index];
    return .{
        .kind = if (entry.kind == abi.filesystem_kind_directory) .directory else .file,
        .size = entry.byte_len,
        .checksum = entry.checksum,
        .modified_tick = entry.modified_tick,
        .entry_id = entry.entry_id,
    };
}

fn findEntryIndex(path: []const u8) ?usize {
    for (&entries, 0..) |*entry, index| {
        if (entry.kind == 0 or entry.path_len != path.len) continue;
        if (std.mem.eql(u8, entry.path[0..entry.path_len], path)) return index;
    }
    return null;
}

fn findFreeEntryIndex() Error!usize {
    for (&entries, 0..) |*entry, index| {
        if (entry.kind == 0) return index;
    }
    return error.NoSpace;
}

fn makeEntry(path: []const u8, kind: u8, data: []const u8, tick: u64) Entry {
    last_entry_id +%= 1;
    var entry = Entry{
        .kind = kind,
        .path_len = @intCast(path.len),
        .byte_len = @intCast(data.len),
        .checksum = checksumBytes(data),
        .modified_tick = tick,
        .entry_id = last_entry_id,
    };
    @memcpy(entry.path[0..path.len], path);
    if (data.len != 0) {
        @memcpy(entry.data[0..data.len], data);
    }
    return entry;
}

fn updateFileEntry(entry_index: usize, data: []const u8, tick: u64) void {
    entries[entry_index].byte_len = @intCast(data.len);
    entries[entry_index].checksum = checksumBytes(data);
    entries[entry_index].modified_tick = tick;
    @memset(entries[entry_index].data[0..], 0);
    if (data.len != 0) {
        @memcpy(entries[entry_index].data[0..data.len], data);
    }
}

fn parentSlice(path: []const u8) []const u8 {
    if (std.mem.eql(u8, path, root_path)) return root_path;
    if (std.mem.lastIndexOfScalar(u8, path[1..], '/')) |relative_index| {
        const last_slash = relative_index + 1;
        if (last_slash == 0) return root_path;
        return path[0..last_slash];
    }
    return root_path;
}

fn directChildName(parent: []const u8, candidate: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, candidate, parent)) return null;
    if (!std.mem.startsWith(u8, candidate, parent)) return null;

    var start = parent.len;
    if (parent.len > 1) {
        if (candidate.len <= parent.len or candidate[parent.len] != '/') return null;
        start += 1;
    } else if (candidate[0] == '/') {
        start = 1;
    }

    const remainder = candidate[start..];
    if (remainder.len == 0) return null;
    if (std.mem.indexOfScalar(u8, remainder, '/')) |slash_index| {
        return remainder[0..slash_index];
    }
    return remainder;
}

fn pathMatchesTree(root: []const u8, candidate: []const u8) bool {
    if (std.mem.eql(u8, root, candidate)) return true;
    if (!std.mem.startsWith(u8, candidate, root)) return false;
    if (candidate.len <= root.len) return false;
    return candidate[root.len] == '/';
}

fn checksumBytes(bytes: []const u8) u32 {
    var total: u32 = 0;
    for (bytes) |byte| total +%= byte;
    return total;
}

test "tmpfs create write read list stat delete tree lifecycle" {
    resetForTest();

    try createDirPath("/tmp/cache/nested");
    try writeFile("/tmp/cache/nested/state.txt", "edge", 7);

    const payload = try readFileAlloc(std.testing.allocator, "/tmp/cache/nested/state.txt", 32);
    defer std.testing.allocator.free(payload);
    try std.testing.expectEqualStrings("edge", payload);

    const stat = try statSummary("/tmp/cache/nested/state.txt");
    try std.testing.expectEqual(std.Io.File.Kind.file, stat.kind);
    try std.testing.expectEqual(@as(u64, 4), stat.size);
    try std.testing.expectEqual(@as(u64, 7), stat.modified_tick);

    const listing = try listDirectoryAlloc(std.testing.allocator, "/tmp/cache/nested", 128);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("file state.txt 4\n", listing);

    try deleteFile("/tmp/cache/nested/state.txt");
    try std.testing.expectError(error.FileNotFound, readFileAlloc(std.testing.allocator, "/tmp/cache/nested/state.txt", 32));

    try writeFile("/tmp/cache/nested/state.txt", "again", 9);
    try deleteTree("/tmp/cache");
    try std.testing.expectError(error.FileNotFound, statSummary("/tmp/cache"));
}

test "tmpfs does not persist across reset" {
    resetForTest();
    try createDirPath("/tmp/run");
    try writeFile("/tmp/run/state.txt", "volatile", 11);
    resetForTest();
    try std.testing.expectError(error.FileNotFound, statSummary("/tmp/run/state.txt"));
    const root_stat = try statSummary("/tmp");
    try std.testing.expectEqual(std.Io.File.Kind.directory, root_stat.kind);
}
