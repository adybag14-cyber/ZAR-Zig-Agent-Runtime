// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const filesystem = @import("filesystem.zig");

pub const max_name_len: usize = 32;
const root_dir = "/runtime/tty";
const max_state_bytes: usize = 512;
const max_input_bytes: usize = 2048;
const max_stream_bytes: usize = 2048;
const max_transcript_bytes: usize = 4096;

pub const Error = filesystem.Error || std.mem.Allocator.Error || error{
    InvalidTtyName,
    TtySessionNotFound,
    ResponseTooLarge,
};

const SessionState = struct {
    open: bool = false,
    command_count: u32 = 0,
    input_bytes: u32 = 0,
    stdout_bytes: u32 = 0,
    stderr_bytes: u32 = 0,
    last_exit_code: u8 = 0,
    updated_tick: u64 = 0,
};

const SessionFileKind = enum {
    info,
    input,
    stdout,
    stderr,
    transcript,
};

pub fn listSessionsAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const listing = filesystem.listDirectoryAlloc(allocator, root_dir, max_bytes) catch |err| switch (err) {
        error.FileNotFound => return allocator.alloc(u8, 0),
        else => return err,
    };
    defer allocator.free(listing);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, listing, '\n');
    while (lines.next()) |raw_line| {
        if (!std.mem.startsWith(u8, raw_line, "dir ")) continue;
        const session_name = std.mem.trim(u8, raw_line["dir ".len..], " \t\r");
        if (session_name.len == 0) continue;
        if (out.items.len + session_name.len + 1 > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, session_name);
        try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

pub fn renderStateAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const sessions = try listSessionsAlloc(allocator, max_bytes);
    defer allocator.free(sessions);

    var session_count: usize = 0;
    var open_count: usize = 0;
    var lines = std.mem.splitScalar(u8, sessions, '\n');
    while (lines.next()) |raw_name| {
        const name = std.mem.trim(u8, raw_name, " \t\r");
        if (name.len == 0) continue;
        session_count += 1;
        const state = loadState(allocator, name) catch |err| switch (err) {
            error.TtySessionNotFound => continue,
            else => return err,
        };
        if (state.open) open_count += 1;
    }

    const rendered = try std.fmt.allocPrint(
        allocator,
        "sessions={d}\nopen_sessions={d}\nroot={s}\n",
        .{ session_count, open_count, root_dir },
    );
    errdefer allocator.free(rendered);
    if (rendered.len > max_bytes) return error.ResponseTooLarge;
    return rendered;
}

pub fn openSession(name: []const u8, tick: u64) Error!void {
    try validateName(name);
    try filesystem.createDirPath(root_dir);

    var session_dir_buf: [filesystem.max_path_len]u8 = undefined;
    const session_dir = try sessionDirPath(name, &session_dir_buf);
    try filesystem.createDirPath(session_dir);

    var state = loadStateBounded(name) catch |err| switch (err) {
        error.TtySessionNotFound => SessionState{},
        else => return err,
    };
    state.open = true;
    state.updated_tick = tick;
    try saveState(name, state, tick);
}

pub fn closeSession(name: []const u8, tick: u64) Error!void {
    var state = try loadStateBounded(name);
    state.open = false;
    state.updated_tick = tick;
    try saveState(name, state, tick);
}

pub fn recordCommand(
    allocator: std.mem.Allocator,
    name: []const u8,
    command: []const u8,
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
    tick: u64,
) Error!void {
    var state = try loadState(allocator, name);
    if (!state.open) return error.TtySessionNotFound;

    const transcript_entry = try renderTranscriptEntryAlloc(allocator, command, exit_code, stdout, stderr);
    defer allocator.free(transcript_entry);

    try appendSessionFile(allocator, name, .input, command, max_input_bytes, tick);
    try appendSessionFile(allocator, name, .input, "\n", max_input_bytes, tick);
    try appendSessionFile(allocator, name, .stdout, stdout, max_stream_bytes, tick);
    try appendSessionFile(allocator, name, .stderr, stderr, max_stream_bytes, tick);
    try appendSessionFile(allocator, name, .transcript, transcript_entry, max_transcript_bytes, tick);

    state.command_count +%= 1;
    state.input_bytes +%= @as(u32, @intCast(command.len));
    state.stdout_bytes +%= @as(u32, @intCast(stdout.len));
    state.stderr_bytes +%= @as(u32, @intCast(stderr.len));
    state.last_exit_code = exit_code;
    state.updated_tick = tick;
    try saveState(name, state, tick);
}

