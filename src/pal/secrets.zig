// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub fn envLookupAlloc(
    environ: std.process.Environ,
    allocator: std.mem.Allocator,
    name: []const u8,
) !?[]u8 {
    const raw = std.process.Environ.getAlloc(environ, allocator, name) catch |err| {
        const err_name = @errorName(err);
        if (std.mem.eql(u8, err_name, "EnvironmentVariableMissing")) return null;
        if (std.mem.eql(u8, err_name, "EnvironmentVariableNotFound")) return null;
        if (std.mem.eql(u8, err_name, "InvalidWtf8")) return null;
        return err;
    };
    errdefer allocator.free(raw);

    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) {
        allocator.free(raw);
        return null;
    }
    if (trimmed.ptr == raw.ptr and trimmed.len == raw.len) {
        return raw;
    }

    const out = try allocator.dupe(u8, trimmed);
    allocator.free(raw);
    return out;
}

pub fn resolveFirstAlloc(
    environ: std.process.Environ,
    allocator: std.mem.Allocator,
    candidates: []const []const u8,
) !?[]u8 {
    for (candidates) |name| {
        if (try envLookupAlloc(environ, allocator, name)) |value| return value;
    }
    return null;
}

pub fn envTruthy(
    environ: std.process.Environ,
    allocator: std.mem.Allocator,
    name: []const u8,
) bool {
    const raw = envLookupAlloc(environ, allocator, name) catch return false;
    defer if (raw) |value| allocator.free(value);
    const value = raw orelse return false;
    if (std.ascii.eqlIgnoreCase(value, "0")) return false;
    if (std.ascii.eqlIgnoreCase(value, "false")) return false;
    if (std.ascii.eqlIgnoreCase(value, "off")) return false;
    if (std.ascii.eqlIgnoreCase(value, "no")) return false;
    return true;
}
