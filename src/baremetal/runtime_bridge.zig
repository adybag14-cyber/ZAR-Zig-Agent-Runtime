// SPDX-License-Identifier: GPL-2.0-only
const builtin = @import("builtin");
const std = @import("std");
const tool_runtime = @import("../runtime/tool_runtime.zig");

pub const state_root = "/runtime/state";
pub const bounded_exec_allowlist = "echo";

pub fn initRuntime(allocator: std.mem.Allocator) !tool_runtime.ToolRuntime {
    var runtime = tool_runtime.ToolRuntime.init(allocator, runtimeIo());
    errdefer runtime.deinit();
    try runtime.configureStatePersistence(state_root);
    runtime.exec_enabled = true;
    runtime.exec_allowlist = bounded_exec_allowlist;
    return runtime;
}

pub fn snapshotAlloc(allocator: std.mem.Allocator) ![]u8 {
    var runtime = try initRuntime(allocator);
    defer runtime.deinit();
    return runtime.snapshotTextAlloc(allocator);
}

pub fn sessionListAlloc(allocator: std.mem.Allocator) ![]u8 {
    var runtime = try initRuntime(allocator);
    defer runtime.deinit();
    return runtime.sessionListTextAlloc(allocator);
}

pub fn sessionInfoAlloc(allocator: std.mem.Allocator, session_id: []const u8) ![]u8 {
    var runtime = try initRuntime(allocator);
    defer runtime.deinit();
    return runtime.sessionInfoTextAlloc(allocator, session_id);
}

pub fn handleRpcFrameAlloc(allocator: std.mem.Allocator, frame_json: []const u8) ![]u8 {
    var runtime = try initRuntime(allocator);
    defer runtime.deinit();
    return runtime.handleRpcFrameAlloc(allocator, frame_json);
}

fn runtimeIo() std.Io {
    if (builtin.os.tag == .freestanding) return undefined;
    if (builtin.is_test) return std.testing.io;
    return std.Io.Threaded.global_single_threaded.io();
}
