// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const filesystem = @import("filesystem.zig");

pub const max_name_len: usize = 32;
const root_dir = "/runtime/tty";
const max_state_bytes: usize = 512;
const max_input_bytes: usize = 2048;
const max_stream_bytes: usize = 2048;
const max_pending_bytes: usize = 2048;
const max_events_bytes: usize = 2048;
const max_transcript_bytes: usize = 4096;
const max_session_file_bytes: usize = max_transcript_bytes;

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
    pending_input_bytes: u32 = 0,
    event_count: u32 = 0,
    last_exit_code: u8 = 0,
    updated_tick: u64 = 0,
};

const SessionFileKind = enum {
    info,
    input,
    pending,
    stdout,
    stderr,
    events,
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
    var pending_bytes: usize = 0;
    var event_count: usize = 0;
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
        pending_bytes += state.pending_input_bytes;
        event_count += state.event_count;
    }

    const rendered = try std.fmt.allocPrint(
        allocator,
        "sessions={d}\nopen_sessions={d}\npending_bytes={d}\nevents={d}\nroot={s}\n",
        .{ session_count, open_count, pending_bytes, event_count, root_dir },
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
    try appendEventLine(name, tick, "type=open\n", .{});
    state.event_count +%= 1;
    try saveState(name, state, tick);
}

pub fn closeSession(name: []const u8, tick: u64) Error!void {
    var state = try loadStateBounded(name);
    state.open = false;
    state.updated_tick = tick;
    try appendEventLine(name, tick, "type=close\n", .{});
    state.event_count +%= 1;
    try saveState(name, state, tick);
}

pub fn recordCommand(
    allocator: std.mem.Allocator,
    name: []const u8,
    command: []const u8,
    stdin: []const u8,
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
    tick: u64,
) Error!void {
    try recordInteraction(allocator, name, .send, command, null, stdin, exit_code, stdout, stderr, tick);
}

pub fn recordShell(
    allocator: std.mem.Allocator,
    name: []const u8,
    script: []const u8,
    stdin: []const u8,
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
    tick: u64,
) Error!void {
    try recordInteraction(allocator, name, .shell, "shell-run", script, stdin, exit_code, stdout, stderr, tick);
}

const InteractionKind = enum {
    send,
    shell,
};

fn recordInteraction(
    allocator: std.mem.Allocator,
    name: []const u8,
    interaction: InteractionKind,
    command: []const u8,
    script: ?[]const u8,
    stdin: []const u8,
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
    tick: u64,
) Error!void {
    var state = try loadState(allocator, name);
    if (!state.open) return error.TtySessionNotFound;

    const transcript_entry = try renderTranscriptEntryAlloc(allocator, command, script, stdin, exit_code, stdout, stderr);
    defer allocator.free(transcript_entry);

    if (script) |script_bytes| {
        try appendSessionFile(allocator, name, .input, "shell-run\n", max_input_bytes, tick);
        try appendSessionFile(allocator, name, .input, script_bytes, max_input_bytes, tick);
        if (script_bytes.len == 0 or script_bytes[script_bytes.len - 1] != '\n') {
            try appendSessionFile(allocator, name, .input, "\n", max_input_bytes, tick);
        }
    } else {
        try appendSessionFile(allocator, name, .input, command, max_input_bytes, tick);
        try appendSessionFile(allocator, name, .input, "\n", max_input_bytes, tick);
    }
    try appendSessionFile(allocator, name, .stdout, stdout, max_stream_bytes, tick);
    try appendSessionFile(allocator, name, .stderr, stderr, max_stream_bytes, tick);
    try appendSessionFile(allocator, name, .transcript, transcript_entry, max_transcript_bytes, tick);
    switch (interaction) {
        .send => try appendEventLine(
            name,
            tick,
            "type=send exit={d} stdin_bytes={d} stdout_bytes={d} stderr_bytes={d}\n",
            .{ exit_code, stdin.len, stdout.len, stderr.len },
        ),
        .shell => try appendEventLine(
            name,
            tick,
            "type=shell exit={d} script_bytes={d} stdin_bytes={d} stdout_bytes={d} stderr_bytes={d}\n",
            .{ exit_code, script.?.len, stdin.len, stdout.len, stderr.len },
        ),
    }

    state.command_count +%= 1;
    state.input_bytes +%= @as(u32, @intCast(if (script) |script_bytes| script_bytes.len else command.len));
    state.stdout_bytes +%= @as(u32, @intCast(stdout.len));
    state.stderr_bytes +%= @as(u32, @intCast(stderr.len));
    state.event_count +%= 1;
    state.last_exit_code = exit_code;
    state.updated_tick = tick;
    try saveState(name, state, tick);
}