pub fn infoAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    const state = try loadState(allocator, name);

    var state_path_buf: [filesystem.max_path_len]u8 = undefined;
    var input_path_buf: [filesystem.max_path_len]u8 = undefined;
    var stdout_path_buf: [filesystem.max_path_len]u8 = undefined;
    var stderr_path_buf: [filesystem.max_path_len]u8 = undefined;
    var transcript_path_buf: [filesystem.max_path_len]u8 = undefined;

    const rendered = try std.fmt.allocPrint(
        allocator,
        "name={s}\nopen={d}\ncommand_count={d}\nlast_exit_code={d}\ninput_bytes={d}\nstdout_bytes={d}\nstderr_bytes={d}\nupdated_tick={d}\nstate_path={s}\ninput_path={s}\nstdout_path={s}\nstderr_path={s}\ntranscript_path={s}\n",
        .{
            name,
            if (state.open) @as(u8, 1) else @as(u8, 0),
            state.command_count,
            state.last_exit_code,
            state.input_bytes,
            state.stdout_bytes,
            state.stderr_bytes,
            state.updated_tick,
            try sessionFilePath(name, .info, &state_path_buf),
            try sessionFilePath(name, .input, &input_path_buf),
            try sessionFilePath(name, .stdout, &stdout_path_buf),
            try sessionFilePath(name, .stderr, &stderr_path_buf),
            try sessionFilePath(name, .transcript, &transcript_path_buf),
        },
    );
    errdefer allocator.free(rendered);
    if (rendered.len > max_bytes) return error.ResponseTooLarge;
    return rendered;
}

pub fn inputAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    return readSessionFileAlloc(allocator, name, .input, max_bytes);
}

pub fn stdoutAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    return readSessionFileAlloc(allocator, name, .stdout, max_bytes);
}

pub fn stderrAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    return readSessionFileAlloc(allocator, name, .stderr, max_bytes);
}

pub fn transcriptAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    return readSessionFileAlloc(allocator, name, .transcript, max_bytes);
}

fn readSessionFileAlloc(
    allocator: std.mem.Allocator,
    name: []const u8,
    file_kind: SessionFileKind,
    max_bytes: usize,
) Error![]u8 {
    try validateName(name);
    if (file_kind == .info) return infoAlloc(allocator, name, max_bytes);

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try sessionFilePath(name, file_kind, &path_buf);
    return filesystem.readFileAlloc(allocator, path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => return allocator.alloc(u8, 0),
        else => return err,
    };
}

fn loadState(allocator: std.mem.Allocator, name: []const u8) Error!SessionState {
    try validateName(name);

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try sessionFilePath(name, .info, &path_buf);
    const bytes = filesystem.readFileAlloc(allocator, path, max_state_bytes) catch |err| switch (err) {
        error.FileNotFound => return error.TtySessionNotFound,
        else => return err,
    };
    defer allocator.free(bytes);

    return parseStateBytes(bytes);
}

fn loadStateBounded(name: []const u8) Error!SessionState {
    try validateName(name);

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try sessionFilePath(name, .info, &path_buf);
    var state_bytes: [max_state_bytes]u8 = undefined;
    const bytes = filesystem.readFile(path, &state_bytes) catch |err| switch (err) {
        error.FileNotFound => return error.TtySessionNotFound,
        else => return err,
    };
    return parseStateBytes(bytes);
}

fn parseStateBytes(bytes: []const u8) SessionState {
    var state = SessionState{};
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        const eq_index = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = line[0..eq_index];
        const value = line[eq_index + 1 ..];
        if (std.mem.eql(u8, key, "open")) {
            state.open = std.mem.eql(u8, value, "1");
        } else if (std.mem.eql(u8, key, "command_count")) {
            state.command_count = std.fmt.parseUnsigned(u32, value, 10) catch 0;
        } else if (std.mem.eql(u8, key, "input_bytes")) {
            state.input_bytes = std.fmt.parseUnsigned(u32, value, 10) catch 0;
        } else if (std.mem.eql(u8, key, "stdout_bytes")) {
            state.stdout_bytes = std.fmt.parseUnsigned(u32, value, 10) catch 0;
        } else if (std.mem.eql(u8, key, "stderr_bytes")) {
            state.stderr_bytes = std.fmt.parseUnsigned(u32, value, 10) catch 0;
        } else if (std.mem.eql(u8, key, "last_exit_code")) {
            state.last_exit_code = std.fmt.parseUnsigned(u8, value, 10) catch 0;
        } else if (std.mem.eql(u8, key, "updated_tick")) {
            state.updated_tick = std.fmt.parseUnsigned(u64, value, 10) catch 0;
        }
    }
    return state;
}

