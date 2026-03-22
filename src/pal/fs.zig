// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const baremetal_filesystem = @import("../baremetal/filesystem.zig");

fn readFileAllocHosted(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    max_bytes: usize,
) ![]u8 {
    if (shouldUseBaremetalFilesystem(path)) {
        return baremetal_filesystem.readFileAlloc(allocator, path, max_bytes);
    }
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_bytes));
}

fn readFileAllocBaremetal(
    _: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    max_bytes: usize,
) ![]u8 {
    return baremetal_filesystem.readFileAlloc(allocator, path, max_bytes);
}

pub const readFileAlloc = if (builtin.os.tag == .freestanding) readFileAllocBaremetal else readFileAllocHosted;

fn writeFileHosted(io: std.Io, path: []const u8, data: []const u8) !void {
    if (shouldUseBaremetalFilesystem(path)) {
        return baremetal_filesystem.writeFile(path, data, 0);
    }
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = data,
    });
}

fn writeFileBaremetal(_: std.Io, path: []const u8, data: []const u8) !void {
    try baremetal_filesystem.writeFile(path, data, 0);
}

pub const writeFile = if (builtin.os.tag == .freestanding) writeFileBaremetal else writeFileHosted;

fn createDirPathHosted(io: std.Io, path: []const u8) !void {
    if (shouldUseBaremetalFilesystem(path)) {
        return baremetal_filesystem.createDirPath(path);
    }
    try std.Io.Dir.cwd().createDirPath(io, path);
}

fn createDirPathBaremetal(_: std.Io, path: []const u8) !void {
    try baremetal_filesystem.createDirPath(path);
}

pub const createDirPath = if (builtin.os.tag == .freestanding) createDirPathBaremetal else createDirPathHosted;

fn statNoFollowHosted(io: std.Io, path: []const u8) !std.Io.Dir.Stat {
    if (shouldUseBaremetalFilesystem(path)) {
        return baremetal_filesystem.statNoFollow(path);
    }
    return std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
}

fn statNoFollowBaremetal(_: std.Io, path: []const u8) !std.Io.Dir.Stat {
    return baremetal_filesystem.statNoFollow(path);
}

pub const statNoFollow = if (builtin.os.tag == .freestanding) statNoFollowBaremetal else statNoFollowHosted;

fn shouldUseBaremetalFilesystem(path: []const u8) bool {
    if (!builtin.is_test) return false;
    if (!std.mem.startsWith(u8, path, "/")) return false;
    return isBaremetalHostedPath(path);
}

fn isBaremetalHostedPath(path: []const u8) bool {
    return matchesBaremetalRoot(path, "/runtime") or
        matchesBaremetalRoot(path, "/packages") or
        matchesBaremetalRoot(path, "/pkg") or
        matchesBaremetalRoot(path, "/tools") or
        matchesBaremetalRoot(path, "/proc") or
        matchesBaremetalRoot(path, "/sys") or
        matchesBaremetalRoot(path, "/dev") or
        matchesBaremetalRoot(path, "/loader") or
        matchesBaremetalRoot(path, "/boot");
}

fn matchesBaremetalRoot(path: []const u8, root: []const u8) bool {
    if (!std.mem.startsWith(u8, path, root)) return false;
    return path.len == root.len or path[root.len] == '/';
}

test "hosted pal fs path classifier only routes baremetal virtual roots" {
    try std.testing.expect(isBaremetalHostedPath("/runtime/state/runtime-state.json"));
    try std.testing.expect(isBaremetalHostedPath("/packages/demo/bin/main.oc"));
    try std.testing.expect(!isBaremetalHostedPath("/home/runner/work/ZAR-Zig-Agent-Runtime/runtime-state.json"));
    try std.testing.expect(!isBaremetalHostedPath("/tmp/zig-test-cache/runtime-state.json"));
    try std.testing.expect(!shouldUseBaremetalFilesystem("C:\\temp\\runtime-state.json"));
}