pub fn writePendingInput(
    allocator: std.mem.Allocator,
    name: []const u8,
    input: []const u8,
    tick: u64,
) Error!void {
    var state = try loadState(allocator, name);
    if (!state.open) return error.TtySessionNotFound;
    if (input.len == 0) return;

    try appendSessionFile(allocator, name, .pending, input, max_pending_bytes, tick);
    try appendEventLine(name, tick, "type=write bytes={d}\n", .{input.len});

    state.pending_input_bytes +%= @as(u32, @intCast(input.len));
    state.event_count +%= 1;
    state.updated_tick = tick;
    try saveState(name, state, tick);
}

pub fn clearPendingInput(allocator: std.mem.Allocator, name: []const u8, tick: u64) Error!void {
    var state = try loadState(allocator, name);
    if (!state.open) return error.TtySessionNotFound;

    const cleared_bytes = state.pending_input_bytes;
    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try sessionFilePath(name, .pending, &path_buf);
    try filesystem.writeFile(path, "", tick);
    try appendEventLine(name, tick, "type=clear bytes={d}\n", .{cleared_bytes});

    state.pending_input_bytes = 0;
    state.event_count +%= 1;
    state.updated_tick = tick;
    try saveState(name, state, tick);
}

pub fn takePendingInputAlloc(
    allocator: std.mem.Allocator,
    name: []const u8,
    max_bytes: usize,
    tick: u64,
) Error![]u8 {
    var state = try loadState(allocator, name);
    if (!state.open) return error.TtySessionNotFound;

    const pending = try readSessionFileAlloc(allocator, name, .pending, max_bytes);
    errdefer allocator.free(pending);

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try sessionFilePath(name, .pending, &path_buf);
    try filesystem.writeFile(path, "", tick);

    state.pending_input_bytes = 0;
    state.updated_tick = tick;
    try saveState(name, state, tick);
    return pending;
}