fn saveState(name: []const u8, state: SessionState, tick: u64) Error!void {
    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try sessionFilePath(name, .info, &path_buf);

    var body: [max_state_bytes]u8 = undefined;
    const rendered = std.fmt.bufPrint(
        &body,
        "open={d}\ncommand_count={d}\nlast_exit_code={d}\ninput_bytes={d}\nstdout_bytes={d}\nstderr_bytes={d}\nupdated_tick={d}\n",
        .{
            if (state.open) @as(u8, 1) else @as(u8, 0),
            state.command_count,
            state.last_exit_code,
            state.input_bytes,
            state.stdout_bytes,
            state.stderr_bytes,
            state.updated_tick,
        },
    ) catch return error.ResponseTooLarge;

    try filesystem.writeFile(path, rendered, tick);
}

fn appendSessionFile(
    allocator: std.mem.Allocator,
    name: []const u8,
    file_kind: SessionFileKind,
    suffix: []const u8,
    max_bytes: usize,
    tick: u64,
) Error!void {
    if (suffix.len == 0) return;

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try sessionFilePath(name, file_kind, &path_buf);

    const existing = filesystem.readFileAlloc(allocator, path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => try allocator.alloc(u8, 0),
        else => return err,
    };
    defer allocator.free(existing);

    if (existing.len + suffix.len > max_bytes) return error.ResponseTooLarge;
    const combined = try allocator.alloc(u8, existing.len + suffix.len);
    defer allocator.free(combined);
    @memcpy(combined[0..existing.len], existing);
    @memcpy(combined[existing.len..], suffix);
    try filesystem.writeFile(path, combined, tick);
}

fn renderTranscriptEntryAlloc(
    allocator: std.mem.Allocator,
    command: []const u8,
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
) Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, "$ ");
    try out.appendSlice(allocator, command);
    try out.appendSlice(allocator, "\n");
    const exit_line = try std.fmt.allocPrint(allocator, "exit={d}\n", .{exit_code});
    defer allocator.free(exit_line);
    try out.appendSlice(allocator, exit_line);
    if (stdout.len != 0) {
        try out.appendSlice(allocator, "stdout:\n");
        try out.appendSlice(allocator, stdout);
        if (stdout[stdout.len - 1] != '\n') try out.append(allocator, '\n');
    }
    if (stderr.len != 0) {
        try out.appendSlice(allocator, "stderr:\n");
        try out.appendSlice(allocator, stderr);
        if (stderr[stderr.len - 1] != '\n') try out.append(allocator, '\n');
    }
    try out.appendSlice(allocator, "---\n");
    if (out.items.len > max_transcript_bytes) return error.ResponseTooLarge;
    return out.toOwnedSlice(allocator);
}

fn sessionDirPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    return std.fmt.bufPrint(buffer, "{s}/{s}", .{ root_dir, name }) catch error.InvalidPath;
}

pub fn sessionFilePath(name: []const u8, file_kind: SessionFileKind, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateName(name);
    const file_name = switch (file_kind) {
        .info => "state.txt",
        .input => "input.log",
        .stdout => "stdout.log",
        .stderr => "stderr.log",
        .transcript => "transcript.log",
    };
    return std.fmt.bufPrint(buffer, "{s}/{s}/{s}", .{ root_dir, name, file_name }) catch error.InvalidPath;
}

fn validateName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > max_name_len) return error.InvalidTtyName;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
        return error.InvalidTtyName;
    }
}

test "tty runtime records bounded session receipts" {
    filesystem.resetForTest();
    try filesystem.init();

    try openSession("demo", 1);
    try recordCommand(std.testing.allocator, "demo", "echo tty-ok", 0, "tty-ok\n", "", 2);

    const list = try listSessionsAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(list);
    try std.testing.expectEqualStrings("demo\n", list);

    const state = try renderStateAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(state);
    try std.testing.expect(std.mem.indexOf(u8, state, "sessions=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, state, "open_sessions=1") != null);

    const info = try infoAlloc(std.testing.allocator, "demo", 512);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "open=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "command_count=1") != null);

    const input = try inputAlloc(std.testing.allocator, "demo", 128);
    defer std.testing.allocator.free(input);
    try std.testing.expectEqualStrings("echo tty-ok\n", input);

    const stdout = try stdoutAlloc(std.testing.allocator, "demo", 128);
    defer std.testing.allocator.free(stdout);
    try std.testing.expectEqualStrings("tty-ok\n", stdout);

    const transcript = try transcriptAlloc(std.testing.allocator, "demo", 512);
    defer std.testing.allocator.free(transcript);
    try std.testing.expect(std.mem.indexOf(u8, transcript, "$ echo tty-ok\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, transcript, "stdout:\ntty-ok\n") != null);

    try closeSession("demo", 3);
    const closed_info = try infoAlloc(std.testing.allocator, "demo", 512);
    defer std.testing.allocator.free(closed_info);
    try std.testing.expect(std.mem.indexOf(u8, closed_info, "open=0") != null);
}
