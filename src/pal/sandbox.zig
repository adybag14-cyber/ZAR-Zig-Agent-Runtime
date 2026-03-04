const builtin = @import("builtin");
const std = @import("std");

pub fn hasParentTraversal(path: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    while (it.next()) |segment| {
        if (std.mem.eql(u8, segment, "..")) return true;
    }
    return false;
}

pub fn resolveAbsolutePath(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, path, " \t\r\n");
    if (trimmed.len == 0) return error.PathAccessDenied;

    if (std.fs.path.isAbsolute(trimmed)) {
        return std.fs.path.resolve(allocator, &.{trimmed});
    }

    const cwd_real_z = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", allocator);
    defer allocator.free(cwd_real_z);
    const cwd_real = std.mem.sliceTo(cwd_real_z, 0);
    return std.fs.path.resolve(allocator, &.{ cwd_real, trimmed });
}

pub fn parseAllowedRoots(
    io: std.Io,
    allocator: std.mem.Allocator,
    csv: []const u8,
) !std.ArrayList([]u8) {
    var roots: std.ArrayList([]u8) = .empty;
    errdefer freePathList(allocator, &roots);

    const trimmed = std.mem.trim(u8, csv, " \t\r\n");
    if (trimmed.len == 0) {
        const cwd_real_z = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", allocator);
        defer allocator.free(cwd_real_z);
        try roots.append(allocator, try allocator.dupe(u8, std.mem.sliceTo(cwd_real_z, 0)));
        return roots;
    }

    var it = std.mem.tokenizeAny(u8, trimmed, ",;");
    while (it.next()) |entry_raw| {
        const entry = std.mem.trim(u8, entry_raw, " \t\r\n");
        if (entry.len == 0) continue;
        const absolute_root = try resolveAbsolutePath(io, allocator, entry);
        defer allocator.free(absolute_root);
        const real_root_z = std.Io.Dir.realPathFileAbsoluteAlloc(io, absolute_root, allocator) catch continue;
        defer allocator.free(real_root_z);
        const real_root = std.mem.sliceTo(real_root_z, 0);
        const stat = std.Io.Dir.cwd().statFile(io, real_root, .{ .follow_symlinks = false }) catch continue;
        if (stat.kind == .sym_link) continue;
        if (stat.kind != .directory) continue;
        try roots.append(allocator, try allocator.dupe(u8, real_root));
    }

    return roots;
}

pub fn resolveNearestExistingPath(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]u8 {
    var current = try allocator.dupe(u8, path);
    errdefer allocator.free(current);

    while (true) {
        const current_real_z = std.Io.Dir.realPathFileAbsoluteAlloc(io, current, allocator) catch |err| switch (err) {
            error.FileNotFound => {
                const parent = std.fs.path.dirname(current) orelse return error.PathAccessDenied;
                if (parent.len == 0 or std.mem.eql(u8, parent, current)) return error.PathAccessDenied;
                const next = try allocator.dupe(u8, parent);
                allocator.free(current);
                current = next;
                continue;
            },
            else => return error.PathAccessDenied,
        };
        defer allocator.free(current_real_z);

        const current_real = try allocator.dupe(u8, std.mem.sliceTo(current_real_z, 0));
        allocator.free(current);
        return current_real;
    }
}

pub fn freePathList(allocator: std.mem.Allocator, list: *std.ArrayList([]u8)) void {
    for (list.items) |entry| allocator.free(entry);
    list.deinit(allocator);
}

pub fn isWithinAnyRoot(path: []const u8, roots: []const []const u8) bool {
    for (roots) |root| {
        if (pathWithinRoot(path, root)) return true;
    }
    return false;
}

fn pathWithinRoot(path: []const u8, root: []const u8) bool {
    const root_norm = trimTrailingSeparators(root);
    const path_norm = trimTrailingSeparators(path);
    if (path_norm.len < root_norm.len) return false;
    if (!pathPrefixEqual(path_norm, root_norm)) return false;
    if (path_norm.len == root_norm.len) return true;
    return isPathSeparator(path_norm[root_norm.len]);
}

fn trimTrailingSeparators(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 1 and isPathSeparator(path[end - 1])) : (end -= 1) {}
    if (builtin.os.tag == .windows and path.len >= 2 and path[1] == ':') {
        if (end < 3) return path[0..3];
    }
    return path[0..end];
}

fn pathPrefixEqual(path: []const u8, prefix: []const u8) bool {
    for (prefix, 0..) |expected, idx| {
        if (!pathCharEq(path[idx], expected)) return false;
    }
    return true;
}

fn isPathSeparator(ch: u8) bool {
    return if (builtin.os.tag == .windows)
        (ch == '/' or ch == '\\')
    else
        ch == '/';
}

fn pathCharEq(lhs: u8, rhs: u8) bool {
    if (builtin.os.tag != .windows) return lhs == rhs;
    const a = if (isPathSeparator(lhs)) '\\' else std.ascii.toLower(lhs);
    const b = if (isPathSeparator(rhs)) '\\' else std.ascii.toLower(rhs);
    return a == b;
}

test "path-in-root handles windows-like separators case-insensitively" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try std.testing.expect(isWithinAnyRoot("C:\\Temp\\Root\\file.txt", &.{"c:/temp/root"}));
}