pub fn infoAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    const state = try loadState(allocator, name);

    var state_path_buf: [filesystem.max_path_len]u8 = undefined;
    var input_path_buf: [filesystem.max_path_len]u8 = undefined;
    var pending_path_buf: [filesystem.max_path_len]u8 = undefined;
    var stdout_path_buf: [filesystem.max_path_len]u8 = undefined;
    var stderr_path_buf: [filesystem.max_path_len]u8 = undefined;
    var events_path_buf: [filesystem.max_path_len]u8 = undefined;
    var transcript_path_buf: [filesystem.max_path_len]u8 = undefined;

    const rendered = try std.fmt.allocPrint(
        allocator,
        "name={s}\nopen={d}\ncommand_count={d}\nlast_exit_code={d}\ninput_bytes={d}\nstdout_bytes={d}\nstderr_bytes={d}\npending_input_bytes={d}\nevent_count={d}\nupdated_tick={d}\nstate_path={s}\ninput_path={s}\npending_path={s}\nstdout_path={s}\nstderr_path={s}\nevents_path={s}\ntranscript_path={s}\n",
        .{
            name,
            if (state.open) @as(u8, 1) else @as(u8, 0),
            state.command_count,
            state.last_exit_code,
            state.input_bytes,
            state.stdout_bytes,
            state.stderr_bytes,
            state.pending_input_bytes,
            state.event_count,
            state.updated_tick,
            try sessionFilePath(name, .info, &state_path_buf),
            try sessionFilePath(name, .input, &input_path_buf),
            try sessionFilePath(name, .pending, &pending_path_buf),
            try sessionFilePath(name, .stdout, &stdout_path_buf),
            try sessionFilePath(name, .stderr, &stderr_path_buf),
            try sessionFilePath(name, .events, &events_path_buf),
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

pub fn pendingAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    return readSessionFileAlloc(allocator, name, .pending, max_bytes);
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

pub fn eventsAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    return readSessionFileAlloc(allocator, name, .events, max_bytes);
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
        } else if (std.mem.eql(u8, key, "pending_input_bytes")) {
            state.pending_input_bytes = std.fmt.parseUnsigned(u32, value, 10) catch 0;
        } else if (std.mem.eql(u8, key, "event_count")) {
            state.event_count = std.fmt.parseUnsigned(u32, value, 10) catch 0;
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
        "open={d}\ncommand_count={d}\nlast_exit_code={d}\ninput_bytes={d}\nstdout_bytes={d}\nstderr_bytes={d}\npending_input_bytes={d}\nevent_count={d}\nupdated_tick={d}\n",
        .{
            if (state.open) @as(u8, 1) else @as(u8, 0),
            state.command_count,
            state.last_exit_code,
            state.input_bytes,
            state.stdout_bytes,
            state.stderr_bytes,
            state.pending_input_bytes,
            state.event_count,
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

fn appendSessionFileBounded(
    name: []const u8,
    file_kind: SessionFileKind,
    suffix: []const u8,
    max_bytes: usize,
    tick: u64,
) Error!void {
    if (suffix.len == 0) return;

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try sessionFilePath(name, file_kind, &path_buf);

    var existing_buf: [max_session_file_bytes]u8 = undefined;
    const existing = filesystem.readFile(path, &existing_buf) catch |err| switch (err) {
        error.FileNotFound => &[_]u8{},
        else => return err,
    };
    if (existing.len + suffix.len > max_bytes or existing.len + suffix.len > max_session_file_bytes) {
        return error.ResponseTooLarge;
    }

    var combined_buf: [max_session_file_bytes]u8 = undefined;
    @memcpy(combined_buf[0..existing.len], existing);
    @memcpy(combined_buf[existing.len .. existing.len + suffix.len], suffix);
    try filesystem.writeFile(path, combined_buf[0 .. existing.len + suffix.len], tick);
}

fn appendEventLine(name: []const u8, tick: u64, comptime fmt: []const u8, args: anytype) Error!void {
    var line_buf: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&line_buf, "tick={d} " ++ fmt, .{tick} ++ args) catch return error.ResponseTooLarge;
    try appendSessionFileBounded(name, .events, line, max_events_bytes, tick);
}

fn renderTranscriptEntryAlloc(
    allocator: std.mem.Allocator,
    command: []const u8,
    script: ?[]const u8,
    stdin: []const u8,
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
) Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, "$ ");
    try out.appendSlice(allocator, command);
    try out.appendSlice(allocator, "\n");
    if (script) |script_bytes| {
        try out.appendSlice(allocator, "script:\n");
        try out.appendSlice(allocator, script_bytes);
        if (script_bytes.len == 0 or script_bytes[script_bytes.len - 1] != '\n') try out.append(allocator, '\n');
    }
    const exit_line = try std.fmt.allocPrint(allocator, "exit={d}\n", .{exit_code});
    defer allocator.free(exit_line);
    try out.appendSlice(allocator, exit_line);
    if (stdin.len != 0) {
        try out.appendSlice(allocator, "stdin:\n");
        try out.appendSlice(allocator, stdin);
        if (stdin[stdin.len - 1] != '\n') try out.append(allocator, '\n');
    }
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
        .pending => "pending.log",
        .stdout => "stdout.log",
        .stderr => "stderr.log",
        .events => "events.log",
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
    try writePendingInput(std.testing.allocator, "demo", "queued-tty\n", 2);

    const pending_before = try pendingAlloc(std.testing.allocator, "demo", 128);
    defer std.testing.allocator.free(pending_before);
    try std.testing.expectEqualStrings("queued-tty\n", pending_before);

    const stdin_bytes = try takePendingInputAlloc(std.testing.allocator, "demo", 128, 3);
    defer std.testing.allocator.free(stdin_bytes);
    try std.testing.expectEqualStrings("queued-tty\n", stdin_bytes);
    try recordCommand(std.testing.allocator, "demo", "cat", stdin_bytes, 0, "queued-tty\n", "", 4);

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
    try std.testing.expect(std.mem.indexOf(u8, info, "pending_input_bytes=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "event_count=3") != null);

    const input = try inputAlloc(std.testing.allocator, "demo", 128);
    defer std.testing.allocator.free(input);
    try std.testing.expectEqualStrings("cat\n", input);

    const pending_after = try pendingAlloc(std.testing.allocator, "demo", 128);
    defer std.testing.allocator.free(pending_after);
    try std.testing.expectEqualStrings("", pending_after);

    const stdout = try stdoutAlloc(std.testing.allocator, "demo", 128);
    defer std.testing.allocator.free(stdout);
    try std.testing.expectEqualStrings("queued-tty\n", stdout);

    const events = try eventsAlloc(std.testing.allocator, "demo", 512);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "type=open") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "type=write bytes=11") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "type=send exit=0 stdin_bytes=11 stdout_bytes=11 stderr_bytes=0") != null);

    const transcript = try transcriptAlloc(std.testing.allocator, "demo", 512);
    defer std.testing.allocator.free(transcript);
    try std.testing.expect(std.mem.indexOf(u8, transcript, "$ cat\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, transcript, "stdin:\nqueued-tty\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, transcript, "stdout:\nqueued-tty\n") != null);

    try closeSession("demo", 5);
    const closed_info = try infoAlloc(std.testing.allocator, "demo", 512);
    defer std.testing.allocator.free(closed_info);
    try std.testing.expect(std.mem.indexOf(u8, closed_info, "open=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, closed_info, "event_count=4") != null);
}

test "tty runtime records bounded shell receipts" {
    filesystem.resetForTest();
    try filesystem.init();

    try openSession("shell", 1);
    try writePendingInput(std.testing.allocator, "shell", "tty-shell\n", 2);

    const stdin_bytes = try takePendingInputAlloc(std.testing.allocator, "shell", 128, 3);
    defer std.testing.allocator.free(stdin_bytes);
    const script = "cat > /tmp/tty-shell.txt; cat";
    try recordShell(std.testing.allocator, "shell", script, stdin_bytes, 0, "tty-shell\n", "", 4);

    const input = try inputAlloc(std.testing.allocator, "shell", 128);
    defer std.testing.allocator.free(input);
    try std.testing.expect(std.mem.indexOf(u8, input, "shell-run\ncat > /tmp/tty-shell.txt; cat\n") != null);

    const events = try eventsAlloc(std.testing.allocator, "shell", 512);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "type=shell exit=0 script_bytes=29 stdin_bytes=10 stdout_bytes=10 stderr_bytes=0") != null);

    const transcript = try transcriptAlloc(std.testing.allocator, "shell", 512);
    defer std.testing.allocator.free(transcript);
    try std.testing.expect(std.mem.indexOf(u8, transcript, "$ shell-run\nscript:\ncat > /tmp/tty-shell.txt; cat\nexit=0\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, transcript, "stdout:\ntty-shell\n") != null);
}
