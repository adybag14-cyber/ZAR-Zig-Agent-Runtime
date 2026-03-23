// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");
const app_runtime = @import("app_runtime.zig");
const filesystem = @import("filesystem.zig");
const package_store = @import("package_store.zig");
const runtime_bridge = @import("runtime_bridge.zig");
const storage_backend_registry = @import("storage_backend_registry.zig");
const storage_registry = @import("storage_registry.zig");
const tty_runtime = @import("tty_runtime.zig");
const trust_store = @import("trust_store.zig");
const workspace_runtime = @import("workspace_runtime.zig");
const display_profile_store = @import("display_profile_store.zig");
const display_output = @import("display_output.zig");
const framebuffer_console = @import("framebuffer_console.zig");
const pal_framebuffer = @import("../pal/framebuffer.zig");
const vga_text_console = @import("vga_text_console.zig");
const storage_backend = @import("storage_backend.zig");
const tool_layout = @import("tool_layout.zig");
const virtio_gpu = @import("virtio_gpu.zig");

pub const Error = filesystem.Error || trust_store.Error || app_runtime.Error || workspace_runtime.Error || display_profile_store.Error || storage_backend.Error || tty_runtime.Error || std.mem.Allocator.Error || error{
    MissingCommand,
    MissingPath,
    StreamTooLong,
    InvalidQuotedArgument,
    InvalidRedirection,
    ScriptDepthExceeded,
    ShellCommandLimitExceeded,
    UnsupportedPattern,
    NoMatches,
    DisplayConnectorMismatch,
    DisplayInterfaceMismatch,
    DisplayOutputNotFound,
    DisplayOutputUnsupportedMode,
};

const max_script_depth: usize = 4;
const max_shell_command_count: usize = 64;
const max_shell_glob_segments: usize = 16;

pub const Result = struct {
    exit_code: u8,
    stdout: []u8,
    stderr: []u8,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

const OutputBuffer = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(u8),
    limit: usize,
    mirror: bool,

    fn init(allocator: std.mem.Allocator, limit: usize, mirror: bool) OutputBuffer {
        return .{
            .allocator = allocator,
            .list = .empty,
            .limit = limit,
            .mirror = mirror,
        };
    }

    fn deinit(self: *OutputBuffer) void {
        self.list.deinit(self.allocator);
    }

    fn appendSlice(self: *OutputBuffer, bytes: []const u8) !void {
        if (self.list.items.len + bytes.len > self.limit) return error.StreamTooLong;
        try self.list.appendSlice(self.allocator, bytes);
        if (self.mirror and bytes.len > 0) vga_text_console.write(bytes);
    }

    fn appendByte(self: *OutputBuffer, byte: u8) !void {
        var single = [1]u8{byte};
        try self.appendSlice(single[0..]);
    }

    fn appendLine(self: *OutputBuffer, line: []const u8) !void {
        try self.appendSlice(line);
        try self.appendByte('\n');
    }

    fn appendFmt(self: *OutputBuffer, comptime fmt: []const u8, args: anytype) !void {
        const rendered = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(rendered);
        try self.appendSlice(rendered);
    }

    fn toOwnedSlice(self: *OutputBuffer) ![]u8 {
        return self.list.toOwnedSlice(self.allocator);
    }
};

const ParsedCommand = struct {
    name: []const u8,
    rest: []const u8,
};

const ParsedArg = struct {
    arg: []const u8,
    rest: []const u8,
};

const ParsedShellLine = struct {
    command: []const u8,
    input_path: ?[]const u8 = null,
    redirect_path: ?[]const u8 = null,
    redirect_stream: RedirectStream = .stdout,
    append: bool = false,
};

const RedirectStream = enum {
    stdout,
    stderr,
};

const ListingChild = struct {
    name: []const u8,
    kind: std.Io.File.Kind,
};

pub fn runCapture(
    allocator: std.mem.Allocator,
    command: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
) Error!Result {
    return runCaptureWithMirror(allocator, command, stdout_limit, stderr_limit, true);
}

pub fn runCaptureSilent(
    allocator: std.mem.Allocator,
    command: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
) Error!Result {
    return runCaptureWithMirror(allocator, command, stdout_limit, stderr_limit, false);
}

pub fn runCaptureSilentWithInput(
    allocator: std.mem.Allocator,
    command: []const u8,
    stdin_content: ?[]const u8,
    stdout_limit: usize,
    stderr_limit: usize,
) Error!Result {
    return runCaptureWithMirrorAndInput(allocator, command, stdin_content, stdout_limit, stderr_limit, false);
}

pub fn runShellCaptureSilentWithInput(
    allocator: std.mem.Allocator,
    script: []const u8,
    stdin_content: ?[]const u8,
    stdout_limit: usize,
    stderr_limit: usize,
) Error!Result {
    var stdout_buffer = OutputBuffer.init(allocator, stdout_limit, false);
    errdefer stdout_buffer.deinit();
    var stderr_buffer = OutputBuffer.init(allocator, stderr_limit, false);
    errdefer stderr_buffer.deinit();
    var exit_code: u8 = 0;
    try filesystem.init();

    executeScriptContents(script, "shell-run", &stdout_buffer, &stderr_buffer, &exit_code, stdin_content, allocator, 0) catch |err| {
        exit_code = 1;
        try stderr_buffer.appendFmt("{s}\n", .{@errorName(err)});
    };

    return .{
        .exit_code = exit_code,
        .stdout = try stdout_buffer.toOwnedSlice(),
        .stderr = try stderr_buffer.toOwnedSlice(),
    };
}

pub fn runTtyShellCapture(
    allocator: std.mem.Allocator,
    session_name: []const u8,
    script: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
) Error!Result {
    const pending_limit = @max(stdout_limit, stderr_limit);
    const pending_input = tty_runtime.takePendingInputAlloc(allocator, session_name, pending_limit, 0) catch |err| return err;
    defer allocator.free(pending_input);
    const tty_stdin: ?[]const u8 = if (pending_input.len == 0) null else pending_input;

    var result = try runShellCaptureSilentWithInput(allocator, script, tty_stdin, stdout_limit, stderr_limit);
    tty_runtime.recordShell(allocator, session_name, script, tty_stdin orelse "", result.exit_code, result.stdout, result.stderr, 0) catch |err| {
        result.deinit(allocator);
        return err;
    };
    return result;
}

fn runCaptureWithMirror(
    allocator: std.mem.Allocator,
    command: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    mirror: bool,
) Error!Result {
    return runCaptureWithMirrorAndInput(allocator, command, null, stdout_limit, stderr_limit, mirror);
}

fn runCaptureWithMirrorAndInput(
    allocator: std.mem.Allocator,
    command: []const u8,
    stdin_content: ?[]const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    mirror: bool,
) Error!Result {
    var stdout_buffer = OutputBuffer.init(allocator, stdout_limit, mirror);
    errdefer stdout_buffer.deinit();
    var stderr_buffer = OutputBuffer.init(allocator, stderr_limit, mirror);
    errdefer stderr_buffer.deinit();
    var exit_code: u8 = 0;
    try filesystem.init();

    if (shouldBypassDirectShellLineParsing(command)) {
        const parsed = parseCommand(command) catch |err| {
            exit_code = 2;
            try writeCommandError(&stderr_buffer, err, "command");
            return .{
                .exit_code = exit_code,
                .stdout = try stdout_buffer.toOwnedSlice(),
                .stderr = try stderr_buffer.toOwnedSlice(),
            };
        };
        execute(parsed, &stdout_buffer, &stderr_buffer, &exit_code, stdin_content, allocator, 1) catch |err| {
            exit_code = 1;
            try stderr_buffer.appendFmt("{s}\n", .{@errorName(err)});
        };
    } else {
        executeCommandLine(command, "command", &stdout_buffer, &stderr_buffer, &exit_code, stdin_content, allocator, 0) catch |err| {
            exit_code = 1;
            try stderr_buffer.appendFmt("{s}\n", .{@errorName(err)});
        };
    }

    return .{
        .exit_code = exit_code,
        .stdout = try stdout_buffer.toOwnedSlice(),
        .stderr = try stderr_buffer.toOwnedSlice(),
    };
}

fn shouldBypassDirectShellLineParsing(command: []const u8) bool {
    const parsed = parseCommand(command) catch return false;
    return std.ascii.eqlIgnoreCase(parsed.name, "shell-run") or
        std.ascii.eqlIgnoreCase(parsed.name, "tty-send") or
        std.ascii.eqlIgnoreCase(parsed.name, "tty-shell");
}

fn executeCommandLine(
    line: []const u8,
    operation: []const u8,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    stdin_content: ?[]const u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    const parsed_line = parseShellLine(line) catch |err| {
        exit_code.* = 2;
        try writeCommandError(stderr_buffer, err, operation);
        return;
    };
    const command_text = normalizeShellCommandTextAlloc(allocator, parsed_line.command) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };
    defer allocator.free(command_text);

    const parsed = parseCommand(command_text) catch |err| {
        exit_code.* = 2;
        try writeCommandError(stderr_buffer, err, operation);
        return;
    };

    var command_stdin_content: ?[]u8 = null;
    defer if (command_stdin_content) |bytes| allocator.free(bytes);
    if (parsed_line.input_path) |input_path_raw| {
        const input_path = unescapeShellTextAlloc(allocator, input_path_raw) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
            return;
        };
        defer allocator.free(input_path);

        const input_limit = @max(stdout_buffer.limit, stderr_buffer.limit);
        command_stdin_content = filesystem.readFileAlloc(allocator, input_path, input_limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
            return;
        };
    }

    if (parsed_line.redirect_path) |redirect_path_raw| {
        const redirect_path = unescapeShellTextAlloc(allocator, redirect_path_raw) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
            return;
        };
        defer allocator.free(redirect_path);

        try executeWithRedirection(
            parsed,
            parsed_line.redirect_stream,
            redirect_path,
            parsed_line.append,
            operation,
            stdout_buffer,
            stderr_buffer,
            exit_code,
            command_stdin_content orelse stdin_content,
            allocator,
            depth + 1,
        );
        return;
    }

    try execute(parsed, stdout_buffer, stderr_buffer, exit_code, command_stdin_content orelse stdin_content, allocator, depth + 1);
}

fn execute(
    parsed: ParsedCommand,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    stdin_content: ?[]const u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    if (depth > max_script_depth) return error.ScriptDepthExceeded;

    if (std.ascii.eqlIgnoreCase(parsed.name, "help")) {
        try stdout_buffer.appendLine("OpenClaw bare-metal builtins: help, echo, cat, write-file, mkdir, stat, ls, shell-expand, shell-run, tty-list, tty-open, tty-info, tty-read, tty-pending, tty-events, tty-stdout, tty-stderr, tty-write, tty-send, tty-shell, tty-clear, tty-close, storage-backends, storage-filesystems, storage-backend-info, storage-backend-select, storage-partitions, storage-partition-select, mount-list, mount-info, mount-bind, mount-remove, package-info, package-verify, package-app, package-display, package-ls, package-cat, package-delete, package-release-list, package-release-info, package-release-save, package-release-activate, package-release-delete, package-release-prune, package-release-channel-list, package-release-channel-info, package-release-channel-set, package-release-channel-activate, app-list, app-info, app-state, app-history, app-stdout, app-stderr, app-trust, app-connector, app-plan-list, app-plan-info, app-plan-active, app-plan-save, app-plan-apply, app-plan-delete, app-suite-list, app-suite-info, app-suite-save, app-suite-apply, app-suite-run, app-suite-delete, app-suite-release-list, app-suite-release-info, app-suite-release-save, app-suite-release-activate, app-suite-release-delete, app-suite-release-prune, app-suite-release-channel-list, app-suite-release-channel-info, app-suite-release-channel-set, app-suite-release-channel-activate, app-delete, app-autorun-list, app-autorun-add, app-autorun-remove, app-autorun-run, workspace-plan-list, workspace-plan-info, workspace-plan-active, workspace-plan-save, workspace-plan-apply, workspace-plan-delete, workspace-plan-release-list, workspace-plan-release-info, workspace-plan-release-save, workspace-plan-release-activate, workspace-plan-release-delete, workspace-plan-release-prune, workspace-suite-list, workspace-suite-info, workspace-suite-save, workspace-suite-apply, workspace-suite-run, workspace-suite-delete, workspace-suite-release-list, workspace-suite-release-info, workspace-suite-release-save, workspace-suite-release-activate, workspace-suite-release-delete, workspace-suite-release-prune, workspace-suite-release-channel-list, workspace-suite-release-channel-info, workspace-suite-release-channel-set, workspace-suite-release-channel-activate, workspace-list, workspace-info, workspace-save, workspace-apply, workspace-run, workspace-state, workspace-history, workspace-stdout, workspace-stderr, workspace-delete, workspace-release-list, workspace-release-info, workspace-release-save, workspace-release-activate, workspace-release-delete, workspace-release-prune, workspace-release-channel-list, workspace-release-channel-info, workspace-release-channel-set, workspace-release-channel-activate, workspace-autorun-list, workspace-autorun-add, workspace-autorun-remove, workspace-autorun-run, trust-list, trust-info, trust-active, trust-select, trust-delete, runtime-snapshot, runtime-sessions, runtime-session, display-info, display-outputs, display-output, display-output-detail, display-output-capabilities, display-output-modes, display-interface-detail, display-interface-capabilities, display-interface-modes, display-modes, display-set, display-activate, display-activate-preferred, display-activate-interface, display-activate-interface-preferred, display-interface-set, display-interface-activate-mode, display-activate-output, display-activate-output-preferred, display-output-set, display-output-activate-mode, display-profile-list, display-profile-info, display-profile-active, display-profile-save, display-profile-apply, display-profile-delete, run-script, run-package, app-run");
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "echo")) {
        if (stdin_content != null) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: echo <content>");
            return;
        }
        try stdout_buffer.appendLine(parsed.rest);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "mkdir")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "mkdir <path>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: mkdir <path>");
            return;
        }
        const path = unescapeShellTextAlloc(allocator, arg.arg) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("mkdir failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(path);
        filesystem.createDirPath(path) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("mkdir failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("created {s}\n", .{path});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "cat")) {
        if (stdin_content) |bytes| {
            if (std.mem.trim(u8, parsed.rest, " \t\r\n").len != 0) {
                exit_code.* = 2;
                try stderr_buffer.appendLine("usage: cat <path>");
                return;
            }
            try stdout_buffer.appendSlice(bytes);
            return;
        }
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "cat <path>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: cat <path>");
            return;
        }
        const path = unescapeShellTextAlloc(allocator, arg.arg) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("cat failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(path);
        const content = filesystem.readFileAlloc(allocator, path, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("cat failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(content);
        try stdout_buffer.appendSlice(content);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "write-file")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "write-file <path> <content>");
            return;
        };
        const content = if (stdin_content) |bytes| blk: {
            if (arg.rest.len != 0) {
                exit_code.* = 2;
                try stderr_buffer.appendLine("usage: write-file <path> <content>");
                return;
            }
            break :blk bytes;
        } else arg.rest;
        if (content.len == 0 and stdin_content == null) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: write-file <path> <content>");
            return;
        }
        const path = unescapeShellTextAlloc(allocator, arg.arg) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("write-file failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(path);
        ensureParentDirectory(path) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("write-file failed: {s}\n", .{@errorName(err)});
            return;
        };
        filesystem.writeFile(path, content, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("write-file failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("wrote {d} bytes to {s}\n", .{ content.len, path });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "stat")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "stat <path>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: stat <path>");
            return;
        }
        const path = unescapeShellTextAlloc(allocator, arg.arg) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("stat failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(path);
        const stat = filesystem.statSummary(path) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("stat failed: {s}\n", .{@errorName(err)});
            return;
        };
        const kind = switch (stat.kind) {
            .directory => "directory",
            .file => "file",
            else => "unknown",
        };
        try stdout_buffer.appendFmt("path={s} kind={s} size={d}\n", .{ path, kind, stat.size });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "ls")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "ls <path>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: ls <path>");
            return;
        }
        const path = unescapeShellTextAlloc(allocator, arg.arg) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("ls failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(path);
        const listing = filesystem.listDirectoryAlloc(allocator, path, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("ls failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "shell-expand")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "shell-expand <pattern>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: shell-expand <pattern>");
            return;
        }
        const pattern = unescapeShellTextAlloc(allocator, arg.arg) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("shell-expand failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(pattern);
        const expanded = expandShellPatternAlloc(allocator, pattern, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("shell-expand failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(expanded);
        try stdout_buffer.appendSlice(expanded);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "shell-run")) {
        const trimmed_script = std.mem.trim(u8, parsed.rest, " \t\r\n");
        if (stdin_content) |bytes| {
            if (trimmed_script.len != 0) {
                exit_code.* = 2;
                try stderr_buffer.appendLine("usage: shell-run <command[;command...]> or shell-run < <path>");
                return;
            }
            try executeScriptContents(bytes, "shell-run", stdout_buffer, stderr_buffer, exit_code, null, allocator, depth);
            return;
        }
        if (trimmed_script.len == 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: shell-run <command[;command...]>");
            return;
        }
        try executeScriptContents(parsed.rest, "shell-run", stdout_buffer, stderr_buffer, exit_code, null, allocator, depth);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-list")) {
        if (std.mem.trim(u8, parsed.rest, " \t\r\n").len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-list");
            return;
        }
        const rendered = tty_runtime.listSessionsAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(rendered);
        try stdout_buffer.appendSlice(rendered);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-open")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-open <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-open <name>");
            return;
        }
        tty_runtime.openSession(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-open failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("tty opened {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-info")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-info <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-info <name>");
            return;
        }
        const rendered = tty_runtime.infoAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(rendered);
        try stdout_buffer.appendSlice(rendered);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-read")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-read <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-read <name>");
            return;
        }
        const rendered = tty_runtime.transcriptAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-read failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(rendered);
        try stdout_buffer.appendSlice(rendered);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-pending")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-pending <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-pending <name>");
            return;
        }
        const rendered = tty_runtime.pendingAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-pending failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(rendered);
        try stdout_buffer.appendSlice(rendered);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-events")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-events <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-events <name>");
            return;
        }
        const rendered = tty_runtime.eventsAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-events failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(rendered);
        try stdout_buffer.appendSlice(rendered);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-stdout")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-stdout <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-stdout <name>");
            return;
        }
        const rendered = tty_runtime.stdoutAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-stdout failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(rendered);
        try stdout_buffer.appendSlice(rendered);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-stderr")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-stderr <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-stderr <name>");
            return;
        }
        const rendered = tty_runtime.stderrAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-stderr failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(rendered);
        try stdout_buffer.appendSlice(rendered);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-write")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-write <name> <content>");
            return;
        };
        const content = arg.rest;
        if (content.len == 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-write <name> <content>");
            return;
        }
        tty_runtime.writePendingInput(allocator, arg.arg, content, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-write failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("tty queued {s} {d} bytes\n", .{ arg.arg, content.len });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-send")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-send <name> <command>");
            return;
        };
        const command = std.mem.trim(u8, arg.rest, " \t\r\n");
        if (command.len == 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-send <name> <command>");
            return;
        }
        const pending_input = tty_runtime.takePendingInputAlloc(allocator, arg.arg, stdout_buffer.limit, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-send failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(pending_input);
        const tty_stdin: ?[]const u8 = if (pending_input.len == 0) null else pending_input;

        var result = runCaptureSilentWithInput(allocator, command, tty_stdin, stdout_buffer.limit, stderr_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-send failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer result.deinit(allocator);

        tty_runtime.recordCommand(allocator, arg.arg, command, tty_stdin orelse "", result.exit_code, result.stdout, result.stderr, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-send failed: {s}\n", .{@errorName(err)});
            return;
        };

        exit_code.* = result.exit_code;
        try stdout_buffer.appendSlice(result.stdout);
        try stderr_buffer.appendSlice(result.stderr);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-shell")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-shell <name> <script>");
            return;
        };
        const script = std.mem.trim(u8, arg.rest, " \t\r\n");
        if (script.len == 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-shell <name> <script>");
            return;
        }

        var result = runTtyShellCapture(allocator, arg.arg, script, stdout_buffer.limit, stderr_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-shell failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer result.deinit(allocator);

        exit_code.* = result.exit_code;
        try stdout_buffer.appendSlice(result.stdout);
        try stderr_buffer.appendSlice(result.stderr);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-clear")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-clear <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-clear <name>");
            return;
        }
        tty_runtime.clearPendingInput(allocator, arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-clear failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("tty cleared {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "tty-close")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "tty-close <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: tty-close <name>");
            return;
        }
        tty_runtime.closeSession(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("tty-close failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("tty closed {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "storage-backends")) {
        if (std.mem.trim(u8, parsed.rest, " \t\r\n").len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: storage-backends");
            return;
        }
        const rendered = storage_backend_registry.renderAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("storage-backends failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(rendered);
        try stdout_buffer.appendSlice(rendered);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "storage-filesystems")) {
        if (std.mem.trim(u8, parsed.rest, " \t\r\n").len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: storage-filesystems");
            return;
        }
        const rendered = storage_backend_registry.renderFilesystemSupportAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("storage-filesystems failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(rendered);
        try stdout_buffer.appendSlice(rendered);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "storage-backend-info")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "storage-backend-info <backend>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: storage-backend-info <backend>");
            return;
        }
        const backend = parseStorageBackendArg(arg.arg) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: storage-backend-info <backend>");
            return;
        };
        appendStorageBackendInfo(stdout_buffer, backend) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("storage-backend-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "storage-backend-select")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "storage-backend-select <backend>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: storage-backend-select <backend>");
            return;
        }
        const backend = parseStorageBackendArg(arg.arg) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: storage-backend-select <backend>");
            return;
        };
        storage_backend.selectBackendById(backend) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("storage-backend-select failed: {s}\n", .{@errorName(err)});
            return;
        };
        tool_layout.invalidateForBackendChange();
        filesystem.invalidateForBackendChange();
        try stdout_buffer.appendFmt("storage backend selected {s}\n", .{storage_registry.backendName(backend)});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "storage-partitions")) {
        if (std.mem.trim(u8, parsed.rest, " \t\r\n").len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: storage-partitions");
            return;
        }
        appendStoragePartitions(stdout_buffer) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("storage-partitions failed: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "storage-partition-select")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "storage-partition-select <index>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: storage-partition-select <index>");
            return;
        }
        const index = std.fmt.parseUnsigned(u8, arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: storage-partition-select <index>");
            return;
        };
        storage_backend.selectPartition(index) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("storage-partition-select failed: {s}\n", .{@errorName(err)});
            return;
        };
        tool_layout.invalidateForBackendChange();
        filesystem.invalidateForBackendChange();
        try stdout_buffer.appendFmt("storage partition selected {d}\n", .{index});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "mount-list")) {
        if (std.mem.trim(u8, parsed.rest, " \t\r\n").len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: mount-list");
            return;
        }
        appendMountList(stdout_buffer) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("mount-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "mount-info")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "mount-info <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: mount-info <name>");
            return;
        }
        appendMountInfo(stdout_buffer, arg.arg) catch |err| {
            exit_code.* = if (err == error.FileNotFound) 1 else 1;
            try stderr_buffer.appendFmt("mount-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "mount-bind")) {
        const name_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "mount-bind <name> <target>");
            return;
        };
        const target_arg = parseFirstArg(name_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "mount-bind <name> <target>");
            return;
        };
        if (target_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: mount-bind <name> <target>");
            return;
        }
        filesystem.bindMount(name_arg.arg, target_arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("mount-bind failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("mount bound {s} -> {s}\n", .{ name_arg.arg, target_arg.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "mount-remove")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "mount-remove <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: mount-remove <name>");
            return;
        }
        filesystem.removeMount(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("mount-remove failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("mount removed {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-info")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-info <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-info <name>");
            return;
        }
        const manifest = package_store.manifestAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(manifest);
        try stdout_buffer.appendSlice(manifest);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-verify")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-verify <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-verify <name>");
            return;
        }
        var verification = package_store.verifyPackageAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-verify failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer verification.deinit(allocator);

        if (verification.ok) {
            try stdout_buffer.appendSlice(verification.payload);
        } else {
            exit_code.* = 1;
            try stderr_buffer.appendSlice(verification.payload);
        }
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-app")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-app <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-app <name>");
            return;
        }
        const manifest = package_store.appManifestAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-app failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(manifest);
        try stdout_buffer.appendSlice(manifest);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-display")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-display <name> <width> <height>");
            return;
        };
        const width_arg = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-display <name> <width> <height>");
            return;
        };
        const height_arg = parseFirstArg(width_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-display <name> <width> <height>");
            return;
        };
        if (height_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-display <name> <width> <height>");
            return;
        }
        const width = std.fmt.parseInt(u16, width_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-display <name> <width> <height>");
            return;
        };
        const height = std.fmt.parseInt(u16, height_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-display <name> <width> <height>");
            return;
        };
        package_store.configureDisplayMode(package_name.arg, width, height, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-display failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("package display {s} {d}x{d}\n", .{ package_name.arg, width, height });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-ls")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-ls <name>");
            return;
        };
        if (package_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-ls <name>");
            return;
        }
        const listing = package_store.listPackageAssetsAlloc(allocator, package_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-ls failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-cat")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-cat <name> <relative-path>");
            return;
        };
        const relative_path = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-cat <name> <relative-path>");
            return;
        };
        if (relative_path.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-cat <name> <relative-path>");
            return;
        }
        const asset = package_store.readPackageAssetAlloc(allocator, package_name.arg, relative_path.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-cat failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(asset);
        try stdout_buffer.appendSlice(asset);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-delete")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-delete <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-delete <name>");
            return;
        }
        app_runtime.uninstallApp(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("package deleted {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-release-list")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-list <name>");
            return;
        };
        if (package_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-release-list <name>");
            return;
        }
        const listing = package_store.releaseListAlloc(allocator, package_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-release-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-release-info")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-info <name> <release>");
            return;
        };
        const release_name = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-info <name> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-release-info <name> <release>");
            return;
        }
        const info = package_store.releaseInfoAlloc(allocator, package_name.arg, release_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-release-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-release-save")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-save <name> <release>");
            return;
        };
        const release_name = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-save <name> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-release-save <name> <release>");
            return;
        }
        package_store.snapshotPackageRelease(package_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-release-save failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("package release saved {s} {s}\n", .{ package_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-release-activate")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-activate <name> <release>");
            return;
        };
        const release_name = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-activate <name> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-release-activate <name> <release>");
            return;
        }
        package_store.activatePackageRelease(package_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-release-activate failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("package release activated {s} {s}\n", .{ package_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-release-delete")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-delete <name> <release>");
            return;
        };
        const release_name = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-delete <name> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-release-delete <name> <release>");
            return;
        }
        package_store.deletePackageRelease(package_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-release-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("package release deleted {s} {s}\n", .{ package_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-release-prune")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-prune <name> <keep>");
            return;
        };
        const keep_arg = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-prune <name> <keep>");
            return;
        };
        if (keep_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-release-prune <name> <keep>");
            return;
        }
        const keep = std.fmt.parseInt(usize, keep_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-release-prune <name> <keep>");
            return;
        };
        const prune = package_store.prunePackageReleases(package_name.arg, keep, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-release-prune failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt(
            "package release pruned {s} keep={d} deleted={d} kept={d}\n",
            .{ package_name.arg, keep, prune.deleted_count, prune.kept_count },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-release-channel-list")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-channel-list <name>");
            return;
        };
        if (package_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-release-channel-list <name>");
            return;
        }
        const listing = package_store.channelListAlloc(allocator, package_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-release-channel-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-release-channel-info")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-channel-info <name> <channel>");
            return;
        };
        const channel_name = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-channel-info <name> <channel>");
            return;
        };
        if (channel_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-release-channel-info <name> <channel>");
            return;
        }
        const info = package_store.channelInfoAlloc(allocator, package_name.arg, channel_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-release-channel-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-release-channel-set")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-channel-set <name> <channel> <release>");
            return;
        };
        const channel_name = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-channel-set <name> <channel> <release>");
            return;
        };
        const release_name = parseFirstArg(channel_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-channel-set <name> <channel> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-release-channel-set <name> <channel> <release>");
            return;
        }
        package_store.setPackageReleaseChannel(package_name.arg, channel_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-release-channel-set failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("package release channel set {s} {s} {s}\n", .{ package_name.arg, channel_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "package-release-channel-activate")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-channel-activate <name> <channel>");
            return;
        };
        const channel_name = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "package-release-channel-activate <name> <channel>");
            return;
        };
        if (channel_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: package-release-channel-activate <name> <channel>");
            return;
        }
        package_store.activatePackageReleaseChannel(package_name.arg, channel_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("package-release-channel-activate failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("package release channel activated {s} {s}\n", .{ package_name.arg, channel_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-list")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-list");
            return;
        }
        const listing = app_runtime.listAppsAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-info")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-info <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-info <name>");
            return;
        }
        const info = app_runtime.infoAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-state")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-state <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-state <name>");
            return;
        }
        const state = app_runtime.stateAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-state failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(state);
        try stdout_buffer.appendSlice(state);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-history")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-history <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-history <name>");
            return;
        }
        const history = app_runtime.historyAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-history failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(history);
        try stdout_buffer.appendSlice(history);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-stdout")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-stdout <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-stdout <name>");
            return;
        }
        const stdout = app_runtime.stdoutAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-stdout failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(stdout);
        try stdout_buffer.appendSlice(stdout);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-stderr")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-stderr <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-stderr <name>");
            return;
        }
        const stderr = app_runtime.stderrAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-stderr failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(stderr);
        try stdout_buffer.appendSlice(stderr);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-trust")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-trust <name> <bundle|none>");
            return;
        };
        const bundle_arg = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-trust <name> <bundle|none>");
            return;
        };
        if (bundle_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-trust <name> <bundle|none>");
            return;
        }
        const trust_bundle = if (std.ascii.eqlIgnoreCase(bundle_arg.arg, "none")) "" else bundle_arg.arg;
        package_store.configureTrustBundle(package_name.arg, trust_bundle, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-trust failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app trust {s} {s}\n", .{ package_name.arg, if (trust_bundle.len == 0) "none" else trust_bundle });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-connector")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-connector <name> <connector>");
            return;
        };
        const connector_arg = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-connector <name> <connector>");
            return;
        };
        if (connector_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-connector <name> <connector>");
            return;
        }
        const connector_type = package_store.parseConnectorType(connector_arg.arg) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-connector <name> <connector>");
            return;
        };
        package_store.configureConnectorType(package_name.arg, connector_type, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-connector failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app connector {s} {s}\n", .{ package_name.arg, package_store.connectorNameFromType(connector_type) });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-plan-list")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-list <name>");
            return;
        };
        if (package_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-plan-list <name>");
            return;
        }
        const listing = app_runtime.planListAlloc(allocator, package_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-plan-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-plan-info")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-info <name> <plan>");
            return;
        };
        const plan_name = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-info <name> <plan>");
            return;
        };
        if (plan_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-plan-info <name> <plan>");
            return;
        }
        const info = app_runtime.planInfoAlloc(allocator, package_name.arg, plan_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-plan-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-plan-active")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-active <name>");
            return;
        };
        if (package_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-plan-active <name>");
            return;
        }
        const info = app_runtime.activePlanInfoAlloc(allocator, package_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-plan-active failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-plan-save")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        const plan_name = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        const release_name = parseFirstArg(plan_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        const trust_name = parseFirstArg(release_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        const connector_arg = parseFirstArg(trust_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        const width_arg = parseFirstArg(connector_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        const height_arg = parseFirstArg(width_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        const autorun_arg = parseFirstArg(height_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        if (autorun_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        }

        const connector_type = package_store.parseConnectorType(connector_arg.arg) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        const width = std.fmt.parseInt(u16, width_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        const height = std.fmt.parseInt(u16, height_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        const autorun = parseBoolArg(autorun_arg.arg) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-plan-save <name> <plan> <release|none> <trust|none> <connector> <width> <height> <autorun>");
            return;
        };
        const selected_release = if (std.ascii.eqlIgnoreCase(release_name.arg, "none")) "" else release_name.arg;
        const selected_trust = if (std.ascii.eqlIgnoreCase(trust_name.arg, "none")) "" else trust_name.arg;

        app_runtime.savePlan(package_name.arg, plan_name.arg, selected_release, selected_trust, connector_type, width, height, autorun, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-plan-save failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app plan saved {s} {s}\n", .{ package_name.arg, plan_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-plan-apply")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-apply <name> <plan>");
            return;
        };
        const plan_name = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-apply <name> <plan>");
            return;
        };
        if (plan_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-plan-apply <name> <plan>");
            return;
        }
        app_runtime.applyPlan(package_name.arg, plan_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-plan-apply failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app plan applied {s} {s}\n", .{ package_name.arg, plan_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-plan-delete")) {
        const package_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-delete <name> <plan>");
            return;
        };
        const plan_name = parseFirstArg(package_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-plan-delete <name> <plan>");
            return;
        };
        if (plan_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-plan-delete <name> <plan>");
            return;
        }
        app_runtime.deletePlan(package_name.arg, plan_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-plan-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app plan deleted {s} {s}\n", .{ package_name.arg, plan_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-list")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-list");
            return;
        }
        const listing = app_runtime.suiteListAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-info")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-info <suite>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-info <suite>");
            return;
        }
        const info = app_runtime.suiteInfoAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-save")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-save <suite> <package:plan> [package:plan...]");
            return;
        };
        if (suite_name.rest.len == 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-save <suite> <package:plan> [package:plan...]");
            return;
        }
        app_runtime.saveSuite(suite_name.arg, suite_name.rest, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-save failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app suite saved {s}\n", .{suite_name.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-apply")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-apply <suite>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-apply <suite>");
            return;
        }
        app_runtime.applySuite(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-apply failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app suite applied {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-run")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-run <suite>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-run <suite>");
            return;
        }
        try runSuiteProfiles(arg.arg, "app-suite-run", stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-delete")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-delete <suite>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-delete <suite>");
            return;
        }
        app_runtime.deleteSuite(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app suite deleted {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-release-list")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-list <suite>");
            return;
        };
        if (suite_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-release-list <suite>");
            return;
        }
        const listing = app_runtime.suiteReleaseListAlloc(allocator, suite_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-release-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-release-info")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-info <suite> <release>");
            return;
        };
        const release_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-info <suite> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-release-info <suite> <release>");
            return;
        }
        const info = app_runtime.suiteReleaseInfoAlloc(allocator, suite_name.arg, release_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-release-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-release-save")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-save <suite> <release>");
            return;
        };
        const release_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-save <suite> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-release-save <suite> <release>");
            return;
        }
        app_runtime.snapshotSuiteRelease(suite_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-release-save failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app suite release saved {s} {s}\n", .{ suite_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-release-activate")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-activate <suite> <release>");
            return;
        };
        const release_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-activate <suite> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-release-activate <suite> <release>");
            return;
        }
        app_runtime.activateSuiteRelease(suite_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-release-activate failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app suite release activated {s} {s}\n", .{ suite_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-release-delete")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-delete <suite> <release>");
            return;
        };
        const release_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-delete <suite> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-release-delete <suite> <release>");
            return;
        }
        app_runtime.deleteSuiteRelease(suite_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-release-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app suite release deleted {s} {s}\n", .{ suite_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-release-prune")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-prune <suite> <keep>");
            return;
        };
        const keep_arg = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-prune <suite> <keep>");
            return;
        };
        if (keep_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-release-prune <suite> <keep>");
            return;
        }
        const keep = std.fmt.parseInt(usize, keep_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-release-prune <suite> <keep>");
            return;
        };
        const prune = app_runtime.pruneSuiteReleases(suite_name.arg, keep, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-release-prune failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt(
            "app suite release pruned {s} keep={d} deleted={d} kept={d}\n",
            .{ suite_name.arg, keep, prune.deleted_count, prune.kept_count },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-release-channel-list")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-channel-list <suite>");
            return;
        };
        if (suite_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-release-channel-list <suite>");
            return;
        }
        const listing = app_runtime.suiteChannelListAlloc(allocator, suite_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-release-channel-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-release-channel-info")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-channel-info <suite> <channel>");
            return;
        };
        const channel_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-channel-info <suite> <channel>");
            return;
        };
        if (channel_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-release-channel-info <suite> <channel>");
            return;
        }
        const info = app_runtime.suiteChannelInfoAlloc(allocator, suite_name.arg, channel_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-release-channel-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-release-channel-set")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-channel-set <suite> <channel> <release>");
            return;
        };
        const channel_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-channel-set <suite> <channel> <release>");
            return;
        };
        const release_name = parseFirstArg(channel_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-channel-set <suite> <channel> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-release-channel-set <suite> <channel> <release>");
            return;
        }
        app_runtime.setSuiteReleaseChannel(suite_name.arg, channel_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-release-channel-set failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app suite release channel set {s} {s} {s}\n", .{ suite_name.arg, channel_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-suite-release-channel-activate")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-channel-activate <suite> <channel>");
            return;
        };
        const channel_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-suite-release-channel-activate <suite> <channel>");
            return;
        };
        if (channel_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-suite-release-channel-activate <suite> <channel>");
            return;
        }
        app_runtime.activateSuiteReleaseChannel(suite_name.arg, channel_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-suite-release-channel-activate failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app suite release channel activated {s} {s}\n", .{ suite_name.arg, channel_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-delete")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-delete <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-delete <name>");
            return;
        }
        app_runtime.uninstallApp(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app deleted {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-autorun-list")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-autorun-list");
            return;
        }
        const listing = app_runtime.autorunListAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-autorun-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-autorun-add")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-autorun-add <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-autorun-add <name>");
            return;
        }
        app_runtime.addAutorun(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-autorun-add failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app autorun add {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-autorun-remove")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-autorun-remove <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-autorun-remove <name>");
            return;
        }
        app_runtime.removeAutorun(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("app-autorun-remove failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("app autorun remove {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-list")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-list <name>");
            return;
        };
        if (workspace_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-list <name>");
            return;
        }
        const listing = workspace_runtime.planListAlloc(allocator, workspace_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-info")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-info <name> <plan>");
            return;
        };
        const plan_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-info <name> <plan>");
            return;
        };
        if (plan_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-info <name> <plan>");
            return;
        }
        const info = workspace_runtime.planInfoAlloc(allocator, workspace_name.arg, plan_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-active")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-active <name>");
            return;
        };
        if (workspace_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-active <name>");
            return;
        }
        const info = workspace_runtime.activePlanInfoAlloc(allocator, workspace_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-active failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-save")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-save <name> <plan> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const plan_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-save <name> <plan> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const suite_name = parseFirstArg(plan_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-save <name> <plan> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const trust_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-save <name> <plan> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const width_arg = parseFirstArg(trust_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-save <name> <plan> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const height_arg = parseFirstArg(width_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-save <name> <plan> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const width = std.fmt.parseInt(u16, width_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-save <name> <plan> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const height = std.fmt.parseInt(u16, height_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-save <name> <plan> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const selected_suite = if (std.ascii.eqlIgnoreCase(suite_name.arg, "none")) "" else suite_name.arg;
        const selected_trust = if (std.ascii.eqlIgnoreCase(trust_name.arg, "none")) "" else trust_name.arg;
        workspace_runtime.savePlan(workspace_name.arg, plan_name.arg, selected_suite, selected_trust, width, height, height_arg.rest, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-save failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace plan saved {s} {s}\n", .{ workspace_name.arg, plan_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-apply")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-apply <name> <plan>");
            return;
        };
        const plan_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-apply <name> <plan>");
            return;
        };
        if (plan_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-apply <name> <plan>");
            return;
        }
        workspace_runtime.applyPlan(workspace_name.arg, plan_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-apply failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace plan applied {s} {s}\n", .{ workspace_name.arg, plan_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-delete")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-delete <name> <plan>");
            return;
        };
        const plan_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-delete <name> <plan>");
            return;
        };
        if (plan_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-delete <name> <plan>");
            return;
        }
        workspace_runtime.deletePlan(workspace_name.arg, plan_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace plan deleted {s} {s}\n", .{ workspace_name.arg, plan_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-release-list")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-list <name> <plan>");
            return;
        };
        const plan_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-list <name> <plan>");
            return;
        };
        if (plan_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-release-list <name> <plan>");
            return;
        }
        const listing = workspace_runtime.planReleaseListAlloc(allocator, workspace_name.arg, plan_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-release-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-release-info")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-info <name> <plan> <release>");
            return;
        };
        const plan_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-info <name> <plan> <release>");
            return;
        };
        const release_name = parseFirstArg(plan_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-info <name> <plan> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-release-info <name> <plan> <release>");
            return;
        }
        const info = workspace_runtime.planReleaseInfoAlloc(allocator, workspace_name.arg, plan_name.arg, release_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-release-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-release-save")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-save <name> <plan> <release>");
            return;
        };
        const plan_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-save <name> <plan> <release>");
            return;
        };
        const release_name = parseFirstArg(plan_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-save <name> <plan> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-release-save <name> <plan> <release>");
            return;
        }
        workspace_runtime.snapshotPlanRelease(workspace_name.arg, plan_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-release-save failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace plan release saved {s} {s} {s}\n", .{ workspace_name.arg, plan_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-release-activate")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-activate <name> <plan> <release>");
            return;
        };
        const plan_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-activate <name> <plan> <release>");
            return;
        };
        const release_name = parseFirstArg(plan_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-activate <name> <plan> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-release-activate <name> <plan> <release>");
            return;
        }
        workspace_runtime.activatePlanRelease(workspace_name.arg, plan_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-release-activate failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace plan release activated {s} {s} {s}\n", .{ workspace_name.arg, plan_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-release-delete")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-delete <name> <plan> <release>");
            return;
        };
        const plan_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-delete <name> <plan> <release>");
            return;
        };
        const release_name = parseFirstArg(plan_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-delete <name> <plan> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-release-delete <name> <plan> <release>");
            return;
        }
        workspace_runtime.deletePlanRelease(workspace_name.arg, plan_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-release-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace plan release deleted {s} {s} {s}\n", .{ workspace_name.arg, plan_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-plan-release-prune")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-prune <name> <plan> <keep>");
            return;
        };
        const plan_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-prune <name> <plan> <keep>");
            return;
        };
        const keep_arg = parseFirstArg(plan_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-plan-release-prune <name> <plan> <keep>");
            return;
        };
        if (keep_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-release-prune <name> <plan> <keep>");
            return;
        }
        const keep = std.fmt.parseInt(u32, keep_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-plan-release-prune <name> <plan> <keep>");
            return;
        };
        const result = workspace_runtime.prunePlanReleases(workspace_name.arg, plan_name.arg, keep, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-plan-release-prune failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt(
            "workspace plan release pruned {s} {s} keep={d} deleted={d} kept={d}\n",
            .{ workspace_name.arg, plan_name.arg, keep, result.deleted_count, result.kept_count },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-list")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-list");
            return;
        }
        const listing = workspace_runtime.suiteListAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-info")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-info <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-info <name>");
            return;
        }
        const info = workspace_runtime.suiteInfoAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-save")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-save <name> <workspace...>");
            return;
        };
        if (suite_name.rest.len == 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-save <name> <workspace...>");
            return;
        }
        workspace_runtime.saveSuite(suite_name.arg, suite_name.rest, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-save failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace suite saved {s}\n", .{suite_name.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-apply")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-apply <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-apply <name>");
            return;
        }
        workspace_runtime.applySuite(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-apply failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace suite applied {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-run")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-run <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-run <name>");
            return;
        }
        try runWorkspaceSuite(arg.arg, "workspace-suite-run", stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-delete")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-delete <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-delete <name>");
            return;
        }
        workspace_runtime.deleteSuite(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace suite deleted {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-release-list")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-list <suite>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-release-list <suite>");
            return;
        }
        const listing = workspace_runtime.suiteReleaseListAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-release-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-release-info")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-info <suite> <release>");
            return;
        };
        const release_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-info <suite> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-release-info <suite> <release>");
            return;
        }
        const info = workspace_runtime.suiteReleaseInfoAlloc(allocator, suite_name.arg, release_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-release-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-release-save")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-save <suite> <release>");
            return;
        };
        const release_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-save <suite> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-release-save <suite> <release>");
            return;
        }
        workspace_runtime.snapshotSuiteRelease(suite_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-release-save failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace suite release saved {s} {s}\n", .{ suite_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-release-activate")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-activate <suite> <release>");
            return;
        };
        const release_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-activate <suite> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-release-activate <suite> <release>");
            return;
        }
        workspace_runtime.activateSuiteRelease(suite_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-release-activate failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace suite release activated {s} {s}\n", .{ suite_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-release-delete")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-delete <suite> <release>");
            return;
        };
        const release_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-delete <suite> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-release-delete <suite> <release>");
            return;
        }
        workspace_runtime.deleteSuiteRelease(suite_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-release-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace suite release deleted {s} {s}\n", .{ suite_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-release-prune")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-prune <suite> <keep>");
            return;
        };
        const keep_arg = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-prune <suite> <keep>");
            return;
        };
        if (keep_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-release-prune <suite> <keep>");
            return;
        }
        const keep = std.fmt.parseInt(usize, keep_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-release-prune <suite> <keep>");
            return;
        };
        const result = workspace_runtime.pruneSuiteReleases(suite_name.arg, keep, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-release-prune failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt(
            "workspace suite release pruned {s} keep={d} deleted={d} kept={d}\n",
            .{ suite_name.arg, keep, result.deleted_count, result.kept_count },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-release-channel-list")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-channel-list <suite>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-release-channel-list <suite>");
            return;
        }
        const listing = workspace_runtime.suiteChannelListAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-release-channel-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-release-channel-info")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-channel-info <suite> <channel>");
            return;
        };
        const channel_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-channel-info <suite> <channel>");
            return;
        };
        if (channel_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-release-channel-info <suite> <channel>");
            return;
        }
        const info = workspace_runtime.suiteChannelInfoAlloc(allocator, suite_name.arg, channel_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-release-channel-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-release-channel-set")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-channel-set <suite> <channel> <release>");
            return;
        };
        const channel_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-channel-set <suite> <channel> <release>");
            return;
        };
        const release_name = parseFirstArg(channel_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-channel-set <suite> <channel> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-release-channel-set <suite> <channel> <release>");
            return;
        }
        workspace_runtime.setSuiteReleaseChannel(suite_name.arg, channel_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-release-channel-set failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace suite release channel set {s} {s} {s}\n", .{ suite_name.arg, channel_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-suite-release-channel-activate")) {
        const suite_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-channel-activate <suite> <channel>");
            return;
        };
        const channel_name = parseFirstArg(suite_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-suite-release-channel-activate <suite> <channel>");
            return;
        };
        if (channel_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-suite-release-channel-activate <suite> <channel>");
            return;
        }
        workspace_runtime.activateSuiteReleaseChannel(suite_name.arg, channel_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-suite-release-channel-activate failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace suite release channel activated {s} {s}\n", .{ suite_name.arg, channel_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-list")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-list");
            return;
        }
        const listing = workspace_runtime.listAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-info")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-info <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-info <name>");
            return;
        }
        const info = workspace_runtime.infoAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-save")) {
        const name_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-save <name> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const suite_arg = parseFirstArg(name_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-save <name> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const trust_arg = parseFirstArg(suite_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-save <name> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const width_arg = parseFirstArg(trust_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-save <name> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const height_arg = parseFirstArg(width_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-save <name> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const width = std.fmt.parseInt(u16, width_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-save <name> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const height = std.fmt.parseInt(u16, height_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-save <name> <suite|none> <trust|none> <width> <height> [package:channel:release...]");
            return;
        };
        const suite_name = if (std.ascii.eqlIgnoreCase(suite_arg.arg, "none")) "" else suite_arg.arg;
        const trust_name = if (std.ascii.eqlIgnoreCase(trust_arg.arg, "none")) "" else trust_arg.arg;
        workspace_runtime.saveWorkspace(name_arg.arg, suite_name, trust_name, width, height, height_arg.rest, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-save failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace saved {s}\n", .{name_arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-apply")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-apply <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-apply <name>");
            return;
        }
        workspace_runtime.applyWorkspace(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-apply failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace applied {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-run")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-run <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-run <name>");
            return;
        }
        try runWorkspace(arg.arg, "workspace-run", stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-state")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-state <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-state <name>");
            return;
        }
        const state = workspace_runtime.stateAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-state failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(state);
        try stdout_buffer.appendSlice(state);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-history")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-history <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-history <name>");
            return;
        }
        const history = workspace_runtime.historyAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-history failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(history);
        try stdout_buffer.appendSlice(history);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-stdout")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-stdout <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-stdout <name>");
            return;
        }
        const stdout = workspace_runtime.stdoutAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-stdout failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(stdout);
        try stdout_buffer.appendSlice(stdout);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-stderr")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-stderr <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-stderr <name>");
            return;
        }
        const stderr = workspace_runtime.stderrAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-stderr failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(stderr);
        try stdout_buffer.appendSlice(stderr);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-delete")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-delete <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-delete <name>");
            return;
        }
        workspace_runtime.deleteWorkspace(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace deleted {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-release-list")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-list <name>");
            return;
        };
        if (workspace_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-release-list <name>");
            return;
        }
        const listing = workspace_runtime.releaseListAlloc(allocator, workspace_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-release-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-release-info")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-info <name> <release>");
            return;
        };
        const release_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-info <name> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-release-info <name> <release>");
            return;
        }
        const info = workspace_runtime.releaseInfoAlloc(allocator, workspace_name.arg, release_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-release-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-release-save")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-save <name> <release>");
            return;
        };
        const release_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-save <name> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-release-save <name> <release>");
            return;
        }
        workspace_runtime.snapshotWorkspaceRelease(workspace_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-release-save failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace release saved {s} {s}\n", .{ workspace_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-release-activate")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-activate <name> <release>");
            return;
        };
        const release_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-activate <name> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-release-activate <name> <release>");
            return;
        }
        workspace_runtime.activateWorkspaceRelease(workspace_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-release-activate failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace release activated {s} {s}\n", .{ workspace_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-release-delete")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-delete <name> <release>");
            return;
        };
        const release_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-delete <name> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-release-delete <name> <release>");
            return;
        }
        workspace_runtime.deleteWorkspaceRelease(workspace_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-release-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace release deleted {s} {s}\n", .{ workspace_name.arg, release_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-release-prune")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-prune <name> <keep>");
            return;
        };
        const keep_arg = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-prune <name> <keep>");
            return;
        };
        if (keep_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-release-prune <name> <keep>");
            return;
        }
        const keep = std.fmt.parseInt(usize, keep_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-release-prune <name> <keep>");
            return;
        };
        const prune = workspace_runtime.pruneWorkspaceReleases(workspace_name.arg, keep, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-release-prune failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt(
            "workspace release pruned {s} keep={d} deleted={d} kept={d}\n",
            .{ workspace_name.arg, keep, prune.deleted_count, prune.kept_count },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-release-channel-list")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-channel-list <name>");
            return;
        };
        if (workspace_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-release-channel-list <name>");
            return;
        }
        const listing = workspace_runtime.channelListAlloc(allocator, workspace_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-release-channel-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-release-channel-info")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-channel-info <name> <channel>");
            return;
        };
        const channel_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-channel-info <name> <channel>");
            return;
        };
        if (channel_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-release-channel-info <name> <channel>");
            return;
        }
        const info = workspace_runtime.channelInfoAlloc(allocator, workspace_name.arg, channel_name.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-release-channel-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-release-channel-set")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-channel-set <name> <channel> <release>");
            return;
        };
        const channel_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-channel-set <name> <channel> <release>");
            return;
        };
        const release_name = parseFirstArg(channel_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-channel-set <name> <channel> <release>");
            return;
        };
        if (release_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-release-channel-set <name> <channel> <release>");
            return;
        }
        workspace_runtime.setWorkspaceReleaseChannel(workspace_name.arg, channel_name.arg, release_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-release-channel-set failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt(
            "workspace release channel set {s} {s} {s}\n",
            .{ workspace_name.arg, channel_name.arg, release_name.arg },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-release-channel-activate")) {
        const workspace_name = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-channel-activate <name> <channel>");
            return;
        };
        const channel_name = parseFirstArg(workspace_name.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-release-channel-activate <name> <channel>");
            return;
        };
        if (channel_name.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-release-channel-activate <name> <channel>");
            return;
        }
        workspace_runtime.activateWorkspaceReleaseChannel(workspace_name.arg, channel_name.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-release-channel-activate failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace release channel activated {s} {s}\n", .{ workspace_name.arg, channel_name.arg });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-autorun-list")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-autorun-list");
            return;
        }
        const listing = workspace_runtime.autorunListAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-autorun-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-autorun-add")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-autorun-add <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-autorun-add <name>");
            return;
        }
        workspace_runtime.addAutorun(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-autorun-add failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace autorun add {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-autorun-remove")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "workspace-autorun-remove <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-autorun-remove <name>");
            return;
        }
        workspace_runtime.removeAutorun(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("workspace-autorun-remove failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("workspace autorun remove {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "trust-list")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: trust-list");
            return;
        }
        const listing = trust_store.listBundlesAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("trust-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "trust-info")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "trust-info <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: trust-info <name>");
            return;
        }
        const info = trust_store.infoAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("trust-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "trust-active")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: trust-active");
            return;
        }
        const info = trust_store.activeBundleInfoAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("trust-active failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "trust-select")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "trust-select <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: trust-select <name>");
            return;
        }
        trust_store.selectBundle(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("trust-select failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("selected {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "trust-delete")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "trust-delete <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: trust-delete <name>");
            return;
        }
        trust_store.deleteBundle(arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("trust-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("deleted {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "runtime-snapshot")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: runtime-snapshot");
            return;
        }
        const snapshot = runtime_bridge.snapshotAlloc(allocator) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("runtime-snapshot failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(snapshot);
        try stdout_buffer.appendSlice(snapshot);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "runtime-sessions")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: runtime-sessions");
            return;
        }
        const sessions = runtime_bridge.sessionListAlloc(allocator) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("runtime-sessions failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(sessions);
        try stdout_buffer.appendSlice(sessions);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "runtime-session")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "runtime-session <id>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: runtime-session <id>");
            return;
        }
        const session_info = runtime_bridge.sessionInfoAlloc(allocator, arg.arg) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("runtime-session failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(session_info);
        try stdout_buffer.appendSlice(session_info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-info")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-info");
            return;
        }
        ensureDisplayReady();
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "backend={s} controller={s} connector={s} interface={s} connected={d} hardware_backed={d} current={d}x{d} preferred={d}x{d} scanouts={d} active={d} capabilities=0x{x}\n",
            .{
                displayBackendName(output.backend),
                displayControllerName(output.controller),
                displayConnectorName(output.connector_type),
                displayInterfaceName(display_output.stateInterfaceType()),
                output.connected,
                output.hardware_backed,
                output.current_width,
                output.current_height,
                output.preferred_width,
                output.preferred_height,
                output.scanout_count,
                output.active_scanout,
                output.capability_flags,
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-outputs")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-outputs");
            return;
        }
        ensureDisplayReady();
        var index: u16 = 0;
        while (index < display_output.outputCount()) : (index += 1) {
            const entry = display_output.outputEntry(index);
            try stdout_buffer.appendFmt(
                "output {d} scanout={d} connector={s} interface={s} connected={d} current={d}x{d} preferred={d}x{d} capabilities=0x{x}\n",
                .{
                    index,
                    entry.scanout_index,
                    displayConnectorName(entry.connector_type),
                    displayInterfaceName(display_output.outputInterfaceType(index)),
                    entry.connected,
                    entry.current_width,
                    entry.current_height,
                    entry.preferred_width,
                    entry.preferred_height,
                    entry.capability_flags,
                },
            );
        }
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-output")) {
        const index_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-output <index>");
            return;
        };
        if (index_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output <index>");
            return;
        }
        const index = std.fmt.parseInt(u16, index_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output <index>");
            return;
        };
        ensureDisplayReady();
        if (index >= display_output.outputCount()) {
            exit_code.* = 1;
            try stderr_buffer.appendLine("display-output failed: NotFound");
            return;
        }
        const entry = display_output.outputEntry(index);
        try stdout_buffer.appendFmt(
            "index={d} scanout={d} connector={s} interface={s} connected={d} current={d}x{d} preferred={d}x{d} capabilities=0x{x} edid_present={d} mode_count={d}\n",
            .{
                index,
                entry.scanout_index,
                displayConnectorName(entry.connector_type),
                displayInterfaceName(display_output.outputInterfaceType(index)),
                entry.connected,
                entry.current_width,
                entry.current_height,
                entry.preferred_width,
                entry.preferred_height,
                entry.capability_flags,
                entry.edid_present,
                pal_framebuffer.displayOutputModeCount(index),
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-output-detail")) {
        const index_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-output-detail <index>");
            return;
        };
        if (index_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-detail <index>");
            return;
        }
        const index = std.fmt.parseInt(u16, index_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-detail <index>");
            return;
        };
        ensureDisplayReady();
        if (index >= display_output.outputCount()) {
            exit_code.* = 1;
            try stderr_buffer.appendLine("display-output-detail failed: NotFound");
            return;
        }
        try appendDisplayOutputDetailLine(stdout_buffer, index);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-output-capabilities")) {
        const index_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-output-capabilities <index>");
            return;
        };
        if (index_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-capabilities <index>");
            return;
        }
        const index = std.fmt.parseInt(u16, index_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-capabilities <index>");
            return;
        };
        ensureDisplayReady();
        if (index >= display_output.outputCount()) {
            exit_code.* = 1;
            try stderr_buffer.appendLine("display-output-capabilities failed: NotFound");
            return;
        }
        try appendDisplayOutputCapabilityLine(stdout_buffer, index);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-output-modes")) {
        const index_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-output-modes <index>");
            return;
        };
        if (index_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-modes <index>");
            return;
        }
        const index = std.fmt.parseInt(u16, index_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-modes <index>");
            return;
        };
        ensureDisplayReady();
        if (index >= display_output.outputCount()) {
            exit_code.* = 1;
            try stderr_buffer.appendLine("display-output-modes failed: NotFound");
            return;
        }
        const mode_count = pal_framebuffer.displayOutputModeCount(index);
        var mode_index: u16 = 0;
        while (mode_index < mode_count) : (mode_index += 1) {
            const mode = pal_framebuffer.displayOutputMode(index, mode_index) orelse continue;
            try appendDisplayModeLine(stdout_buffer, mode_index, mode);
        }
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-interface-detail")) {
        const interface_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-interface-detail <interface>");
            return;
        };
        if (interface_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-detail <interface>");
            return;
        }
        const interface_type = display_output.interfaceTypeFromName(interface_arg.arg) orelse {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-detail <interface>");
            return;
        };
        ensureDisplayReady();
        const index = display_output.connectedOutputIndexForInterface(interface_type) orelse {
            exit_code.* = 1;
            try stderr_buffer.appendLine("display-interface-detail failed: NotFound");
            return;
        };
        try appendDisplayOutputDetailLine(stdout_buffer, index);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-interface-capabilities")) {
        const interface_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-interface-capabilities <interface>");
            return;
        };
        if (interface_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-capabilities <interface>");
            return;
        }
        const interface_type = display_output.interfaceTypeFromName(interface_arg.arg) orelse {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-capabilities <interface>");
            return;
        };
        ensureDisplayReady();
        const index = display_output.connectedOutputIndexForInterface(interface_type) orelse {
            exit_code.* = 1;
            try stderr_buffer.appendLine("display-interface-capabilities failed: NotFound");
            return;
        };
        try appendDisplayOutputCapabilityLine(stdout_buffer, index);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-interface-modes")) {
        const interface_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-interface-modes <interface>");
            return;
        };
        if (interface_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-modes <interface>");
            return;
        }
        const interface_type = display_output.interfaceTypeFromName(interface_arg.arg) orelse {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-modes <interface>");
            return;
        };
        ensureDisplayReady();
        const mode_count = pal_framebuffer.displayOutputModeCountForInterface(interface_type);
        if (mode_count == 0) {
            exit_code.* = 1;
            try stderr_buffer.appendLine("display-interface-modes failed: NotFound");
            return;
        }
        var mode_index: u16 = 0;
        while (mode_index < mode_count) : (mode_index += 1) {
            const mode = pal_framebuffer.displayOutputModeForInterface(interface_type, mode_index) orelse continue;
            try appendDisplayModeLine(stdout_buffer, mode_index, mode);
        }
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-modes")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-modes");
            return;
        }
        ensureDisplayReady();
        var index: u16 = 0;
        while (index < framebuffer_console.supportedModeCount()) : (index += 1) {
            try stdout_buffer.appendFmt(
                "mode {d} {d}x{d}\n",
                .{ index, framebuffer_console.supportedModeWidth(index), framebuffer_console.supportedModeHeight(index) },
            );
        }
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-set")) {
        const width_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-set <width> <height>");
            return;
        };
        const height_arg = parseFirstArg(width_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-set <width> <height>");
            return;
        };
        if (height_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-set <width> <height>");
            return;
        }
        const width = std.fmt.parseInt(u16, width_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-set <width> <height>");
            return;
        };
        const height = std.fmt.parseInt(u16, height_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-set <width> <height>");
            return;
        };
        framebuffer_console.setMode(width, height) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-set failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("display mode {d}x{d}\n", .{ width, height });
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-activate")) {
        const connector_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-activate <connector>");
            return;
        };
        if (connector_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate <connector>");
            return;
        }
        const connector_type = package_store.parseConnectorType(connector_arg.arg) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate <connector>");
            return;
        };
        activateDisplayConnector(connector_type) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-activate failed: {s}\n", .{@errorName(err)});
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display connector {s} active scanout={d} current={d}x{d}\n",
            .{
                displayConnectorName(output.connector_type),
                output.active_scanout,
                output.current_width,
                output.current_height,
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-activate-preferred")) {
        const connector_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-activate-preferred <connector>");
            return;
        };
        if (connector_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate-preferred <connector>");
            return;
        }
        const connector_type = package_store.parseConnectorType(connector_arg.arg) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate-preferred <connector>");
            return;
        };
        activateDisplayConnectorPreferred(connector_type) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-activate-preferred failed: {s}\n", .{@errorName(err)});
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display connector preferred {s} scanout={d} current={d}x{d} preferred={d}x{d}\n",
            .{
                displayConnectorName(output.connector_type),
                output.active_scanout,
                output.current_width,
                output.current_height,
                if (output.preferred_width != 0) output.preferred_width else output.current_width,
                if (output.preferred_height != 0) output.preferred_height else output.current_height,
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-activate-interface")) {
        const interface_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-activate-interface <interface>");
            return;
        };
        if (interface_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate-interface <interface>");
            return;
        }
        const interface_type = display_output.interfaceTypeFromName(interface_arg.arg) orelse {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate-interface <interface>");
            return;
        };
        activateDisplayInterface(interface_type) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-activate-interface failed: {s}\n", .{@errorName(err)});
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display interface {s} active connector={s} scanout={d} current={d}x{d}\n",
            .{
                displayInterfaceName(output.reserved0),
                displayConnectorName(output.connector_type),
                output.active_scanout,
                output.current_width,
                output.current_height,
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-activate-interface-preferred")) {
        const interface_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-activate-interface-preferred <interface>");
            return;
        };
        if (interface_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate-interface-preferred <interface>");
            return;
        }
        const interface_type = display_output.interfaceTypeFromName(interface_arg.arg) orelse {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate-interface-preferred <interface>");
            return;
        };
        activateDisplayInterfacePreferred(interface_type) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-activate-interface-preferred failed: {s}\n", .{@errorName(err)});
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display interface preferred {s} connector={s} scanout={d} current={d}x{d} preferred={d}x{d}\n",
            .{
                displayInterfaceName(output.reserved0),
                displayConnectorName(output.connector_type),
                output.active_scanout,
                output.current_width,
                output.current_height,
                if (output.preferred_width != 0) output.preferred_width else output.current_width,
                if (output.preferred_height != 0) output.preferred_height else output.current_height,
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-interface-set")) {
        const interface_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-interface-set <interface> <width> <height>");
            return;
        };
        const width_arg = parseFirstArg(interface_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-interface-set <interface> <width> <height>");
            return;
        };
        const height_arg = parseFirstArg(width_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-interface-set <interface> <width> <height>");
            return;
        };
        if (height_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-set <interface> <width> <height>");
            return;
        }
        const interface_type = display_output.interfaceTypeFromName(interface_arg.arg) orelse {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-set <interface> <width> <height>");
            return;
        };
        const width = std.fmt.parseInt(u16, width_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-set <interface> <width> <height>");
            return;
        };
        const height = std.fmt.parseInt(u16, height_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-set <interface> <width> <height>");
            return;
        };
        setDisplayInterfaceMode(interface_type, width, height) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-interface-set failed: {s}\n", .{@errorName(err)});
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display interface {s} mode {d}x{d} connector={s} scanout={d}\n",
            .{
                displayInterfaceName(output.reserved0),
                output.current_width,
                output.current_height,
                displayConnectorName(output.connector_type),
                output.active_scanout,
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-interface-activate-mode")) {
        const interface_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-interface-activate-mode <interface> <mode-index>");
            return;
        };
        const mode_arg = parseFirstArg(interface_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-interface-activate-mode <interface> <mode-index>");
            return;
        };
        if (mode_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-activate-mode <interface> <mode-index>");
            return;
        }
        const interface_type = display_output.interfaceTypeFromName(interface_arg.arg) orelse {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-activate-mode <interface> <mode-index>");
            return;
        };
        const mode_index = std.fmt.parseInt(u16, mode_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-interface-activate-mode <interface> <mode-index>");
            return;
        };
        pal_framebuffer.activateDisplayInterfaceMode(interface_type, mode_index) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-interface-activate-mode failed: {s}\n", .{@errorName(err)});
            return;
        };
        const mode = pal_framebuffer.displayOutputModeForInterface(interface_type, mode_index) orelse {
            exit_code.* = 1;
            try stderr_buffer.appendLine("display-interface-activate-mode failed: UnsupportedMode");
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display interface mode {s}:{d} {d}x{d} connector={s} scanout={d}\n",
            .{
                displayInterfaceName(output.reserved0),
                mode_index,
                mode.width,
                mode.height,
                displayConnectorName(output.connector_type),
                output.active_scanout,
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-activate-output")) {
        const output_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-activate-output <index>");
            return;
        };
        if (output_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate-output <index>");
            return;
        }
        const output_index = std.fmt.parseInt(u16, output_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate-output <index>");
            return;
        };
        activateDisplayOutput(output_index) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-activate-output failed: {s}\n", .{@errorName(err)});
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display output {d} active connector={s} scanout={d} current={d}x{d}\n",
            .{
                output_index,
                displayConnectorName(output.connector_type),
                output.active_scanout,
                output.current_width,
                output.current_height,
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-activate-output-preferred")) {
        const output_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-activate-output-preferred <index>");
            return;
        };
        if (output_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate-output-preferred <index>");
            return;
        }
        const output_index = std.fmt.parseInt(u16, output_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-activate-output-preferred <index>");
            return;
        };
        activateDisplayOutputPreferred(output_index) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-activate-output-preferred failed: {s}\n", .{@errorName(err)});
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display output preferred {d} connector={s} scanout={d} current={d}x{d} preferred={d}x{d}\n",
            .{
                output_index,
                displayConnectorName(output.connector_type),
                output.active_scanout,
                output.current_width,
                output.current_height,
                if (output.preferred_width != 0) output.preferred_width else output.current_width,
                if (output.preferred_height != 0) output.preferred_height else output.current_height,
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-output-set")) {
        const output_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-output-set <index> <width> <height>");
            return;
        };
        const width_arg = parseFirstArg(output_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-output-set <index> <width> <height>");
            return;
        };
        const height_arg = parseFirstArg(width_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-output-set <index> <width> <height>");
            return;
        };
        if (height_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-set <index> <width> <height>");
            return;
        }
        const output_index = std.fmt.parseInt(u16, output_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-set <index> <width> <height>");
            return;
        };
        const width = std.fmt.parseInt(u16, width_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-set <index> <width> <height>");
            return;
        };
        const height = std.fmt.parseInt(u16, height_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-set <index> <width> <height>");
            return;
        };
        setDisplayOutputMode(output_index, width, height) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-output-set failed: {s}\n", .{@errorName(err)});
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display output {d} mode {d}x{d} connector={s} scanout={d}\n",
            .{
                output_index,
                output.current_width,
                output.current_height,
                displayConnectorName(output.connector_type),
                output.active_scanout,
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-output-activate-mode")) {
        const output_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-output-activate-mode <index> <mode-index>");
            return;
        };
        const mode_arg = parseFirstArg(output_arg.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-output-activate-mode <index> <mode-index>");
            return;
        };
        if (mode_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-activate-mode <index> <mode-index>");
            return;
        }
        const output_index = std.fmt.parseInt(u16, output_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-activate-mode <index> <mode-index>");
            return;
        };
        const mode_index = std.fmt.parseInt(u16, mode_arg.arg, 10) catch {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-output-activate-mode <index> <mode-index>");
            return;
        };
        pal_framebuffer.activateDisplayOutputMode(output_index, mode_index) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-output-activate-mode failed: {s}\n", .{@errorName(err)});
            return;
        };
        const mode = pal_framebuffer.displayOutputMode(output_index, mode_index) orelse {
            exit_code.* = 1;
            try stderr_buffer.appendLine("display-output-activate-mode failed: UnsupportedMode");
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display output mode {d}:{d} {d}x{d} connector={s} scanout={d}\n",
            .{
                output_index,
                mode_index,
                mode.width,
                mode.height,
                displayConnectorName(output.connector_type),
                output.active_scanout,
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-profile-list")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-profile-list");
            return;
        }
        const listing = display_profile_store.listProfilesAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-profile-list failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-profile-info")) {
        const name_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-profile-info <name>");
            return;
        };
        if (name_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-profile-info <name>");
            return;
        }
        const info = display_profile_store.infoAlloc(allocator, name_arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-profile-info failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-profile-active")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-profile-active");
            return;
        }
        const info = display_profile_store.activeProfileInfoAlloc(allocator, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-profile-active failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(info);
        try stdout_buffer.appendSlice(info);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-profile-save")) {
        const name_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-profile-save <name>");
            return;
        };
        if (name_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-profile-save <name>");
            return;
        }
        display_profile_store.saveCurrentProfile(name_arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-profile-save failed: {s}\n", .{@errorName(err)});
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display profile saved {s} output={d} current={d}x{d} connector={s}\n",
            .{
                name_arg.arg,
                output.active_scanout,
                output.current_width,
                output.current_height,
                displayConnectorName(output.connector_type),
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-profile-apply")) {
        const name_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-profile-apply <name>");
            return;
        };
        if (name_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-profile-apply <name>");
            return;
        }
        display_profile_store.applyProfile(name_arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-profile-apply failed: {s}\n", .{@errorName(err)});
            return;
        };
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "display profile applied {s} output={d} current={d}x{d} connector={s}\n",
            .{
                name_arg.arg,
                output.active_scanout,
                output.current_width,
                output.current_height,
                displayConnectorName(output.connector_type),
            },
        );
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-profile-delete")) {
        const name_arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "display-profile-delete <name>");
            return;
        };
        if (name_arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-profile-delete <name>");
            return;
        }
        display_profile_store.deleteProfile(name_arg.arg, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("display-profile-delete failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("display profile deleted {s}\n", .{name_arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "run-script")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "run-script <path>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: run-script <path>");
            return;
        }
        try executeScriptPath(arg.arg, "run-script", stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "run-package")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "run-package <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: run-package <name>");
            return;
        }
        try runLaunchProfile(arg.arg, "run-package", false, stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-run")) {
        const arg = parseFirstArg(parsed.rest) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, "app-run <name>");
            return;
        };
        if (arg.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-run <name>");
            return;
        }
        try runLaunchProfile(arg.arg, "app-run", true, stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "app-autorun-run")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: app-autorun-run");
            return;
        }
        try runAutorunProfiles("app-autorun-run", stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "workspace-autorun-run")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: workspace-autorun-run");
            return;
        }
        try runWorkspaceAutorun("workspace-autorun-run", stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        return;
    }

    exit_code.* = 127;
    try stderr_buffer.appendFmt("unknown command: {s}\n", .{parsed.name});
}

fn displayBackendName(value: u8) []const u8 {
    return switch (value) {
        abi.display_backend_bga => "bga",
        abi.display_backend_virtio_gpu => "virtio-gpu",
        else => "none",
    };
}

fn ensureDisplayReady() void {
    if (display_output.statePtr().backend == abi.display_backend_none) {
        _ = framebuffer_console.init();
    }
}

fn ensureDisplayReadyForMode(width: u16, height: u16) error{UnsupportedMode}!void {
    if (display_output.statePtr().backend == abi.display_backend_none) {
        try framebuffer_console.prepareMode(width, height);
        return;
    }

    const framebuffer_state = framebuffer_console.statePtr();
    if (framebuffer_state.width != width or framebuffer_state.height != height) {
        try framebuffer_console.prepareMode(width, height);
    }
}

pub fn activateDisplayConnector(connector_type: u8) Error!void {
    if (connector_type == abi.display_connector_none) return;
    ensureDisplayReady();
    const display_state = display_output.statePtr();
    if (display_state.connector_type == connector_type and
        (display_state.connected == 1 or display_state.controller != abi.display_controller_virtio_gpu))
    {
        return;
    }

    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForConnector(connector_type) catch return error.DisplayConnectorMismatch;
        } else if (!display_output.selectOutputConnector(connector_type)) {
            return error.DisplayConnectorMismatch;
        }
    } else if (display_state.connector_type == connector_type) {
        return;
    }

    const refreshed = display_output.statePtr();
    if (refreshed.connector_type != connector_type) return error.DisplayConnectorMismatch;
    if (refreshed.controller == abi.display_controller_virtio_gpu and refreshed.connected != 1) {
        return error.DisplayConnectorMismatch;
    }
}

pub fn activateDisplayConnectorPreferred(connector_type: u8) Error!void {
    if (connector_type == abi.display_connector_none) return;
    ensureDisplayReady();
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForConnectorPreferred(connector_type) catch |err| switch (err) {
                error.NoConnectedScanout => return error.DisplayConnectorMismatch,
                error.UnsupportedMode, error.FramebufferTooLarge => return error.DisplayOutputUnsupportedMode,
                else => return error.DisplayConnectorMismatch,
            };
        } else {
            if (!display_output.selectOutputConnector(connector_type)) return error.DisplayConnectorMismatch;
            if (!display_output.setOutputPreferredMode(@as(u16, display_output.statePtr().active_scanout))) {
                return error.DisplayOutputUnsupportedMode;
            }
        }
    } else {
        if (display_state.connector_type != connector_type) return error.DisplayConnectorMismatch;
        const mode = display_output.preferredMode(@as(u16, display_state.active_scanout)) orelse return error.DisplayOutputUnsupportedMode;
        ensureDisplayReadyForMode(mode.width, mode.height) catch return error.DisplayOutputUnsupportedMode;
    }

    const refreshed = display_output.statePtr();
    if (refreshed.connector_type != connector_type) return error.DisplayConnectorMismatch;
    if (refreshed.controller == abi.display_controller_virtio_gpu and refreshed.connected != 1) {
        return error.DisplayConnectorMismatch;
    }
    const preferred_width = if (refreshed.preferred_width != 0) refreshed.preferred_width else refreshed.current_width;
    const preferred_height = if (refreshed.preferred_height != 0) refreshed.preferred_height else refreshed.current_height;
    if (refreshed.current_width != preferred_width or refreshed.current_height != preferred_height) {
        return error.DisplayOutputUnsupportedMode;
    }
}

pub fn activateDisplayInterface(interface_type: u8) Error!void {
    if (interface_type == abi.display_interface_none) return;
    ensureDisplayReady();
    const display_state = display_output.statePtr();
    if (display_output.stateInterfaceType() == interface_type and
        (display_state.connected == 1 or display_state.controller != abi.display_controller_virtio_gpu))
    {
        return;
    }

    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForInterface(interface_type) catch return error.DisplayInterfaceMismatch;
        } else if (!display_output.selectOutputInterface(interface_type)) {
            return error.DisplayInterfaceMismatch;
        }
    } else if (display_output.stateInterfaceType() == interface_type) {
        return;
    }

    const refreshed = display_output.statePtr();
    if (display_output.stateInterfaceType() != interface_type) return error.DisplayInterfaceMismatch;
    if (refreshed.controller == abi.display_controller_virtio_gpu and refreshed.connected != 1) {
        return error.DisplayInterfaceMismatch;
    }
}

pub fn activateDisplayInterfacePreferred(interface_type: u8) Error!void {
    if (interface_type == abi.display_interface_none) return;
    ensureDisplayReady();
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForInterfacePreferred(interface_type) catch |err| switch (err) {
                error.NoConnectedScanout => return error.DisplayInterfaceMismatch,
                error.UnsupportedMode, error.FramebufferTooLarge => return error.DisplayOutputUnsupportedMode,
                else => return error.DisplayInterfaceMismatch,
            };
        } else {
            if (!display_output.selectOutputInterface(interface_type)) return error.DisplayInterfaceMismatch;
            if (!display_output.setOutputPreferredMode(@as(u16, display_output.statePtr().active_scanout))) {
                return error.DisplayOutputUnsupportedMode;
            }
        }
    } else {
        if (display_output.stateInterfaceType() != interface_type) return error.DisplayInterfaceMismatch;
        const mode = display_output.preferredMode(@as(u16, display_state.active_scanout)) orelse return error.DisplayOutputUnsupportedMode;
        ensureDisplayReadyForMode(mode.width, mode.height) catch return error.DisplayOutputUnsupportedMode;
    }

    const refreshed = display_output.statePtr();
    if (display_output.stateInterfaceType() != interface_type) return error.DisplayInterfaceMismatch;
    if (refreshed.controller == abi.display_controller_virtio_gpu and refreshed.connected != 1) {
        return error.DisplayInterfaceMismatch;
    }
    const preferred_width = if (refreshed.preferred_width != 0) refreshed.preferred_width else refreshed.current_width;
    const preferred_height = if (refreshed.preferred_height != 0) refreshed.preferred_height else refreshed.current_height;
    if (refreshed.current_width != preferred_width or refreshed.current_height != preferred_height) {
        return error.DisplayOutputUnsupportedMode;
    }
}

pub fn setDisplayInterfaceMode(interface_type: u8, width: u16, height: u16) Error!void {
    if (interface_type == abi.display_interface_none) return error.DisplayInterfaceMismatch;
    ensureDisplayReady();
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForInterfaceMode(@intCast(interface_type), width, height) catch |err| switch (err) {
                error.NoConnectedScanout => return error.DisplayInterfaceMismatch,
                error.UnsupportedMode, error.FramebufferTooLarge => return error.DisplayOutputUnsupportedMode,
                else => return error.DisplayInterfaceMismatch,
            };
        } else {
            if (display_output.outputModeCountForInterface(interface_type) == 0) return error.DisplayInterfaceMismatch;
            if (!display_output.setOutputModeForInterface(interface_type, width, height)) {
                return error.DisplayOutputUnsupportedMode;
            }
        }
    } else {
        if (display_output.stateInterfaceType() != interface_type) return error.DisplayInterfaceMismatch;
        ensureDisplayReadyForMode(width, height) catch return error.DisplayOutputUnsupportedMode;
    }

    const refreshed = display_output.statePtr();
    if (display_output.stateInterfaceType() != interface_type) return error.DisplayInterfaceMismatch;
    if (refreshed.controller == abi.display_controller_virtio_gpu and refreshed.connected != 1) {
        return error.DisplayInterfaceMismatch;
    }
    if (refreshed.current_width != width or refreshed.current_height != height) {
        return error.DisplayOutputUnsupportedMode;
    }
}

pub fn activateDisplayInterfaceMode(interface_type: u8, mode_index: u16) Error!void {
    if (interface_type == abi.display_interface_none) return error.DisplayInterfaceMismatch;
    ensureDisplayReady();
    if (pal_framebuffer.displayOutputModeCountForInterface(interface_type) == 0) return error.DisplayInterfaceMismatch;
    const mode = pal_framebuffer.displayOutputModeForInterface(interface_type, mode_index) orelse return error.DisplayOutputUnsupportedMode;
    pal_framebuffer.activateDisplayInterfaceMode(interface_type, mode_index) catch |err| switch (err) {
        error.NotFound => return error.DisplayInterfaceMismatch,
        error.UnsupportedMode => return error.DisplayOutputUnsupportedMode,
    };
    const refreshed = display_output.statePtr();
    if (display_output.stateInterfaceType() != interface_type) return error.DisplayInterfaceMismatch;
    if (refreshed.controller == abi.display_controller_virtio_gpu and refreshed.connected != 1) {
        return error.DisplayInterfaceMismatch;
    }
    if (refreshed.current_width != mode.width or refreshed.current_height != mode.height) {
        return error.DisplayOutputUnsupportedMode;
    }
}

pub fn activateDisplayOutput(index: u16) Error!void {
    ensureDisplayReady();
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForOutputIndex(@intCast(index)) catch return error.DisplayOutputNotFound;
        } else if (!display_output.selectOutputIndex(index)) {
            return error.DisplayOutputNotFound;
        }
    } else if (!display_output.selectOutputIndex(index)) {
        return error.DisplayOutputNotFound;
    }
    const refreshed = display_output.statePtr();
    if (refreshed.active_scanout != @as(u8, @intCast(index)) or refreshed.connected != 1) {
        return error.DisplayOutputNotFound;
    }
}

pub fn activateDisplayOutputPreferred(index: u16) Error!void {
    ensureDisplayReady();
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForOutputIndexPreferred(@intCast(index)) catch |err| switch (err) {
                error.NoConnectedScanout => return error.DisplayOutputNotFound,
                error.UnsupportedMode, error.FramebufferTooLarge => return error.DisplayOutputUnsupportedMode,
                else => return error.DisplayOutputNotFound,
            };
        } else if (!display_output.setOutputPreferredMode(index)) {
            return error.DisplayOutputUnsupportedMode;
        }
    } else {
        if (index != 0) return error.DisplayOutputNotFound;
        const mode = display_output.preferredMode(index) orelse return error.DisplayOutputUnsupportedMode;
        ensureDisplayReadyForMode(mode.width, mode.height) catch return error.DisplayOutputUnsupportedMode;
    }

    const refreshed = display_output.statePtr();
    if (refreshed.active_scanout != @as(u8, @intCast(index)) or refreshed.connected != 1) {
        return error.DisplayOutputNotFound;
    }
    const preferred_width = if (refreshed.preferred_width != 0) refreshed.preferred_width else refreshed.current_width;
    const preferred_height = if (refreshed.preferred_height != 0) refreshed.preferred_height else refreshed.current_height;
    if (refreshed.current_width != preferred_width or refreshed.current_height != preferred_height) {
        return error.DisplayOutputUnsupportedMode;
    }
}

pub fn setDisplayOutputMode(index: u16, width: u16, height: u16) Error!void {
    ensureDisplayReady();
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForOutputIndexMode(@intCast(index), width, height) catch |err| switch (err) {
                error.NoConnectedScanout => return error.DisplayOutputNotFound,
                error.UnsupportedMode, error.FramebufferTooLarge => return error.DisplayOutputUnsupportedMode,
                else => return error.DisplayOutputNotFound,
            };
        } else {
            const entry = display_output.outputEntry(index);
            if (index >= display_output.outputCount() or entry.connected == 0) {
                return error.DisplayOutputNotFound;
            }
            if (!display_output.setOutputMode(index, width, height)) {
                return error.DisplayOutputUnsupportedMode;
            }
        }
    } else {
        if (index != 0) return error.DisplayOutputNotFound;
        framebuffer_console.setMode(width, height) catch return error.DisplayOutputUnsupportedMode;
    }
    const refreshed = display_output.statePtr();
    if (refreshed.active_scanout != @as(u8, @intCast(index)) or refreshed.connected != 1) {
        return error.DisplayOutputNotFound;
    }
    if (refreshed.current_width != width or refreshed.current_height != height) {
        return error.DisplayOutputUnsupportedMode;
    }
}

pub fn activateDisplayOutputMode(index: u16, mode_index: u16) Error!void {
    ensureDisplayReady();
    const mode = pal_framebuffer.displayOutputMode(index, mode_index) orelse return error.DisplayOutputUnsupportedMode;
    pal_framebuffer.activateDisplayOutputMode(index, mode_index) catch |err| switch (err) {
        error.NotFound => return error.DisplayOutputNotFound,
        error.UnsupportedMode => return error.DisplayOutputUnsupportedMode,
    };
    const refreshed = display_output.statePtr();
    if (refreshed.active_scanout != @as(u8, @intCast(index)) or refreshed.connected != 1) {
        return error.DisplayOutputNotFound;
    }
    if (refreshed.current_width != mode.width or refreshed.current_height != mode.height) {
        return error.DisplayOutputUnsupportedMode;
    }
}

fn displayControllerName(value: u8) []const u8 {
    return switch (value) {
        abi.display_controller_bochs_bga => "bochs-bga",
        abi.display_controller_virtio_gpu => "virtio-gpu",
        else => "none",
    };
}

fn displayConnectorName(value: u8) []const u8 {
    return switch (value) {
        abi.display_connector_displayport => "displayport",
        abi.display_connector_hdmi => "hdmi",
        abi.display_connector_embedded_displayport => "embedded-displayport",
        abi.display_connector_virtual => "virtual",
        else => "none",
    };
}

fn displayInterfaceName(value: u8) []const u8 {
    return display_output.interfaceName(value);
}

fn capabilityBit(value: u16, flag: u16) u8 {
    return if ((value & flag) != 0) 1 else 0;
}

fn appendDisplayOutputCapabilityLine(buffer: anytype, index: u16) !void {
    const entry = display_output.outputEntry(index);
    const capability_flags = entry.capability_flags;
    try buffer.appendFmt(
        "index={d} scanout={d} connector={s} interface={s} declared_interface={s} connected={d} digital={d} preferred={d} cea={d} audio={d} hdmi_vendor={d} displayid={d} underscan={d} ycbcr444={d} ycbcr422={d} capabilities=0x{x}\n",
        .{
            index,
            entry.scanout_index,
            displayConnectorName(entry.connector_type),
            displayInterfaceName(display_output.outputInterfaceType(index)),
            displayInterfaceName(display_output.outputDeclaredInterfaceType(index)),
            entry.connected,
            capabilityBit(capability_flags, abi.display_capability_digital_input),
            capabilityBit(capability_flags, abi.display_capability_preferred_timing),
            capabilityBit(capability_flags, abi.display_capability_cea_extension),
            capabilityBit(capability_flags, abi.display_capability_basic_audio),
            capabilityBit(capability_flags, abi.display_capability_hdmi_vendor_data),
            capabilityBit(capability_flags, abi.display_capability_displayid_extension),
            capabilityBit(capability_flags, abi.display_capability_underscan),
            capabilityBit(capability_flags, abi.display_capability_ycbcr444),
            capabilityBit(capability_flags, abi.display_capability_ycbcr422),
            capability_flags,
        },
    );
}

fn appendDisplayOutputDetailLine(buffer: anytype, index: u16) !void {
    const entry = display_output.outputEntry(index);
    const capability_flags = entry.capability_flags;
    try buffer.appendFmt(
        "index={d} scanout={d} connector={s} interface={s} declared_interface={s} connected={d} current={d}x{d} preferred={d}x{d} name={s} manufacturer={s} week={d} year={d} edid={d}.{d} extensions={d} physical={d}x{d}mm audio={d} hdmi_vendor={d} displayid={d} capabilities=0x{x}\n",
        .{
            index,
            entry.scanout_index,
            displayConnectorName(entry.connector_type),
            displayInterfaceName(display_output.outputInterfaceType(index)),
            displayInterfaceName(display_output.outputDeclaredInterfaceType(index)),
            entry.connected,
            entry.current_width,
            entry.current_height,
            entry.preferred_width,
            entry.preferred_height,
            display_output.outputDisplayName(index),
            display_output.outputManufacturerName(index),
            display_output.outputManufactureWeek(index),
            display_output.outputManufactureYear(index),
            display_output.outputEdidVersion(index),
            display_output.outputEdidRevision(index),
            display_output.outputExtensionCount(index),
            entry.physical_width_mm,
            entry.physical_height_mm,
            if ((capability_flags & abi.display_capability_basic_audio) != 0) @as(u8, 1) else @as(u8, 0),
            if ((capability_flags & abi.display_capability_hdmi_vendor_data) != 0) @as(u8, 1) else @as(u8, 0),
            if ((capability_flags & abi.display_capability_displayid_extension) != 0) @as(u8, 1) else @as(u8, 0),
            capability_flags,
        },
    );
}

fn appendDisplayModeLine(buffer: anytype, mode_index: u16, mode: pal_framebuffer.DisplayOutputMode) !void {
    try buffer.appendFmt(
        "mode {d} {d}x{d} refresh={d}\n",
        .{ mode_index, mode.width, mode.height, mode.refresh_hz },
    );
}

fn parseCommand(command: []const u8) Error!ParsedCommand {
    const trimmed = std.mem.trim(u8, command, " \t\r\n");
    if (trimmed.len == 0) return error.MissingCommand;

    const name = try parseFirstArg(trimmed);
    return .{
        .name = name.arg,
        .rest = name.rest,
    };
}

fn parseFirstArg(text: []const u8) Error!ParsedArg {
    const trimmed = trimLeftWhitespace(text);
    if (trimmed.len == 0) return error.MissingPath;

    const quote = trimmed[0];
    if (quote == '"' or quote == '\'') {
        const end_index = findQuotedArgumentEnd(trimmed, quote) catch return error.InvalidQuotedArgument;
        const arg = trimmed[1..end_index];
        const rest = trimLeftWhitespace(trimmed[end_index + 1 ..]);
        return .{ .arg = arg, .rest = rest };
    }

    var idx: usize = 0;
    while (idx < trimmed.len) : (idx += 1) {
        if (trimmed[idx] == '\\' and idx + 1 < trimmed.len and isShellEscapable(trimmed[idx + 1])) {
            idx += 1;
            continue;
        }
        if (std.ascii.isWhitespace(trimmed[idx])) break;
    }
    return .{
        .arg = trimmed[0..idx],
        .rest = trimLeftWhitespace(trimmed[idx..]),
    };
}

fn findQuotedArgumentEnd(text: []const u8, quote: u8) Error!usize {
    var idx: usize = 1;
    while (idx < text.len) : (idx += 1) {
        const ch = text[idx];
        if (ch == '\\' and idx + 1 < text.len and isShellEscapable(text[idx + 1])) {
            idx += 1;
            continue;
        }
        if (ch != quote) continue;
        if (idx + 1 < text.len and !std.ascii.isWhitespace(text[idx + 1])) return error.InvalidQuotedArgument;
        return idx;
    }
    return error.InvalidQuotedArgument;
}

fn parseBoolArg(text: []const u8) Error!bool {
    if (std.mem.eql(u8, text, "1") or std.ascii.eqlIgnoreCase(text, "true") or std.ascii.eqlIgnoreCase(text, "yes")) {
        return true;
    }
    if (std.mem.eql(u8, text, "0") or std.ascii.eqlIgnoreCase(text, "false") or std.ascii.eqlIgnoreCase(text, "no")) {
        return false;
    }
    return error.InvalidQuotedArgument;
}

fn trimLeftWhitespace(text: []const u8) []const u8 {
    var index: usize = 0;
    while (index < text.len and std.ascii.isWhitespace(text[index])) : (index += 1) {}
    return text[index..];
}

fn ensureParentDirectory(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0 or std.mem.eql(u8, parent, "/")) return;
    try filesystem.createDirPath(parent);
}

fn runLaunchProfile(
    package_name: []const u8,
    operation: []const u8,
    persist_state: bool,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = package_store.loadLaunchProfile(package_name, &entrypoint_buf) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };

    if (profile.trustBundle().len != 0) {
        trust_store.selectBundle(profile.trustBundle(), 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
            return;
        };
    }
    ensureDisplayReadyForMode(profile.display_width, profile.display_height) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };
    if (profile.connector_type != abi.display_connector_none) {
        activateDisplayConnector(profile.connector_type) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
            return;
        };
    }
    const framebuffer_state = framebuffer_console.statePtr();
    if (framebuffer_state.width != profile.display_width or framebuffer_state.height != profile.display_height) {
        framebuffer_console.setMode(profile.display_width, profile.display_height) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
            return;
        };
    }
    const stdout_before = stdout_buffer.list.items.len;
    const stderr_before = stderr_buffer.list.items.len;
    try executeScriptPath(profile.entrypoint, operation, stdout_buffer, stderr_buffer, exit_code, allocator, depth);

    if (persist_state) {
        const stdout_delta = stdout_buffer.list.items[stdout_before..];
        const stderr_delta = stderr_buffer.list.items[stderr_before..];
        app_runtime.writeLastRun(package_name, profile, exit_code.*, stdout_delta, stderr_delta, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
            return;
        };
    }
}

fn runAutorunProfiles(
    operation: []const u8,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    const autorun_list = app_runtime.autorunListAlloc(allocator, 1024) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };
    defer allocator.free(autorun_list);

    var lines = std.mem.splitScalar(u8, autorun_list, '\n');
    while (lines.next()) |raw_line| {
        const package_name = std.mem.trim(u8, raw_line, " \t\r");
        if (package_name.len == 0) continue;
        try runLaunchProfile(package_name, operation, true, stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        if (exit_code.* != 0) return;
    }
}

fn runWorkspace(
    workspace_name: []const u8,
    operation: []const u8,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    const suite_name = workspace_runtime.suiteNameAlloc(allocator, workspace_name, 128) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };
    defer allocator.free(suite_name);

    workspace_runtime.applyWorkspace(workspace_name, 0) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };

    const stdout_before = stdout_buffer.list.items.len;
    const stderr_before = stderr_buffer.list.items.len;
    try runSuiteProfiles(suite_name, operation, stdout_buffer, stderr_buffer, exit_code, allocator, depth);
    const stdout_delta = stdout_buffer.list.items[stdout_before..];
    const stderr_delta = stderr_buffer.list.items[stderr_before..];
    workspace_runtime.writeLastRun(workspace_name, exit_code.*, stdout_delta, stderr_delta, 0) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };
}

fn runWorkspaceSuite(
    suite_name: []const u8,
    operation: []const u8,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    const suite_entries = workspace_runtime.suiteEntriesAlloc(allocator, suite_name, 1024) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };
    defer allocator.free(suite_entries);

    var lines = std.mem.splitScalar(u8, suite_entries, '\n');
    while (lines.next()) |raw_line| {
        const workspace_name = std.mem.trim(u8, raw_line, " \t\r");
        if (workspace_name.len == 0) continue;
        try runWorkspace(workspace_name, operation, stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        if (exit_code.* != 0) return;
    }
}

fn runWorkspaceAutorun(
    operation: []const u8,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    const autorun_list = workspace_runtime.autorunListAlloc(allocator, 1024) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };
    defer allocator.free(autorun_list);

    var lines = std.mem.splitScalar(u8, autorun_list, '\n');
    while (lines.next()) |raw_line| {
        const workspace_name = std.mem.trim(u8, raw_line, " \t\r");
        if (workspace_name.len == 0) continue;
        try runWorkspace(workspace_name, operation, stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        if (exit_code.* != 0) return;
    }
}

fn runSuiteProfiles(
    suite_name: []const u8,
    operation: []const u8,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    const suite_entries = app_runtime.suiteEntriesAlloc(allocator, suite_name, 1024) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };
    defer allocator.free(suite_entries);

    app_runtime.applySuite(suite_name, 0) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };

    var lines = std.mem.splitScalar(u8, suite_entries, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        const separator = std.mem.indexOfScalar(u8, line, ':') orelse {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: InvalidAppSuite\n", .{operation});
            return;
        };
        const package_name = line[0..separator];
        if (package_name.len == 0) {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: InvalidAppSuite\n", .{operation});
            return;
        }
        try runLaunchProfile(package_name, operation, true, stdout_buffer, stderr_buffer, exit_code, allocator, depth);
        if (exit_code.* != 0) return;
    }
}

fn executeScriptPath(
    path: []const u8,
    operation: []const u8,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    if (depth >= max_script_depth) {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: ScriptDepthExceeded\n", .{operation});
        return;
    }

    const script = filesystem.readFileAlloc(allocator, path, 4096) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };
    defer allocator.free(script);

    try executeScriptContents(script, operation, stdout_buffer, stderr_buffer, exit_code, null, allocator, depth);
}

fn executeScriptContents(
    script: []const u8,
    operation: []const u8,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    stdin_content: ?[]const u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    if (depth >= max_script_depth) {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: ScriptDepthExceeded\n", .{operation});
        return;
    }

    try filesystem.beginDeferredPersist();
    var finish_deferred_persist = true;
    defer if (finish_deferred_persist) {
        filesystem.endDeferredPersist() catch |err| {
            exit_code.* = 1;
            stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) }) catch {};
        };
    };

    var start: usize = 0;
    var quote: u8 = 0;
    var command_count: usize = 0;
    var idx: usize = 0;
    while (idx <= script.len) : (idx += 1) {
        const at_end = idx == script.len;
        if (!at_end) {
            const ch = script[idx];
            if (quote != 0) {
                if (ch == '\\' and idx + 1 < script.len and isShellEscapable(script[idx + 1])) {
                    idx += 1;
                    continue;
                }
                if (ch == quote) quote = 0;
                continue;
            }
            if (ch == '\\' and idx + 1 < script.len and isShellEscapable(script[idx + 1])) {
                idx += 1;
                continue;
            }
            if (ch == '"' or ch == '\'') {
                quote = ch;
                continue;
            }
            if (ch != ';' and ch != '\n') continue;
        }

        const line = std.mem.trim(u8, script[start..idx], " \t\r");
        start = idx + 1;
        if (line.len == 0 or line[0] == '#') continue;
        command_count += 1;
        if (command_count > max_shell_command_count) {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: ShellCommandLimitExceeded\n", .{operation});
            return;
        }

        try executeCommandLine(line, operation, stdout_buffer, stderr_buffer, exit_code, stdin_content, allocator, depth);
        if (exit_code.* != 0) return;
    }

    try filesystem.endDeferredPersist();
    finish_deferred_persist = false;
}

fn executeWithRedirection(
    parsed: ParsedCommand,
    redirect_stream: RedirectStream,
    redirect_path: []const u8,
    append_mode: bool,
    operation: []const u8,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    stdin_content: ?[]const u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    const stream_limit = switch (redirect_stream) {
        .stdout => stdout_buffer.limit,
        .stderr => stderr_buffer.limit,
    };
    var redirected_stream = OutputBuffer.init(allocator, stream_limit, false);
    defer redirected_stream.deinit();

    switch (redirect_stream) {
        .stdout => try execute(parsed, &redirected_stream, stderr_buffer, exit_code, stdin_content, allocator, depth),
        .stderr => try execute(parsed, stdout_buffer, &redirected_stream, exit_code, stdin_content, allocator, depth),
    }
    if (redirect_stream == .stdout and exit_code.* != 0) return;

    ensureParentDirectory(redirect_path) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };

    if (append_mode) {
        const existing = filesystem.readFileAlloc(allocator, redirect_path, stream_limit) catch |err| switch (err) {
            error.FileNotFound => null,
            else => {
                exit_code.* = 1;
                try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
                return;
            },
        };
        defer if (existing) |bytes| allocator.free(bytes);

        const existing_len: usize = if (existing) |bytes| bytes.len else 0;
        if (existing_len + redirected_stream.list.items.len > stream_limit) {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: StreamTooLong\n", .{operation});
            return;
        }

        var combined = std.ArrayList(u8).empty;
        defer combined.deinit(allocator);
        if (existing) |bytes| try combined.appendSlice(allocator, bytes);
        try combined.appendSlice(allocator, redirected_stream.list.items);
        filesystem.writeFile(redirect_path, combined.items, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
            return;
        };
        return;
    }

    filesystem.writeFile(redirect_path, redirected_stream.list.items, 0) catch |err| {
        exit_code.* = 1;
        try stderr_buffer.appendFmt("{s} failed: {s}\n", .{ operation, @errorName(err) });
        return;
    };
}

fn parseShellLine(line: []const u8) Error!ParsedShellLine {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len == 0) return error.MissingCommand;

    var quote: u8 = 0;
    var command_end: usize = trimmed.len;
    var idx: usize = 0;
    while (idx < trimmed.len) : (idx += 1) {
        const ch = trimmed[idx];
        if (quote != 0) {
            if (ch == '\\' and idx + 1 < trimmed.len and isShellEscapable(trimmed[idx + 1])) {
                idx += 1;
                continue;
            }
            if (ch == quote) quote = 0;
            continue;
        }
        if (ch == '\\' and idx + 1 < trimmed.len and isShellEscapable(trimmed[idx + 1])) {
            idx += 1;
            continue;
        }
        if (ch == '"' or ch == '\'') {
            quote = ch;
            continue;
        }
        if (ch == '<') {
            command_end = idx;
            break;
        }
        if (ch == '>') {
            command_end = idx;
            if (idx > 0 and (trimmed[idx - 1] == '1' or trimmed[idx - 1] == '2') and isRedirectionFdPrefixBoundary(trimmed, idx - 1)) {
                command_end = idx - 1;
            }
            break;
        }
    }

    const command = std.mem.trim(u8, trimmed[0..command_end], " \t\r");
    if (command.len == 0) return error.InvalidRedirection;
    if (command_end == trimmed.len) return .{ .command = command };

    var parsed = ParsedShellLine{ .command = command };
    var rest = trimmed[command_end..];
    while (true) {
        rest = trimLeftWhitespace(rest);
        if (rest.len == 0) return parsed;

        if (rest[0] == '<') {
            if (parsed.input_path != null) return error.InvalidRedirection;
            const input_arg = parseFirstArg(trimLeftWhitespace(rest[1..])) catch return error.InvalidRedirection;
            if (input_arg.arg.len == 0) return error.InvalidRedirection;
            parsed.input_path = input_arg.arg;
            rest = input_arg.rest;
            continue;
        }

        var redirect_stream: RedirectStream = .stdout;
        var append_mode = false;
        var operator_len: usize = 0;
        if (rest[0] == '>') {
            append_mode = rest.len > 1 and rest[1] == '>';
            operator_len = if (append_mode) 2 else 1;
        } else if ((rest[0] == '1' or rest[0] == '2') and rest.len > 1 and rest[1] == '>' and isRedirectionFdPrefixBoundary(rest, 0)) {
            redirect_stream = if (rest[0] == '2') .stderr else .stdout;
            append_mode = rest.len > 2 and rest[2] == '>';
            operator_len = if (append_mode) 3 else 2;
        } else {
            return error.InvalidRedirection;
        }

        if (parsed.redirect_path != null) return error.InvalidRedirection;
        const redirect_arg = parseFirstArg(trimLeftWhitespace(rest[operator_len..])) catch return error.InvalidRedirection;
        if (redirect_arg.arg.len == 0) return error.InvalidRedirection;
        parsed.redirect_path = redirect_arg.arg;
        parsed.redirect_stream = redirect_stream;
        parsed.append = append_mode;
        rest = redirect_arg.rest;
    }
}

fn isShellEscapable(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', ';', '<', '>', '\\', '"', '\'', '\n' => true,
        else => false,
    };
}

fn isRedirectionFdPrefixBoundary(text: []const u8, digit_index: usize) bool {
    if (digit_index == 0) return true;
    return std.ascii.isWhitespace(text[digit_index - 1]);
}

fn unescapeShellTextAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, text, '\\') == null) return allocator.dupe(u8, text);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var idx: usize = 0;
    while (idx < text.len) : (idx += 1) {
        const ch = text[idx];
        if (ch == '\\' and idx + 1 < text.len and isShellEscapable(text[idx + 1])) {
            idx += 1;
            try out.append(allocator, text[idx]);
            continue;
        }
        try out.append(allocator, ch);
    }
    return out.toOwnedSlice(allocator);
}

fn normalizeShellCommandTextAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, text, '\\') == null) return allocator.dupe(u8, text);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var quote: u8 = 0;
    var idx: usize = 0;
    while (idx < text.len) : (idx += 1) {
        const ch = text[idx];
        if (ch == '\\' and idx + 1 < text.len and isShellEscapable(text[idx + 1])) {
            const next = text[idx + 1];
            if (quote != 0 and (next == quote or next == '\\')) {
                try out.append(allocator, ch);
                idx += 1;
                try out.append(allocator, next);
                continue;
            }
            if (next == ' ' or next == '\t') {
                try out.append(allocator, ch);
                idx += 1;
                try out.append(allocator, next);
                continue;
            }
            idx += 1;
            try out.append(allocator, next);
            continue;
        }

        if (ch == '"' or ch == '\'') {
            if (quote == 0) {
                quote = ch;
            } else if (quote == ch) {
                quote = 0;
            }
        }
        try out.append(allocator, ch);
    }

    return out.toOwnedSlice(allocator);
}

fn expandShellPatternAlloc(
    allocator: std.mem.Allocator,
    pattern: []const u8,
    max_bytes: usize,
) Error![]u8 {
    const trimmed = std.mem.trim(u8, pattern, " \t\r\n");
    if (trimmed.len == 0) return error.MissingPath;
    if (trimmed[0] != '/') return error.UnsupportedPattern;

    if (!containsWildcard(trimmed)) {
        _ = filesystem.statSummary(trimmed) catch return error.NoMatches;
        return std.fmt.allocPrint(allocator, "{s}\n", .{trimmed});
    }

    if (std.mem.eql(u8, trimmed, "/")) return error.UnsupportedPattern;

    var segments_storage: [max_shell_glob_segments][]const u8 = undefined;
    var segment_count: usize = 0;
    var segments_iter = std.mem.splitScalar(u8, trimmed[1..], '/');
    while (segments_iter.next()) |segment| {
        if (segment.len == 0) return error.UnsupportedPattern;
        if (segment_count >= segments_storage.len) return error.UnsupportedPattern;
        segments_storage[segment_count] = segment;
        segment_count += 1;
    }
    if (segment_count == 0) return error.UnsupportedPattern;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try expandShellPatternSegments(allocator, &out, max_bytes, "/", segments_storage[0..segment_count], 0);
    if (out.items.len == 0) return error.NoMatches;
    return out.toOwnedSlice(allocator);
}

fn containsWildcard(text: []const u8) bool {
    return std.mem.indexOfAny(u8, text, "*?") != null;
}

fn childFromListingLine(line: []const u8) ?ListingChild {
    if (std.mem.startsWith(u8, line, "dir ")) return .{
        .name = line[4..],
        .kind = .directory,
    };
    if (std.mem.startsWith(u8, line, "file ")) {
        const rest = line[5..];
        const space_index = std.mem.indexOfScalar(u8, rest, ' ') orelse return null;
        return .{
            .name = rest[0..space_index],
            .kind = .file,
        };
    }
    return null;
}

fn expandShellPatternSegments(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    max_bytes: usize,
    parent: []const u8,
    segments: []const []const u8,
    segment_index: usize,
) Error!void {
    const segment = segments[segment_index];
    const is_last = segment_index + 1 == segments.len;

    if (containsWildcard(segment)) {
        const listing = filesystem.listDirectoryAlloc(allocator, parent, max_bytes) catch |err| switch (err) {
            error.FileNotFound, error.NotDirectory => return,
            else => return err,
        };
        defer allocator.free(listing);

        var lines = std.mem.splitScalar(u8, listing, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const child = childFromListingLine(line) orelse continue;
            if (!globMatches(segment, child.name)) continue;

            const child_path = try joinShellChildPath(allocator, parent, child.name);
            defer allocator.free(child_path);

            if (is_last) {
                try appendExpandedShellPath(allocator, out, max_bytes, child_path);
                continue;
            }
            if (child.kind != .directory) continue;
            try expandShellPatternSegments(allocator, out, max_bytes, child_path, segments, segment_index + 1);
        }
        return;
    }

    const child_path = try joinShellChildPath(allocator, parent, segment);
    defer allocator.free(child_path);
    const stat = filesystem.statSummary(child_path) catch |err| switch (err) {
        error.FileNotFound, error.NotDirectory => return,
        else => return err,
    };
    if (is_last) {
        try appendExpandedShellPath(allocator, out, max_bytes, child_path);
        return;
    }
    if (stat.kind != .directory) return;
    try expandShellPatternSegments(allocator, out, max_bytes, child_path, segments, segment_index + 1);
}

fn joinShellChildPath(allocator: std.mem.Allocator, parent: []const u8, child_name: []const u8) ![]u8 {
    if (std.mem.eql(u8, parent, "/")) return std.fmt.allocPrint(allocator, "/{s}", .{child_name});
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ parent, child_name });
}

fn appendExpandedShellPath(allocator: std.mem.Allocator, out: *std.ArrayList(u8), max_bytes: usize, path: []const u8) !void {
    if (out.items.len + path.len + 1 > max_bytes) return error.StreamTooLong;
    try out.appendSlice(allocator, path);
    try out.append(allocator, '\n');
}

fn globMatches(pattern: []const u8, text: []const u8) bool {
    return globMatchesInner(pattern, text, 0, 0);
}

fn globMatchesInner(pattern: []const u8, text: []const u8, pattern_index: usize, text_index: usize) bool {
    if (pattern_index == pattern.len) return text_index == text.len;

    return switch (pattern[pattern_index]) {
        '*' => blk: {
            var idx = text_index;
            while (idx <= text.len) : (idx += 1) {
                if (globMatchesInner(pattern, text, pattern_index + 1, idx)) break :blk true;
            }
            break :blk false;
        },
        '?' => if (text_index < text.len) globMatchesInner(pattern, text, pattern_index + 1, text_index + 1) else false,
        else => if (text_index < text.len and pattern[pattern_index] == text[text_index])
            globMatchesInner(pattern, text, pattern_index + 1, text_index + 1)
        else
            false,
    };
}

fn writeCommandError(stderr_buffer: *OutputBuffer, err: anyerror, usage: []const u8) Error!void {
    switch (err) {
        error.MissingCommand, error.MissingPath, error.InvalidQuotedArgument, error.InvalidRedirection => {
            try stderr_buffer.appendFmt("usage: {s}\n", .{usage});
        },
        else => try stderr_buffer.appendFmt("{s}\n", .{@errorName(err)}),
    }
}

fn parseStorageBackendArg(text: []const u8) Error!u8 {
    if (std.fmt.parseUnsigned(u8, text, 10)) |index| {
        return switch (index) {
            0 => abi.storage_backend_ram_disk,
            1 => abi.storage_backend_ata_pio,
            2 => abi.storage_backend_virtio_block,
            else => error.OutOfRange,
        };
    } else |_| {}

    if (std.ascii.eqlIgnoreCase(text, "ram_disk") or std.ascii.eqlIgnoreCase(text, "ram-disk")) return abi.storage_backend_ram_disk;
    if (std.ascii.eqlIgnoreCase(text, "ata_pio") or std.ascii.eqlIgnoreCase(text, "ata-pio")) return abi.storage_backend_ata_pio;
    if (std.ascii.eqlIgnoreCase(text, "virtio_block") or std.ascii.eqlIgnoreCase(text, "virtio-block")) return abi.storage_backend_virtio_block;
    return error.OutOfRange;
}

fn appendStorageBackendInfo(stdout_buffer: *OutputBuffer, backend: u8) Error!void {
    var index: usize = 0;
    while (index < storage_backend_registry.entryCount()) : (index += 1) {
        const entry = storage_backend_registry.entry(index) orelse continue;
        if (entry.backend != backend) continue;
        try appendStorageBackendEntry(stdout_buffer, index, entry);
        return;
    }
    return error.FileNotFound;
}

fn appendStorageBackendEntry(stdout_buffer: *OutputBuffer, index: usize, entry: storage_backend_registry.Entry) Error!void {
    if (entry.selected_partition == std.math.maxInt(u8)) {
        try stdout_buffer.appendFmt(
            "backend[{d}]=name={s} backend={s} available={d} selected={d} mounted={d} preferred_order={d} filesystem={s} block_size={d} block_count={d} logical_base_lba={d} partition_count={d} selected_partition=none\n",
            .{
                index,
                entry.nameSlice(),
                storage_registry.backendName(entry.backend),
                entry.available,
                entry.selected,
                entry.mounted,
                entry.preferred_order,
                storage_registry.filesystemKindName(entry.filesystem_kind),
                entry.block_size,
                entry.block_count,
                entry.logical_base_lba,
                entry.partition_count,
            },
        );
    } else {
        try stdout_buffer.appendFmt(
            "backend[{d}]=name={s} backend={s} available={d} selected={d} mounted={d} preferred_order={d} filesystem={s} block_size={d} block_count={d} logical_base_lba={d} partition_count={d} selected_partition={d}\n",
            .{
                index,
                entry.nameSlice(),
                storage_registry.backendName(entry.backend),
                entry.available,
                entry.selected,
                entry.mounted,
                entry.preferred_order,
                storage_registry.filesystemKindName(entry.filesystem_kind),
                entry.block_size,
                entry.block_count,
                entry.logical_base_lba,
                entry.partition_count,
                entry.selected_partition,
            },
        );
    }
}

fn appendStoragePartitions(stdout_buffer: *OutputBuffer) Error!void {
    const backend = storage_backend.activeBackend();
    const partition_count = storage_backend.partitionCount();
    const selected = storage_backend.selectedPartitionIndex();
    if (selected) |index| {
        try stdout_buffer.appendFmt(
            "backend={s} partition_count={d} selected={d} logical_base_lba={d}\n",
            .{ storage_registry.backendName(backend), partition_count, index, storage_backend.logicalBaseLba() },
        );
    } else {
        try stdout_buffer.appendFmt(
            "backend={s} partition_count={d} selected=none logical_base_lba={d}\n",
            .{ storage_registry.backendName(backend), partition_count, storage_backend.logicalBaseLba() },
        );
    }

    var index: u8 = 0;
    while (index < partition_count) : (index += 1) {
        const info = storage_backend.partitionInfo(index) orelse continue;
        try stdout_buffer.appendFmt(
            "partition[{d}] scheme={s} start_lba={d} sector_count={d} selected={d}\n",
            .{
                index,
                switch (info.scheme) {
                    .mbr => "mbr",
                    .gpt => "gpt",
                },
                info.start_lba,
                info.sector_count,
                if (selected != null and selected.? == index) @as(u8, 1) else @as(u8, 0),
            },
        );
    }
}

fn appendMountList(stdout_buffer: *OutputBuffer) Error!void {
    var index: usize = 0;
    while (index < filesystem.mountCount()) : (index += 1) {
        const entry = filesystem.mountEntry(index) orelse continue;
        try appendMountEntry(stdout_buffer, entry);
    }
}

fn appendMountInfo(stdout_buffer: *OutputBuffer, name: []const u8) Error!void {
    var index: usize = 0;
    while (index < filesystem.mountCount()) : (index += 1) {
        const entry = filesystem.mountEntry(index) orelse continue;
        if (!std.mem.eql(u8, entry.name[0..entry.name_len], name)) continue;
        try appendMountEntry(stdout_buffer, entry);
        return;
    }
    return error.FileNotFound;
}

fn appendMountEntry(stdout_buffer: *OutputBuffer, entry: @TypeOf(filesystem.mountEntry(0).?)) Error!void {
    try stdout_buffer.appendFmt(
        "mount name={s} path=/mnt/{s} target={s} modified_tick={d}\n",
        .{
            entry.name[0..entry.name_len],
            entry.name[0..entry.name_len],
            entry.target[0..entry.target_len],
            entry.modified_tick,
        },
    );
}

test "baremetal tool exec echoes to stdout and console" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    var result = try runCapture(std.testing.allocator, "echo tool-exec-ok", 256, 256);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("tool-exec-ok\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
    try std.testing.expectEqual(@as(u16, (@as(u16, 0x07) << 8) | 't'), vga_text_console.cell(0));
}

test "baremetal tool exec writes cats and stats files through baremetal filesystem" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    var mkdir_result = try runCapture(std.testing.allocator, "mkdir /tools/tmp", 256, 256);
    defer mkdir_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), mkdir_result.exit_code);

    var write_result = try runCapture(std.testing.allocator, "write-file /tools/tmp/tool.txt baremetal-tool", 256, 256);
    defer write_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), write_result.exit_code);

    var cat_result = try runCapture(std.testing.allocator, "cat /tools/tmp/tool.txt", 256, 256);
    defer cat_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), cat_result.exit_code);
    try std.testing.expectEqualStrings("baremetal-tool", cat_result.stdout);

    var stat_result = try runCapture(std.testing.allocator, "stat /tools/tmp/tool.txt", 256, 256);
    defer stat_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), stat_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, stat_result.stdout, "kind=file") != null);
    try std.testing.expect(std.mem.indexOf(u8, stat_result.stdout, "size=14") != null);
}

test "baremetal tool exec reports unknown commands on stderr" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    var result = try runCapture(std.testing.allocator, "missing-command", 256, 256);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u8, 127), result.exit_code);
    try std.testing.expectEqualStrings("", result.stdout);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown command") != null);
}

test "baremetal tool exec runs persisted scripts through the baremetal filesystem" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    try filesystem.init();
    try filesystem.createDirPath("/tools/scripts");
    try filesystem.writeFile(
        "/tools/scripts/bootstrap.oc",
        "# setup\nmkdir /tools/out\nwrite-file /tools/out/data.txt script-data\nstat /tools/out/data.txt\necho script-ok\n",
        0,
    );

    var result = try runCapture(std.testing.allocator, "run-script /tools/scripts/bootstrap.oc", 512, 256);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings(
        "created /tools/out\nwrote 11 bytes to /tools/out/data.txt\npath=/tools/out/data.txt kind=file size=11\nscript-ok\n",
        result.stdout,
    );
    try std.testing.expectEqualStrings("", result.stderr);

    const content = try filesystem.readFileAlloc(std.testing.allocator, "/tools/out/data.txt", 64);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("script-data", content);
}

test "baremetal tool exec runs packages from the canonical package layout" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    try package_store.installScriptPackage("demo", "mkdir /pkg/out\nwrite-file /pkg/out/data.txt package-data\necho package-ok\n", 0);

    var result = try runCapture(std.testing.allocator, "run-package demo", 512, 256);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("created /pkg/out\nwrote 12 bytes to /pkg/out/data.txt\npackage-ok\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);

    const content = try filesystem.readFileAlloc(std.testing.allocator, "/pkg/out/data.txt", 64);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("package-data", content);
}

test "baremetal tool exec lists directories and reads package metadata" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    try package_store.installScriptPackage("demo", "echo package-ok", 0);

    var list_result = try runCapture(std.testing.allocator, "ls /packages", 256, 256);
    defer list_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    try std.testing.expectEqualStrings("dir demo\n", list_result.stdout);

    var info_result = try runCapture(std.testing.allocator, "package-info demo", 512, 256);
    defer info_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), info_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "root=/packages/demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "script_bytes=15") != null);

    var app_result = try runCapture(std.testing.allocator, "package-app demo", 256, 256);
    defer app_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), app_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, app_result.stdout, "entrypoint=/packages/demo/bin/main.oc") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_result.stdout, "display_width=640") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_result.stdout, "display_height=400") != null);
}

test "baremetal tool exec verifies package manifest integrity and reports tampering" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    try package_store.installScriptPackage("verify-demo", "echo verify-demo", 1);
    try package_store.installPackageAsset("verify-demo", "config/app.json", "{\"mode\":\"verify\"}", 2);

    var verify_ok = try runCapture(std.testing.allocator, "package-verify verify-demo", 512, 256);
    defer verify_ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), verify_ok.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, verify_ok.stdout, "status=ok") != null);
    try std.testing.expect(std.mem.indexOf(u8, verify_ok.stdout, "asset_tree_checksum=") != null);

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const entrypoint = try package_store.entrypointPath("verify-demo", &entrypoint_buf);
    try filesystem.writeFile(entrypoint, "echo verify-dam0", 3);

    var verify_bad = try runCapture(std.testing.allocator, "package-verify verify-demo", 512, 256);
    defer verify_bad.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), verify_bad.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, verify_bad.stderr, "status=mismatch") != null);
    try std.testing.expect(std.mem.indexOf(u8, verify_bad.stderr, "field=script_checksum") != null);
}

test "baremetal tool exec lists and reads persisted package assets" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    try package_store.installScriptPackage("demo", "echo package-ok", 0);
    try package_store.installPackageAsset("demo", "config/app.json", "{\"mode\":\"tcp\"}", 1);

    var ls_result = try runCapture(std.testing.allocator, "package-ls demo", 256, 256);
    defer ls_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), ls_result.exit_code);
    try std.testing.expectEqualStrings("dir config\n", ls_result.stdout);

    var cat_result = try runCapture(std.testing.allocator, "package-cat demo config/app.json", 256, 256);
    defer cat_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), cat_result.exit_code);
    try std.testing.expectEqualStrings("{\"mode\":\"tcp\"}", cat_result.stdout);
}

test "baremetal tool exec manages persisted package releases" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    try package_store.installScriptPackage("demo", "echo release-one", 0);
    try package_store.installPackageAsset("demo", "config/app.json", "{\"mode\":\"one\"}", 1);

    var save_result = try runCapture(std.testing.allocator, "package-release-save demo r1", 256, 256);
    defer save_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_result.exit_code);
    try std.testing.expectEqualStrings("package release saved demo r1\n", save_result.stdout);

    try package_store.installScriptPackage("demo", "echo release-two", 2);
    try package_store.installPackageAsset("demo", "config/app.json", "{\"mode\":\"two\"}", 3);

    var save_result_two = try runCapture(std.testing.allocator, "package-release-save demo r2", 256, 256);
    defer save_result_two.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_result_two.exit_code);
    try std.testing.expectEqualStrings("package release saved demo r2\n", save_result_two.stdout);

    var info_result = try runCapture(std.testing.allocator, "package-release-info demo r2", 512, 256);
    defer info_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), info_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "release=r2") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "saved_seq=2") != null);

    var mutated_run = try runCapture(std.testing.allocator, "run-package demo", 256, 256);
    defer mutated_run.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), mutated_run.exit_code);
    try std.testing.expectEqualStrings("release-two\n", mutated_run.stdout);

    var list_result = try runCapture(std.testing.allocator, "package-release-list demo", 256, 256);
    defer list_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    try std.testing.expectEqualStrings("r1\nr2\n", list_result.stdout);

    var activate_result = try runCapture(std.testing.allocator, "package-release-activate demo r1", 256, 256);
    defer activate_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_result.exit_code);
    try std.testing.expectEqualStrings("package release activated demo r1\n", activate_result.stdout);

    var restored_run = try runCapture(std.testing.allocator, "run-package demo", 256, 256);
    defer restored_run.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), restored_run.exit_code);
    try std.testing.expectEqualStrings("release-one\n", restored_run.stdout);

    var restored_asset = try runCapture(std.testing.allocator, "package-cat demo config/app.json", 256, 256);
    defer restored_asset.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), restored_asset.exit_code);
    try std.testing.expectEqualStrings("{\"mode\":\"one\"}", restored_asset.stdout);

    var save_result_three = try runCapture(std.testing.allocator, "package-release-save demo r3", 256, 256);
    defer save_result_three.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_result_three.exit_code);
    try std.testing.expectEqualStrings("package release saved demo r3\n", save_result_three.stdout);

    var delete_result = try runCapture(std.testing.allocator, "package-release-delete demo r2", 256, 256);
    defer delete_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_result.exit_code);
    try std.testing.expectEqualStrings("package release deleted demo r2\n", delete_result.stdout);

    var list_after_delete = try runCapture(std.testing.allocator, "package-release-list demo", 256, 256);
    defer list_after_delete.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), list_after_delete.exit_code);
    try std.testing.expectEqualStrings("r1\nr3\n", list_after_delete.stdout);

    var prune_result = try runCapture(std.testing.allocator, "package-release-prune demo 1", 256, 256);
    defer prune_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), prune_result.exit_code);
    try std.testing.expectEqualStrings("package release pruned demo keep=1 deleted=1 kept=1\n", prune_result.stdout);

    var list_after_prune = try runCapture(std.testing.allocator, "package-release-list demo", 256, 256);
    defer list_after_prune.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), list_after_prune.exit_code);
    try std.testing.expectEqualStrings("r3\n", list_after_prune.stdout);
}

test "baremetal tool exec reports current display info and supported modes" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();

    var info_result = try runCapture(std.testing.allocator, "display-info", 256, 256);
    defer info_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), info_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "backend=bga") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "controller=bochs-bga") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "current=640x400") != null);

    var outputs_result = try runCapture(std.testing.allocator, "display-outputs", 256, 256);
    defer outputs_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), outputs_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, outputs_result.stdout, "output 0 scanout=0 connector=virtual interface=none connected=0 current=640x400 preferred=640x400") != null);

    var output_result = try runCapture(std.testing.allocator, "display-output 0", 256, 256);
    defer output_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), output_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output_result.stdout, "index=0 scanout=0 connector=virtual interface=none connected=0 current=640x400 preferred=640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_result.stdout, "mode_count=1") != null);

    var output_modes_result = try runCapture(std.testing.allocator, "display-output-modes 0", 256, 256);
    defer output_modes_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), output_modes_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output_modes_result.stdout, "mode 0 640x400 refresh=0") != null);

    var modes_result = try runCapture(std.testing.allocator, "display-modes", 256, 256);
    defer modes_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), modes_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, modes_result.stdout, "mode 0 640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, modes_result.stdout, "mode 4 1280x1024") != null);

    var set_result = try runCapture(std.testing.allocator, "display-set 800 600", 256, 256);
    defer set_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), set_result.exit_code);
    try std.testing.expectEqualStrings("display mode 800x600\n", set_result.stdout);

    var updated_info = try runCapture(std.testing.allocator, "display-info", 256, 256);
    defer updated_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), updated_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, updated_info.stdout, "current=800x600") != null);
}

test "baremetal tool exec activates requested display connector from stored outputs" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();
    framebuffer_console.resetForTest();
    display_output.resetForTest();
    display_output.updateFromVirtioGpu(.{
        .vendor_id = 0x1AF4,
        .device_id = 0x1050,
        .pci_bus = 0,
        .pci_device = 2,
        .pci_function = 0,
        .hardware_backed = false,
        .connected = true,
        .scanout_count = 2,
        .active_scanout = 0,
        .current_width = 1280,
        .current_height = 720,
        .preferred_width = 1280,
        .preferred_height = 720,
        .physical_width_mm = 300,
        .physical_height_mm = 190,
        .manufacturer_id = 0x1111,
        .product_code = 0x2222,
        .serial_number = 0x33334444,
        .capability_flags = abi.display_capability_hdmi_vendor_data | abi.display_capability_preferred_timing,
        .edid = &.{ 0x00, 0xFF, 0xFF, 0xFF },
        .scanouts = &.{
            .{
                .connected = true,
                .scanout_index = 0,
                .current_width = 1280,
                .current_height = 720,
                .preferred_width = 1280,
                .preferred_height = 720,
                .physical_width_mm = 300,
                .physical_height_mm = 190,
                .manufacturer_id = 0x1111,
                .product_code = 0x2222,
                .serial_number = 0x33334444,
                .capability_flags = abi.display_capability_hdmi_vendor_data | abi.display_capability_preferred_timing,
                .edid_length = 128,
                .supported_mode_count = 2,
                .supported_modes = [_]display_output.OutputMode{
                    .{ .width = 1280, .height = 720, .refresh_hz = 60 },
                    .{ .width = 1024, .height = 768, .refresh_hz = 60 },
                } ++ [_]display_output.OutputMode{.{
                    .width = 0,
                    .height = 0,
                    .refresh_hz = 0,
                }} ** (display_output.max_output_modes - 2),
            },
            .{
                .connected = true,
                .scanout_index = 1,
                .current_width = 1920,
                .current_height = 1080,
                .preferred_width = 1920,
                .preferred_height = 1080,
                .physical_width_mm = 520,
                .physical_height_mm = 320,
                .manufacturer_id = 0xAAAA,
                .product_code = 0xBBBB,
                .serial_number = 0xCCCCDDDD,
                .capability_flags = abi.display_capability_displayid_extension | abi.display_capability_preferred_timing,
                .edid_length = 128,
                .supported_mode_count = 2,
                .supported_modes = [_]display_output.OutputMode{
                    .{ .width = 1920, .height = 1080, .refresh_hz = 60 },
                    .{ .width = 1024, .height = 768, .refresh_hz = 60 },
                } ++ [_]display_output.OutputMode{.{
                    .width = 0,
                    .height = 0,
                    .refresh_hz = 0,
                }} ** (display_output.max_output_modes - 2),
            },
        },
    });

    var activate_result = try runCapture(std.testing.allocator, "display-activate displayport", 256, 256);
    defer activate_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, activate_result.stdout, "display connector displayport active scanout=1 current=1920x1080") != null);

    var mismatch_result = try runCapture(std.testing.allocator, "display-activate embedded-displayport", 256, 256);
    defer mismatch_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), mismatch_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, mismatch_result.stderr, "display-activate failed: DisplayConnectorMismatch") != null);

    var activate_output_result = try runCapture(std.testing.allocator, "display-activate-output 1", 256, 256);
    defer activate_output_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_output_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, activate_output_result.stdout, "display output 1 active connector=displayport scanout=1 current=1920x1080") != null);

    var preferred_connector_result = try runCapture(std.testing.allocator, "display-activate-preferred displayport", 256, 256);
    defer preferred_connector_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), preferred_connector_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, preferred_connector_result.stdout, "display connector preferred displayport scanout=1 current=1920x1080 preferred=1920x1080") != null);

    var activate_interface_result = try runCapture(std.testing.allocator, "display-activate-interface displayport", 256, 256);
    defer activate_interface_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_interface_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, activate_interface_result.stdout, "display interface displayport active connector=displayport scanout=1 current=1920x1080") != null);

    var preferred_interface_result = try runCapture(std.testing.allocator, "display-activate-interface-preferred displayport", 256, 256);
    defer preferred_interface_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), preferred_interface_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, preferred_interface_result.stdout, "display interface preferred displayport connector=displayport scanout=1 current=1920x1080 preferred=1920x1080") != null);

    var mismatch_interface_result = try runCapture(std.testing.allocator, "display-activate-interface hdmi-b", 256, 256);
    defer mismatch_interface_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), mismatch_interface_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, mismatch_interface_result.stderr, "display-activate-interface failed: DisplayInterfaceMismatch") != null);

    var output_modes_result = try runCapture(std.testing.allocator, "display-output-modes 1", 256, 256);
    defer output_modes_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), output_modes_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output_modes_result.stdout, "mode 1 1024x768 refresh=60") != null);

    var interface_modes_result = try runCapture(std.testing.allocator, "display-interface-modes displayport", 256, 256);
    defer interface_modes_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), interface_modes_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, interface_modes_result.stdout, "mode 1 1024x768 refresh=60") != null);

    var missing_output_result = try runCapture(std.testing.allocator, "display-activate-output 2", 256, 256);
    defer missing_output_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), missing_output_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, missing_output_result.stderr, "display-activate-output failed: DisplayOutputNotFound") != null);

    var set_output_result = try runCapture(std.testing.allocator, "display-output-set 1 1024 768", 256, 256);
    defer set_output_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), set_output_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, set_output_result.stdout, "display output 1 mode 1024x768 connector=displayport scanout=1") != null);

    var preferred_output_result = try runCapture(std.testing.allocator, "display-activate-output-preferred 1", 256, 256);
    defer preferred_output_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), preferred_output_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, preferred_output_result.stdout, "display output preferred 1 connector=displayport scanout=1 current=1920x1080 preferred=1920x1080") != null);

    var activate_output_mode_result = try runCapture(std.testing.allocator, "display-output-activate-mode 1 1", 256, 256);
    defer activate_output_mode_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_output_mode_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, activate_output_mode_result.stdout, "display output mode 1:1 1024x768 connector=displayport scanout=1") != null);

    var set_interface_mode_result = try runCapture(std.testing.allocator, "display-interface-set displayport 1024 768", 256, 256);
    defer set_interface_mode_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), set_interface_mode_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, set_interface_mode_result.stdout, "display interface displayport mode 1024x768 connector=displayport scanout=1") != null);

    var activate_interface_mode_result = try runCapture(std.testing.allocator, "display-interface-activate-mode displayport 0", 256, 256);
    defer activate_interface_mode_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_interface_mode_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, activate_interface_mode_result.stdout, "display interface mode displayport:0 1920x1080 connector=displayport scanout=1") != null);

    var reset_output_result = try runCapture(std.testing.allocator, "display-output-set 1 1024 768", 256, 256);
    defer reset_output_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), reset_output_result.exit_code);

    var unsupported_output_result = try runCapture(std.testing.allocator, "display-output-set 1 2560 1440", 256, 256);
    defer unsupported_output_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), unsupported_output_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, unsupported_output_result.stderr, "display-output-set failed: DisplayOutputUnsupportedMode") != null);

    var missing_output_set_result = try runCapture(std.testing.allocator, "display-output-set 2 800 600", 256, 256);
    defer missing_output_set_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), missing_output_set_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, missing_output_set_result.stderr, "display-output-set failed: DisplayOutputNotFound") != null);

    var missing_output_modes_result = try runCapture(std.testing.allocator, "display-output-modes 2", 256, 256);
    defer missing_output_modes_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), missing_output_modes_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, missing_output_modes_result.stderr, "display-output-modes failed: NotFound") != null);

    var missing_interface_modes_result = try runCapture(std.testing.allocator, "display-interface-modes hdmi-b", 256, 256);
    defer missing_interface_modes_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), missing_interface_modes_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, missing_interface_modes_result.stderr, "display-interface-modes failed: NotFound") != null);

    var invalid_output_mode_result = try runCapture(std.testing.allocator, "display-output-activate-mode 1 7", 256, 256);
    defer invalid_output_mode_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), invalid_output_mode_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, invalid_output_mode_result.stderr, "display-output-activate-mode failed: UnsupportedMode") != null);

    var invalid_interface_mode_result = try runCapture(std.testing.allocator, "display-interface-activate-mode displayport 7", 256, 256);
    defer invalid_interface_mode_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), invalid_interface_mode_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, invalid_interface_mode_result.stderr, "display-interface-activate-mode failed: UnsupportedMode") != null);

    var save_profile_result = try runCapture(std.testing.allocator, "display-profile-save golden", 256, 256);
    defer save_profile_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_profile_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, save_profile_result.stdout, "display profile saved golden output=1 current=1024x768 connector=displayport") != null);

    var info_profile_result = try runCapture(std.testing.allocator, "display-profile-info golden", 256, 256);
    defer info_profile_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), info_profile_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, info_profile_result.stdout, "name=golden") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_profile_result.stdout, "output_index=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_profile_result.stdout, "width=1024") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_profile_result.stdout, "height=768") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_profile_result.stdout, "selected=0") != null);

    var list_profile_result = try runCapture(std.testing.allocator, "display-profile-list", 256, 256);
    defer list_profile_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), list_profile_result.exit_code);
    try std.testing.expectEqualStrings("golden\n", list_profile_result.stdout);

    var mutate_output_result = try runCapture(std.testing.allocator, "display-output-set 1 800 600", 256, 256);
    defer mutate_output_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), mutate_output_result.exit_code);

    var apply_profile_result = try runCapture(std.testing.allocator, "display-profile-apply golden", 256, 256);
    defer apply_profile_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), apply_profile_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, apply_profile_result.stdout, "display profile applied golden output=1 current=1024x768 connector=displayport") != null);

    var active_profile_result = try runCapture(std.testing.allocator, "display-profile-active", 256, 256);
    defer active_profile_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), active_profile_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, active_profile_result.stdout, "selected=1") != null);

    var delete_profile_result = try runCapture(std.testing.allocator, "display-profile-delete golden", 256, 256);
    defer delete_profile_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_profile_result.exit_code);
    try std.testing.expectEqualStrings("display profile deleted golden\n", delete_profile_result.stdout);
}

test "baremetal tool exec reports detailed display sink metadata" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();
    framebuffer_console.resetForTest();
    display_output.resetForTest();
    display_output.updateFromVirtioGpu(.{
        .vendor_id = 0x1AF4,
        .device_id = 0x1050,
        .pci_bus = 0,
        .pci_device = 2,
        .pci_function = 0,
        .hardware_backed = false,
        .connected = true,
        .scanout_count = 1,
        .active_scanout = 0,
        .current_width = 1280,
        .current_height = 800,
        .preferred_width = 1280,
        .preferred_height = 800,
        .physical_width_mm = 300,
        .physical_height_mm = 190,
        .manufacturer_id = 0x1234,
        .product_code = 0x5678,
        .serial_number = 0xCAFEBABE,
        .capability_flags = abi.display_capability_digital_input | abi.display_capability_displayid_extension | abi.display_capability_basic_audio | abi.display_capability_preferred_timing,
        .edid = &.{ 0x00, 0xFF, 0xFF, 0xFF },
        .scanouts = &.{
            .{
                .connected = true,
                .scanout_index = 0,
                .current_width = 1280,
                .current_height = 800,
                .preferred_width = 1280,
                .preferred_height = 800,
                .physical_width_mm = 300,
                .physical_height_mm = 190,
                .manufacturer_id = 0x1234,
                .product_code = 0x5678,
                .serial_number = 0xCAFEBABE,
                .manufacturer_name = [_]u8{ 'Q', 'E', 'M' },
                .manufacture_week = 1,
                .manufacture_year = 2024,
                .edid_version = 1,
                .edid_revision = 4,
                .declared_interface_type = abi.display_interface_displayport,
                .extension_count = 1,
                .display_name_len = 9,
                .display_name = [_]u8{ 'Q', 'E', 'M', 'U', '-', 'E', 'D', 'I', 'D' } ++ [_]u8{0} ** (display_output.max_display_name_len - 9),
                .interface_type = abi.display_interface_displayport,
                .capability_flags = abi.display_capability_digital_input | abi.display_capability_displayid_extension | abi.display_capability_basic_audio | abi.display_capability_preferred_timing,
                .edid_length = 128,
                .supported_mode_count = 2,
                .supported_modes = [_]display_output.OutputMode{
                    .{ .width = 1280, .height = 800, .refresh_hz = 60 },
                    .{ .width = 1024, .height = 768, .refresh_hz = 60 },
                } ++ [_]display_output.OutputMode{.{
                    .width = 0,
                    .height = 0,
                    .refresh_hz = 0,
                }} ** (display_output.max_output_modes - 2),
            },
        },
    });

    var detail_result = try runCapture(std.testing.allocator, "display-output-detail 0", 512, 256);
    defer detail_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), detail_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, detail_result.stdout, "connector=displayport interface=displayport declared_interface=displayport") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_result.stdout, "name=QEMU-EDID manufacturer=QEM") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_result.stdout, "week=1 year=2024 edid=1.4 extensions=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_result.stdout, "physical=300x190mm audio=1 hdmi_vendor=0 displayid=1") != null);

    var capability_result = try runCapture(std.testing.allocator, "display-output-capabilities 0", 512, 256);
    defer capability_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), capability_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, capability_result.stdout, "connector=displayport interface=displayport declared_interface=displayport") != null);
    try std.testing.expect(std.mem.indexOf(u8, capability_result.stdout, "digital=1 preferred=1 cea=0 audio=1 hdmi_vendor=0 displayid=1 underscan=0 ycbcr444=0 ycbcr422=0") != null);

    var interface_result = try runCapture(std.testing.allocator, "display-interface-detail displayport", 512, 256);
    defer interface_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), interface_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, interface_result.stdout, "name=QEMU-EDID manufacturer=QEM") != null);

    var interface_capability_result = try runCapture(std.testing.allocator, "display-interface-capabilities displayport", 512, 256);
    defer interface_capability_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), interface_capability_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, interface_capability_result.stdout, "digital=1 preferred=1 cea=0 audio=1 hdmi_vendor=0 displayid=1 underscan=0 ycbcr444=0 ycbcr422=0") != null);

    var missing_result = try runCapture(std.testing.allocator, "display-interface-detail hdmi-a", 512, 256);
    defer missing_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), missing_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, missing_result.stderr, "display-interface-detail failed: NotFound") != null);

    var missing_capability_result = try runCapture(std.testing.allocator, "display-interface-capabilities hdmi-a", 512, 256);
    defer missing_capability_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), missing_capability_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, missing_capability_result.stderr, "display-interface-capabilities failed: NotFound") != null);
}

test "baremetal tool exec persists package display mode and applies it during package launch" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();

    try package_store.installScriptPackage("demo", "echo package-ok", 0);

    var set_result = try runCapture(std.testing.allocator, "package-display demo 1280 720", 256, 256);
    defer set_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), set_result.exit_code);
    try std.testing.expectEqualStrings("package display demo 1280x720\n", set_result.stdout);

    var app_result = try runCapture(std.testing.allocator, "package-app demo", 256, 256);
    defer app_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), app_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, app_result.stdout, "display_width=1280") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_result.stdout, "display_height=720") != null);

    var run_result = try runCapture(std.testing.allocator, "run-package demo", 256, 256);
    defer run_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, run_result.stdout, "package-ok\n") != null);

    const display = display_output.statePtr();
    try std.testing.expectEqual(@as(u16, 1280), display.current_width);
    try std.testing.expectEqual(@as(u16, 720), display.current_height);
}

test "baremetal tool exec rotates and revokes trust bundles" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    try trust_store.installBundle("fs55-root", "root-cert", 0);
    try trust_store.installBundle("fs55-backup", "backup-cert", 0);

    var list_result = try runCapture(std.testing.allocator, "trust-list", 256, 256);
    defer list_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    try std.testing.expectEqualStrings("fs55-root\nfs55-backup\n", list_result.stdout);

    var info_result = try runCapture(std.testing.allocator, "trust-info fs55-root", 256, 256);
    defer info_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), info_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "name=fs55-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "selected=0") != null);

    var select_result = try runCapture(std.testing.allocator, "trust-select fs55-root", 256, 256);
    defer select_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), select_result.exit_code);
    try std.testing.expectEqualStrings("selected fs55-root\n", select_result.stdout);

    var active_result = try runCapture(std.testing.allocator, "trust-active", 256, 256);
    defer active_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), active_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, active_result.stdout, "name=fs55-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, active_result.stdout, "selected=1") != null);

    var rotate_result = try runCapture(std.testing.allocator, "trust-select fs55-backup", 256, 256);
    defer rotate_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), rotate_result.exit_code);
    try std.testing.expectEqualStrings("selected fs55-backup\n", rotate_result.stdout);

    var delete_result = try runCapture(std.testing.allocator, "trust-delete fs55-root", 256, 256);
    defer delete_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_result.exit_code);
    try std.testing.expectEqualStrings("deleted fs55-root\n", delete_result.stdout);

    var remaining_list = try runCapture(std.testing.allocator, "trust-list", 256, 256);
    defer remaining_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), remaining_list.exit_code);
    try std.testing.expectEqualStrings("fs55-backup\n", remaining_list.stdout);

    var selected_info = try runCapture(std.testing.allocator, "trust-active", 256, 256);
    defer selected_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), selected_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, selected_info.stdout, "name=fs55-backup") != null);
    try std.testing.expect(std.mem.indexOf(u8, selected_info.stdout, "selected=1") != null);
}

test "baremetal tool exec reports persisted runtime snapshot and sessions" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    var runtime = try runtime_bridge.initRuntime(std.heap.page_allocator);
    defer runtime.deinit();

    var write_result = try runtime.fileWriteFromFrame(
        std.heap.page_allocator,
        "{\"id\":\"rt-write\",\"method\":\"file.write\",\"params\":{\"sessionId\":\"cli-runtime\",\"path\":\"/runtime/tmp/cli-runtime.txt\",\"content\":\"cli-runtime-data\"}}",
    );
    defer write_result.deinit(std.heap.page_allocator);
    try std.testing.expect(write_result.ok);

    var exec_result = try runtime.execRunFromFrame(
        std.heap.page_allocator,
        "{\"id\":\"rt-exec\",\"method\":\"exec.run\",\"params\":{\"sessionId\":\"cli-runtime\",\"command\":\"echo cli-runtime\",\"timeoutMs\":1000}}",
    );
    defer exec_result.deinit(std.heap.page_allocator);
    try std.testing.expect(exec_result.ok);

    var snapshot_result = try runCapture(std.testing.allocator, "runtime-snapshot", 256, 256);
    defer snapshot_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), snapshot_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_result.stdout, "state_path=/runtime/state/runtime-state.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_result.stdout, "sessions=1") != null);

    var sessions_result = try runCapture(std.testing.allocator, "runtime-sessions", 256, 256);
    defer sessions_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), sessions_result.exit_code);
    try std.testing.expectEqualStrings("cli-runtime\n", sessions_result.stdout);

    var session_result = try runCapture(std.testing.allocator, "runtime-session cli-runtime", 256, 256);
    defer session_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), session_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, session_result.stdout, "id=cli-runtime") != null);
    try std.testing.expect(std.mem.indexOf(u8, session_result.stdout, "last_message=echo cli-runtime") != null);
}

test "baremetal tool exec exposes virtual proc sys and dev overlays" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    var runtime = try runtime_bridge.initRuntime(std.heap.page_allocator);
    defer runtime.deinit();

    var exec_result = try runtime.execRunFromFrame(
        std.heap.page_allocator,
        "{\"id\":\"rt-proc\",\"method\":\"exec.run\",\"params\":{\"sessionId\":\"cli-proc\",\"command\":\"echo proc-fs\",\"timeoutMs\":1000}}",
    );
    defer exec_result.deinit(std.heap.page_allocator);
    try std.testing.expect(exec_result.ok);

    var list_result = try runCapture(std.testing.allocator, "ls /", 256, 256);
    defer list_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, list_result.stdout, "dir dev\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, list_result.stdout, "dir proc\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, list_result.stdout, "dir sys\n") != null);

    var proc_result = try runCapture(std.testing.allocator, "cat /proc/runtime/snapshot", 512, 256);
    defer proc_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), proc_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, proc_result.stdout, "state_path=/runtime/state/runtime-state.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, proc_result.stdout, "sessions=1") != null);

    var session_result = try runCapture(std.testing.allocator, "cat /proc/runtime/sessions/cli-proc", 512, 256);
    defer session_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), session_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, session_result.stdout, "id=cli-proc") != null);

    var sys_result = try runCapture(std.testing.allocator, "cat /sys/storage/state", 512, 256);
    defer sys_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), sys_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, sys_result.stdout, "backend=ram_disk") != null);

    var dev_result = try runCapture(std.testing.allocator, "cat /dev/storage/state", 512, 256);
    defer dev_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), dev_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, dev_result.stdout, "backend=ram_disk") != null);

    var stat_result = try runCapture(std.testing.allocator, "stat /proc/runtime/snapshot", 256, 256);
    defer stat_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), stat_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, stat_result.stdout, "path=/proc/runtime/snapshot kind=file") != null);
}

test "baremetal tool exec exposes storage and mount controls" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    var storage_backends = try runCapture(std.testing.allocator, "storage-backends", 1024, 256);
    defer storage_backends.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), storage_backends.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, storage_backends.stdout, "backend[0]=name=ram_disk backend=ram_disk available=1 selected=1 mounted=1") != null);

    var storage_filesystems = try runCapture(std.testing.allocator, "storage-filesystems", 512, 256);
    defer storage_filesystems.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), storage_filesystems.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, storage_filesystems.stdout, "filesystem=fat32 detect=1 mount=1 write=1 source=zar_bounded_writable_one_level_83") != null);

    var backend_info = try runCapture(std.testing.allocator, "storage-backend-info ram_disk", 512, 256);
    defer backend_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), backend_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, backend_info.stdout, "backend[0]=name=ram_disk backend=ram_disk available=1 selected=1 mounted=1") != null);

    var partitions = try runCapture(std.testing.allocator, "storage-partitions", 256, 256);
    defer partitions.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), partitions.exit_code);
    try std.testing.expectEqualStrings("backend=ram_disk partition_count=0 selected=none logical_base_lba=0\n", partitions.stdout);

    var bind = try runCapture(std.testing.allocator, "mount-bind state /runtime/state", 256, 256);
    defer bind.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), bind.exit_code);
    try std.testing.expectEqualStrings("mount bound state -> /runtime/state\n", bind.stdout);

    var mount_list = try runCapture(std.testing.allocator, "mount-list", 256, 256);
    defer mount_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), mount_list.exit_code);
    try std.testing.expectEqualStrings("mount name=state path=/mnt/state target=/runtime/state modified_tick=0\n", mount_list.stdout);

    var mount_info = try runCapture(std.testing.allocator, "mount-info state", 256, 256);
    defer mount_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), mount_info.exit_code);
    try std.testing.expectEqualStrings("mount name=state path=/mnt/state target=/runtime/state modified_tick=0\n", mount_info.stdout);

    var remove = try runCapture(std.testing.allocator, "mount-remove state", 256, 256);
    defer remove.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), remove.exit_code);
    try std.testing.expectEqualStrings("mount removed state\n", remove.stdout);

    var mount_list_after = try runCapture(std.testing.allocator, "mount-list", 256, 256);
    defer mount_list_after.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), mount_list_after.exit_code);
    try std.testing.expectEqualStrings("", mount_list_after.stdout);
}

test "baremetal tool exec exposes bounded shell batch and globbing" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    var shell_run = try runCapture(
        std.testing.allocator,
        "shell-run mkdir /tmp/sh; write-file /tmp/sh/A.TXT alpha; write-file /tmp/sh/B.LOG beta; mkdir /tmp/sh/DATA; write-file /tmp/sh/DATA/C.TXT gamma; mkdir /tmp/sh/DATA/DEEP; write-file /tmp/sh/DATA/DEEP/Z.TXT delta; echo alpha > /tmp/sh/OUT.TXT; echo beta >> /tmp/sh/OUT.TXT",
        1536,
        256,
    );
    defer shell_run.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_run.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, shell_run.stdout, "created /tmp/sh\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, shell_run.stdout, "wrote 5 bytes to /tmp/sh/A.TXT\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, shell_run.stdout, "created /tmp/sh/DATA\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, shell_run.stdout, "created /tmp/sh/DATA/DEEP\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, shell_run.stdout, "alpha\n") == null);

    var expand_root = try runCapture(std.testing.allocator, "shell-expand /tmp/sh/A*.TXT", 256, 256);
    defer expand_root.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), expand_root.exit_code);
    try std.testing.expectEqualStrings("/tmp/sh/A.TXT\n", expand_root.stdout);

    var expand_nested = try runCapture(std.testing.allocator, "shell-expand /tmp/sh/DATA/*.TXT", 256, 256);
    defer expand_nested.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), expand_nested.exit_code);
    try std.testing.expectEqualStrings("/tmp/sh/DATA/C.TXT\n", expand_nested.stdout);

    var expand_deep = try runCapture(std.testing.allocator, "shell-expand /tmp/sh/*/*/*.TXT", 256, 256);
    defer expand_deep.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), expand_deep.exit_code);
    try std.testing.expectEqualStrings("/tmp/sh/DATA/DEEP/Z.TXT\n", expand_deep.stdout);

    var no_match = try runCapture(std.testing.allocator, "shell-expand /tmp/sh/*.BIN", 256, 256);
    defer no_match.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), no_match.exit_code);
    try std.testing.expectEqualStrings("shell-expand failed: NoMatches\n", no_match.stderr);

    const redirected = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/OUT.TXT", 64);
    defer std.testing.allocator.free(redirected);
    try std.testing.expectEqualStrings("alpha\nbeta\n", redirected);

    var shell_escaped = try runCapture(
        std.testing.allocator,
        "shell-run echo alpha\\;beta > /tmp/sh/ESC.TXT; echo gt\\>value > /tmp/sh/GT.TXT",
        512,
        256,
    );
    defer shell_escaped.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_escaped.exit_code);
    try std.testing.expectEqualStrings("", shell_escaped.stdout);
    try std.testing.expectEqualStrings("", shell_escaped.stderr);

    const escaped_separator = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/ESC.TXT", 64);
    defer std.testing.allocator.free(escaped_separator);
    try std.testing.expectEqualStrings("alpha;beta\n", escaped_separator);

    const escaped_redirect = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/GT.TXT", 64);
    defer std.testing.allocator.free(escaped_redirect);
    try std.testing.expectEqualStrings("gt>value\n", escaped_redirect);

    var shell_stderr_redirect = try runCapture(
        std.testing.allocator,
        "shell-run cat /tmp/sh/MISSING.TXT 2> /tmp/sh/ERR.TXT",
        256,
        256,
    );
    defer shell_stderr_redirect.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), shell_stderr_redirect.exit_code);
    try std.testing.expectEqualStrings("", shell_stderr_redirect.stdout);
    try std.testing.expectEqualStrings("", shell_stderr_redirect.stderr);

    const redirected_stderr = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/ERR.TXT", 64);
    defer std.testing.allocator.free(redirected_stderr);
    try std.testing.expectEqualStrings("cat failed: FileNotFound\n", redirected_stderr);

    try filesystem.writeFile("/tmp/sh/SPACE NAME.TXT", "spaced", 0);
    try filesystem.writeFile("/tmp/sh/QUO\"TE.TXT", "quoted", 0);
    try filesystem.writeFile("/tmp/sh/STDIN.OC", "echo stdin-shell > /tmp/sh/STDINOUT.TXT", 0);

    var shell_input_redirect = try runCapture(
        std.testing.allocator,
        "shell-run cat < /tmp/sh/A.TXT > /tmp/sh/COPY.TXT; write-file /tmp/sh/FROMSTDIN.TXT < /tmp/sh/A.TXT; cat < \"/tmp/sh/SPACE NAME.TXT\" > /tmp/sh/QUOTE.TXT; cat < \"/tmp/sh/QUO\\\"TE.TXT\" > /tmp/sh/QUOTED.TXT; cat \"/tmp/sh/QUO\\\"TE.TXT\" > /tmp/sh/QUOTED2.TXT; write-file \"/tmp/sh/OUT\\\"PUT.TXT\" quoted2; cat \"/tmp/sh/OUT\\\"PUT.TXT\" > /tmp/sh/QUOTED3.TXT; echo lt\\<value > /tmp/sh/LT.TXT; shell-run < /tmp/sh/STDIN.OC",
        1280,
        256,
    );
    defer shell_input_redirect.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_input_redirect.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, shell_input_redirect.stdout, "wrote 5 bytes to /tmp/sh/FROMSTDIN.TXT\n") != null);
    try std.testing.expectEqualStrings("", shell_input_redirect.stderr);

    const copied_input = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/COPY.TXT", 64);
    defer std.testing.allocator.free(copied_input);
    try std.testing.expectEqualStrings("alpha", copied_input);

    const stdin_written = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/FROMSTDIN.TXT", 64);
    defer std.testing.allocator.free(stdin_written);
    try std.testing.expectEqualStrings("alpha", stdin_written);

    const quoted_copy = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/QUOTE.TXT", 64);
    defer std.testing.allocator.free(quoted_copy);
    try std.testing.expectEqualStrings("spaced", quoted_copy);

    const escaped_quoted_copy = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/QUOTED.TXT", 64);
    defer std.testing.allocator.free(escaped_quoted_copy);
    try std.testing.expectEqualStrings("quoted", escaped_quoted_copy);

    const escaped_quoted_copy_2 = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/QUOTED2.TXT", 64);
    defer std.testing.allocator.free(escaped_quoted_copy_2);
    try std.testing.expectEqualStrings("quoted", escaped_quoted_copy_2);

    const escaped_written_output = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/QUOTED3.TXT", 64);
    defer std.testing.allocator.free(escaped_written_output);
    try std.testing.expectEqualStrings("quoted2", escaped_written_output);

    const escaped_input_redirect = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/LT.TXT", 64);
    defer std.testing.allocator.free(escaped_input_redirect);
    try std.testing.expectEqualStrings("lt<value\n", escaped_input_redirect);

    const nested_shell_input = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/sh/STDINOUT.TXT", 64);
    defer std.testing.allocator.free(nested_shell_input);
    try std.testing.expectEqualStrings("stdin-shell\n", nested_shell_input);

    var shell_invalid_quoted = try runCapture(
        std.testing.allocator,
        "shell-run cat \"/tmp/sh/SPACE NAME.TXT\"x",
        256,
        256,
    );
    defer shell_invalid_quoted.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 2), shell_invalid_quoted.exit_code);
    try std.testing.expectEqualStrings("", shell_invalid_quoted.stdout);
    try std.testing.expectEqualStrings("usage: cat <path>\n", shell_invalid_quoted.stderr);
}

test "baremetal tool exec exposes bounded direct command redirection and input precedence" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    try filesystem.createDirPath("/tmp/direct");
    try filesystem.writeFile("/tmp/direct/A.TXT", "alpha", 0);
    try filesystem.writeFile("/tmp/direct/QUO\"TE.TXT", "quoted", 0);
    try filesystem.writeFile("/tmp/direct/SPACE NAME.TXT", "spaced-direct", 0);

    var direct_output_redirect = try runCapture(std.testing.allocator, "echo direct-alpha > /tmp/direct/OUT.TXT", 256, 256);
    defer direct_output_redirect.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), direct_output_redirect.exit_code);
    try std.testing.expectEqualStrings("", direct_output_redirect.stdout);

    const direct_output_file = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/direct/OUT.TXT", 64);
    defer std.testing.allocator.free(direct_output_file);
    try std.testing.expectEqualStrings("direct-alpha\n", direct_output_file);

    var direct_input_redirect = try runCapture(std.testing.allocator, "cat < \"/tmp/direct/QUO\\\"TE.TXT\"", 256, 256);
    defer direct_input_redirect.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), direct_input_redirect.exit_code);
    try std.testing.expectEqualStrings("quoted", direct_input_redirect.stdout);

    var direct_escaped_space_redirect = try runCapture(std.testing.allocator, "cat < /tmp/direct/SPACE\\ NAME.TXT", 256, 256);
    defer direct_escaped_space_redirect.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), direct_escaped_space_redirect.exit_code);
    try std.testing.expectEqualStrings("spaced-direct", direct_escaped_space_redirect.stdout);

    var direct_escaped_space_cat = try runCapture(std.testing.allocator, "cat /tmp/direct/SPACE\\ NAME.TXT", 256, 256);
    defer direct_escaped_space_cat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), direct_escaped_space_cat.exit_code);
    try std.testing.expectEqualStrings("spaced-direct", direct_escaped_space_cat.stdout);

    var direct_escaped_space_write = try runCapture(std.testing.allocator, "write-file /tmp/direct/SPACE\\ OUT.TXT direct-space", 256, 256);
    defer direct_escaped_space_write.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), direct_escaped_space_write.exit_code);
    try std.testing.expectEqualStrings("wrote 12 bytes to /tmp/direct/SPACE OUT.TXT\n", direct_escaped_space_write.stdout);
    const direct_escaped_space_writeback = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/direct/SPACE OUT.TXT", 64);
    defer std.testing.allocator.free(direct_escaped_space_writeback);
    try std.testing.expectEqualStrings("direct-space", direct_escaped_space_writeback);

    var direct_stdin_only = try runCaptureSilentWithInput(std.testing.allocator, "write-file /tmp/direct/FROMSTDIN.TXT", "stdin-direct", 256, 256);
    defer direct_stdin_only.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), direct_stdin_only.exit_code);
    const direct_stdin_file = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/direct/FROMSTDIN.TXT", 64);
    defer std.testing.allocator.free(direct_stdin_file);
    try std.testing.expectEqualStrings("stdin-direct", direct_stdin_file);

    var direct_file_precedence = try runCaptureSilentWithInput(std.testing.allocator, "write-file /tmp/direct/FROMFILE.TXT < /tmp/direct/A.TXT", "ignored-stdin", 256, 256);
    defer direct_file_precedence.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), direct_file_precedence.exit_code);
    const direct_file_precedence_output = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/direct/FROMFILE.TXT", 64);
    defer std.testing.allocator.free(direct_file_precedence_output);
    try std.testing.expectEqualStrings("alpha", direct_file_precedence_output);

    var direct_invalid_quoted = try runCapture(std.testing.allocator, "cat \"/tmp/direct/QUO\\\"TE.TXT\"x", 256, 256);
    defer direct_invalid_quoted.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 2), direct_invalid_quoted.exit_code);
    try std.testing.expectEqualStrings("", direct_invalid_quoted.stdout);
    try std.testing.expectEqualStrings("usage: cat <path>\n", direct_invalid_quoted.stderr);
}

test "baremetal tool exec persists bounded tty session receipts" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    var open_result = try runCapture(std.testing.allocator, "tty-open demo", 256, 256);
    defer open_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), open_result.exit_code);
    try std.testing.expectEqualStrings("tty opened demo\n", open_result.stdout);

    var write_result = try runCapture(std.testing.allocator, "tty-write demo tty-session-input", 256, 256);
    defer write_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), write_result.exit_code);
    try std.testing.expectEqualStrings("tty queued demo 17 bytes\n", write_result.stdout);

    var pending_result = try runCapture(std.testing.allocator, "tty-pending demo", 256, 256);
    defer pending_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), pending_result.exit_code);
    try std.testing.expectEqualStrings("tty-session-input", pending_result.stdout);

    var send_result = try runCapture(std.testing.allocator, "tty-send demo cat", 256, 256);
    defer send_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), send_result.exit_code);
    try std.testing.expectEqualStrings("tty-session-input", send_result.stdout);
    try std.testing.expectEqualStrings("", send_result.stderr);

    try filesystem.writeFile("/tmp/tty-input.txt", "file-input", 0);
    try filesystem.writeFile("/tmp/tty input.txt", "tty spaced", 0);
    var override_write_result = try runCapture(std.testing.allocator, "tty-write demo queued-tty-data", 256, 256);
    defer override_write_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), override_write_result.exit_code);
    var override_send_result = try runCapture(std.testing.allocator, "tty-send demo cat < /tmp/tty-input.txt", 256, 256);
    defer override_send_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), override_send_result.exit_code);
    try std.testing.expectEqualStrings("file-input", override_send_result.stdout);
    try std.testing.expectEqualStrings("", override_send_result.stderr);

    var escaped_space_send_result = try runCapture(std.testing.allocator, "tty-send demo cat < /tmp/tty\\ input.txt", 256, 256);
    defer escaped_space_send_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), escaped_space_send_result.exit_code);
    try std.testing.expectEqualStrings("tty spaced", escaped_space_send_result.stdout);
    try std.testing.expectEqualStrings("", escaped_space_send_result.stderr);

    var drained_pending = try runCapture(std.testing.allocator, "tty-pending demo", 256, 256);
    defer drained_pending.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), drained_pending.exit_code);
    try std.testing.expectEqualStrings("", drained_pending.stdout);

    var stale_write = try runCapture(std.testing.allocator, "tty-write demo stale-tty", 256, 256);
    defer stale_write.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), stale_write.exit_code);
    try std.testing.expectEqualStrings("tty queued demo 9 bytes\n", stale_write.stdout);

    var clear_result = try runCapture(std.testing.allocator, "tty-clear demo", 256, 256);
    defer clear_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), clear_result.exit_code);
    try std.testing.expectEqualStrings("tty cleared demo\n", clear_result.stdout);

    var stderr_send = try runCapture(std.testing.allocator, "tty-send demo cat /tmp/missing-tty.txt", 256, 256);
    defer stderr_send.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), stderr_send.exit_code);
    try std.testing.expectEqualStrings("", stderr_send.stdout);
    try std.testing.expectEqualStrings("cat failed: FileNotFound\n", stderr_send.stderr);

    var list_result = try runCapture(std.testing.allocator, "tty-list", 256, 256);
    defer list_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    try std.testing.expectEqualStrings("demo\n", list_result.stdout);

    var info_result = try runCapture(std.testing.allocator, "tty-info demo", 512, 256);
    defer info_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), info_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "open=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "command_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "pending_input_bytes=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "event_count=9") != null);

    var read_result = try runCapture(std.testing.allocator, "tty-read demo", 1024, 256);
    defer read_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), read_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, read_result.stdout, "$ cat\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_result.stdout, "stdin:\ntty-session-input\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_result.stdout, "$ cat /tmp/missing-tty.txt\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, read_result.stdout, "stderr:\ncat failed: FileNotFound\n") != null);

    var events_result = try runCapture(std.testing.allocator, "tty-events demo", 1024, 256);
    defer events_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), events_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, events_result.stdout, "type=open") != null);
    try std.testing.expect(std.mem.indexOf(u8, events_result.stdout, "type=write bytes=17") != null);
    try std.testing.expect(std.mem.indexOf(u8, events_result.stdout, "type=send exit=0 stdin_bytes=17 stdout_bytes=17 stderr_bytes=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, events_result.stdout, "type=clear bytes=9") != null);

    var stdout_result = try runCapture(std.testing.allocator, "tty-stdout demo", 256, 256);
    defer stdout_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), stdout_result.exit_code);
    try std.testing.expectEqualStrings("tty-session-inputfile-inputtty spaced", stdout_result.stdout);

    var stderr_result = try runCapture(std.testing.allocator, "tty-stderr demo", 256, 256);
    defer stderr_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), stderr_result.exit_code);
    try std.testing.expectEqualStrings("cat failed: FileNotFound\n", stderr_result.stdout);

    var close_result = try runCapture(std.testing.allocator, "tty-close demo", 256, 256);
    defer close_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), close_result.exit_code);
    try std.testing.expectEqualStrings("tty closed demo\n", close_result.stdout);

    var closed_info = try runCapture(std.testing.allocator, "tty-info demo", 512, 256);
    defer closed_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), closed_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, closed_info.stdout, "open=0") != null);

    var shell_open = try runCapture(std.testing.allocator, "tty-open shell", 256, 256);
    defer shell_open.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_open.exit_code);
    try std.testing.expectEqualStrings("tty opened shell\n", shell_open.stdout);

    var shell_write = try runCapture(std.testing.allocator, "tty-write shell tty-shell-input", 256, 256);
    defer shell_write.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_write.exit_code);
    try std.testing.expectEqualStrings("tty queued shell 15 bytes\n", shell_write.stdout);

    var shell_run = try runCapture(std.testing.allocator, "tty-shell shell cat > /tmp/tty-shell/OUT.TXT; cat", 256, 256);
    defer shell_run.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_run.exit_code);
    try std.testing.expectEqualStrings("tty-shell-input", shell_run.stdout);
    try std.testing.expectEqualStrings("", shell_run.stderr);

    var shell_readback = try runCapture(std.testing.allocator, "cat /tmp/tty-shell/OUT.TXT", 256, 256);
    defer shell_readback.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_readback.exit_code);
    try std.testing.expectEqualStrings("tty-shell-input", shell_readback.stdout);

    var shell_info = try runCapture(std.testing.allocator, "tty-info shell", 512, 256);
    defer shell_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, shell_info.stdout, "name=shell") != null);
    try std.testing.expect(std.mem.indexOf(u8, shell_info.stdout, "command_count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, shell_info.stdout, "pending_input_bytes=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, shell_info.stdout, "event_count=3") != null);

    var shell_events = try runCapture(std.testing.allocator, "tty-events shell", 1024, 256);
    defer shell_events.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_events.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, shell_events.stdout, "type=open") != null);
    try std.testing.expect(std.mem.indexOf(u8, shell_events.stdout, "type=write bytes=15") != null);
    try std.testing.expect(std.mem.indexOf(u8, shell_events.stdout, "type=shell exit=0 script_bytes=33 stdin_bytes=15 stdout_bytes=15 stderr_bytes=0") != null);

    var shell_transcript = try runCapture(std.testing.allocator, "tty-read shell", 1024, 256);
    defer shell_transcript.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_transcript.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, shell_transcript.stdout, "$ shell-run\nscript:\ncat > /tmp/tty-shell/OUT.TXT; cat\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, shell_transcript.stdout, "stdin:\ntty-shell-input\n") != null);

    var shell_close = try runCapture(std.testing.allocator, "tty-close shell", 256, 256);
    defer shell_close.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_close.exit_code);
    try std.testing.expectEqualStrings("tty closed shell\n", shell_close.stdout);

    try filesystem.writeFile("/tmp/tty-shell/INPUT.TXT", "file-input", 0);
    try filesystem.writeFile("/tmp/tty-shell/SPACE NAME.TXT", "space-file", 0);

    var shell_override_open = try runCapture(std.testing.allocator, "tty-open shell-override", 256, 256);
    defer shell_override_open.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_override_open.exit_code);

    var shell_override_write = try runCapture(std.testing.allocator, "tty-write shell-override queued-tty-data", 256, 256);
    defer shell_override_write.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_override_write.exit_code);

    const shell_override_script = "cat < \"/tmp/tty-shell/INPUT.TXT\" > /tmp/tty-shell/OVERRIDE.TXT; cat";
    var shell_override_run = try runCapture(std.testing.allocator, "tty-shell shell-override cat < \"/tmp/tty-shell/INPUT.TXT\" > /tmp/tty-shell/OVERRIDE.TXT; cat", 256, 256);
    defer shell_override_run.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_override_run.exit_code);
    try std.testing.expectEqualStrings("queued-tty-data", shell_override_run.stdout);
    try std.testing.expectEqualStrings("", shell_override_run.stderr);

    const shell_override_file = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/tty-shell/OVERRIDE.TXT", 64);
    defer std.testing.allocator.free(shell_override_file);
    try std.testing.expectEqualStrings("file-input", shell_override_file);

    var shell_space_write = try runCapture(std.testing.allocator, "tty-write shell-override queued-space-data", 256, 256);
    defer shell_space_write.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_space_write.exit_code);

    var shell_space_run = try runCapture(std.testing.allocator, "tty-shell shell-override cat < /tmp/tty-shell/SPACE\\ NAME.TXT > /tmp/tty-shell/SPACEOUT.TXT; cat", 256, 256);
    defer shell_space_run.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_space_run.exit_code);
    try std.testing.expectEqualStrings("queued-space-data", shell_space_run.stdout);
    try std.testing.expectEqualStrings("", shell_space_run.stderr);

    const shell_space_file = try filesystem.readFileAlloc(std.testing.allocator, "/tmp/tty-shell/SPACEOUT.TXT", 64);
    defer std.testing.allocator.free(shell_space_file);
    try std.testing.expectEqualStrings("space-file", shell_space_file);

    var shell_override_pending = try runCapture(std.testing.allocator, "tty-pending shell-override", 256, 256);
    defer shell_override_pending.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_override_pending.exit_code);
    try std.testing.expectEqualStrings("", shell_override_pending.stdout);

    var shell_override_events = try runCapture(std.testing.allocator, "tty-events shell-override", 1024, 256);
    defer shell_override_events.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_override_events.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, shell_override_events.stdout, "type=write bytes=15") != null);
    const shell_override_event = try std.fmt.allocPrint(std.testing.allocator, "type=shell exit=0 script_bytes={d} stdin_bytes=15 stdout_bytes=15 stderr_bytes=0", .{shell_override_script.len});
    defer std.testing.allocator.free(shell_override_event);
    try std.testing.expect(std.mem.indexOf(u8, shell_override_events.stdout, shell_override_event) != null);

    var shell_override_close = try runCapture(std.testing.allocator, "tty-close shell-override", 256, 256);
    defer shell_override_close.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), shell_override_close.exit_code);
    try std.testing.expectEqualStrings("tty closed shell-override\n", shell_override_close.stdout);
}

test "baremetal tool exec configures app trust and connector and reports app info" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    try trust_store.installBundle("fs55-root", "root-cert", 0);
    try package_store.installScriptPackage("demo", "echo package-ok", 1);

    var connector_result = try runCapture(std.testing.allocator, "app-connector demo virtual", 256, 256);
    defer connector_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), connector_result.exit_code);
    try std.testing.expectEqualStrings("app connector demo virtual\n", connector_result.stdout);

    var trust_result = try runCapture(std.testing.allocator, "app-trust demo fs55-root", 256, 256);
    defer trust_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), trust_result.exit_code);
    try std.testing.expectEqualStrings("app trust demo fs55-root\n", trust_result.stdout);

    var info_result = try runCapture(std.testing.allocator, "app-info demo", 512, 256);
    defer info_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), info_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "trust_bundle=fs55-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "state_path=/runtime/apps/demo/last_run.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "history_path=/runtime/apps/demo/history.log") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "stdout_path=/runtime/apps/demo/stdout.log") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "stderr_path=/runtime/apps/demo/stderr.log") != null);

    var list_result = try runCapture(std.testing.allocator, "app-list", 256, 256);
    defer list_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    try std.testing.expectEqualStrings("demo\n", list_result.stdout);
}

test "baremetal tool exec app-run persists last run state and selects trust" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();

    try trust_store.installBundle("fs55-root", "root-cert", 0);
    try package_store.installScriptPackage("demo", "mkdir /pkg/out\nwrite-file /pkg/out/data.txt app-data\necho app-ok\n", 1);
    try package_store.configureDisplayMode("demo", 1280, 720, 2);
    try package_store.configureConnectorType("demo", abi.display_connector_virtual, 3);
    try package_store.configureTrustBundle("demo", "fs55-root", 4);

    var run_result = try runCapture(std.testing.allocator, "app-run demo", 512, 256);
    defer run_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, run_result.stdout, "app-ok\n") != null);

    const active_bundle = try trust_store.activeBundleNameAlloc(std.testing.allocator, trust_store.max_name_len);
    defer std.testing.allocator.free(active_bundle);
    try std.testing.expectEqualStrings("fs55-root", active_bundle);

    var state_result = try runCapture(std.testing.allocator, "app-state demo", 512, 256);
    defer state_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), state_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, state_result.stdout, "exit_code=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, state_result.stdout, "requested_connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, state_result.stdout, "actual_connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, state_result.stdout, "trust_bundle=fs55-root") != null);

    var history_result = try runCapture(std.testing.allocator, "app-history demo", 512, 256);
    defer history_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), history_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, history_result.stdout, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, history_result.stdout, "trust_bundle=fs55-root") != null);

    var stdout_result = try runCapture(std.testing.allocator, "app-stdout demo", 512, 256);
    defer stdout_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), stdout_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_result.stdout, "app-ok") != null);

    var stderr_result = try runCapture(std.testing.allocator, "app-stderr demo", 512, 256);
    defer stderr_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), stderr_result.exit_code);
    try std.testing.expectEqualStrings("", stderr_result.stdout);
}

test "baremetal tool exec persists and runs autorun apps" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();

    try package_store.installScriptPackage("demo", "echo demo-autorun", 1);
    try package_store.installScriptPackage("aux", "echo aux-autorun", 2);

    var add_demo = try runCapture(std.testing.allocator, "app-autorun-add demo", 256, 256);
    defer add_demo.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), add_demo.exit_code);
    try std.testing.expectEqualStrings("app autorun add demo\n", add_demo.stdout);

    var add_aux = try runCapture(std.testing.allocator, "app-autorun-add aux", 256, 256);
    defer add_aux.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), add_aux.exit_code);
    try std.testing.expectEqualStrings("app autorun add aux\n", add_aux.stdout);

    var list_result = try runCapture(std.testing.allocator, "app-autorun-list", 256, 256);
    defer list_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    try std.testing.expectEqualStrings("demo\naux\n", list_result.stdout);

    var run_result = try runCapture(std.testing.allocator, "app-autorun-run", 256, 256);
    defer run_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);
    try std.testing.expectEqualStrings("demo-autorun\naux-autorun\n", run_result.stdout);

    const demo_state = try app_runtime.stateAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(demo_state);
    try std.testing.expect(std.mem.indexOf(u8, demo_state, "exit_code=0") != null);

    const aux_stdout = try app_runtime.stdoutAlloc(std.testing.allocator, "aux", 256);
    defer std.testing.allocator.free(aux_stdout);
    try std.testing.expectEqualStrings("aux-autorun\n", aux_stdout);

    var remove_demo = try runCapture(std.testing.allocator, "app-autorun-remove demo", 256, 256);
    defer remove_demo.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), remove_demo.exit_code);
    try std.testing.expectEqualStrings("app autorun remove demo\n", remove_demo.stdout);

    var updated_list = try runCapture(std.testing.allocator, "app-autorun-list", 256, 256);
    defer updated_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), updated_list.exit_code);
    try std.testing.expectEqualStrings("aux\n", updated_list.stdout);
}

test "baremetal tool exec uninstalls packages and clears app state" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    vga_text_console.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();

    try package_store.installScriptPackage("demo", "echo delete-demo", 1);
    try package_store.installScriptPackage("alias-demo", "echo alias-delete", 2);

    var app_run_result = try runCapture(std.testing.allocator, "app-run demo", 512, 256);
    defer app_run_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), app_run_result.exit_code);

    var package_delete_result = try runCapture(std.testing.allocator, "package-delete demo", 256, 256);
    defer package_delete_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), package_delete_result.exit_code);
    try std.testing.expectEqualStrings("package deleted demo\n", package_delete_result.stdout);

    var app_delete_result = try runCapture(std.testing.allocator, "app-delete alias-demo", 256, 256);
    defer app_delete_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), app_delete_result.exit_code);
    try std.testing.expectEqualStrings("app deleted alias-demo\n", app_delete_result.stdout);

    var list_result = try runCapture(std.testing.allocator, "app-list", 256, 256);
    defer list_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    try std.testing.expectEqualStrings("", list_result.stdout);

    try std.testing.expectError(error.FileNotFound, filesystem.statSummary("/packages/demo"));
    try std.testing.expectError(error.FileNotFound, filesystem.statSummary("/packages/alias-demo"));
    try std.testing.expectError(error.FileNotFound, filesystem.statSummary("/runtime/apps/demo"));
}

test "baremetal tool exec saves applies runs and deletes app suites" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();
    vga_text_console.resetForTest();

    try package_store.installScriptPackage("demo", "echo suite-demo", 1);
    try package_store.installScriptPackage("aux", "echo suite-aux", 2);

    var save_demo_plan = try runCapture(std.testing.allocator, "app-plan-save demo golden none none virtual 1280 720 1", 256, 256);
    defer save_demo_plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_demo_plan.exit_code);
    try std.testing.expectEqualStrings("app plan saved demo golden\n", save_demo_plan.stdout);

    var save_aux_plan = try runCapture(std.testing.allocator, "app-plan-save aux sidecar none none virtual 800 600 0", 256, 256);
    defer save_aux_plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_aux_plan.exit_code);
    try std.testing.expectEqualStrings("app plan saved aux sidecar\n", save_aux_plan.stdout);

    var save_suite = try runCapture(std.testing.allocator, "app-suite-save duo demo:golden aux:sidecar", 256, 256);
    defer save_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_suite.exit_code);
    try std.testing.expectEqualStrings("app suite saved duo\n", save_suite.stdout);

    var suite_list = try runCapture(std.testing.allocator, "app-suite-list", 256, 256);
    defer suite_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), suite_list.exit_code);
    try std.testing.expectEqualStrings("duo\n", suite_list.stdout);

    var suite_info = try runCapture(std.testing.allocator, "app-suite-info duo", 256, 256);
    defer suite_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), suite_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, suite_info.stdout, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info.stdout, "entry=demo:golden") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info.stdout, "entry=aux:sidecar") != null);

    var apply_suite = try runCapture(std.testing.allocator, "app-suite-apply duo", 256, 256);
    defer apply_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), apply_suite.exit_code);
    try std.testing.expectEqualStrings("app suite applied duo\n", apply_suite.stdout);

    var demo_active = try runCapture(std.testing.allocator, "app-plan-active demo", 256, 256);
    defer demo_active.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), demo_active.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, demo_active.stdout, "active_plan=golden") != null);

    var aux_active = try runCapture(std.testing.allocator, "app-plan-active aux", 256, 256);
    defer aux_active.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), aux_active.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, aux_active.stdout, "active_plan=sidecar") != null);

    var autorun_list = try runCapture(std.testing.allocator, "app-autorun-list", 256, 256);
    defer autorun_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), autorun_list.exit_code);
    try std.testing.expectEqualStrings("demo\n", autorun_list.stdout);

    var run_suite = try runCapture(std.testing.allocator, "app-suite-run duo", 256, 256);
    defer run_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), run_suite.exit_code);
    try std.testing.expectEqualStrings("suite-demo\nsuite-aux\n", run_suite.stdout);

    const demo_stdout = try app_runtime.stdoutAlloc(std.testing.allocator, "demo", 64);
    defer std.testing.allocator.free(demo_stdout);
    try std.testing.expectEqualStrings("suite-demo\n", demo_stdout);

    const aux_stdout = try app_runtime.stdoutAlloc(std.testing.allocator, "aux", 64);
    defer std.testing.allocator.free(aux_stdout);
    try std.testing.expectEqualStrings("suite-aux\n", aux_stdout);

    var delete_suite = try runCapture(std.testing.allocator, "app-suite-delete duo", 256, 256);
    defer delete_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_suite.exit_code);
    try std.testing.expectEqualStrings("app suite deleted duo\n", delete_suite.stdout);

    var suite_list_after_delete = try runCapture(std.testing.allocator, "app-suite-list", 256, 256);
    defer suite_list_after_delete.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), suite_list_after_delete.exit_code);
    try std.testing.expectEqualStrings("", suite_list_after_delete.stdout);
}

test "baremetal tool exec manages app suite releases" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();
    vga_text_console.resetForTest();

    try package_store.installScriptPackage("demo", "echo suite-demo", 1);
    try package_store.installScriptPackage("aux", "echo suite-aux", 2);

    var save_demo_plan = try runCapture(std.testing.allocator, "app-plan-save demo golden none none virtual 1280 720 1", 256, 256);
    defer save_demo_plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_demo_plan.exit_code);

    var save_demo_canary = try runCapture(std.testing.allocator, "app-plan-save demo canary none none virtual 640 400 0", 256, 256);
    defer save_demo_canary.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_demo_canary.exit_code);

    var save_aux_plan = try runCapture(std.testing.allocator, "app-plan-save aux sidecar none none virtual 800 600 0", 256, 256);
    defer save_aux_plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_aux_plan.exit_code);

    var save_suite = try runCapture(std.testing.allocator, "app-suite-save duo demo:golden aux:sidecar", 256, 256);
    defer save_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_suite.exit_code);

    var save_release_golden = try runCapture(std.testing.allocator, "app-suite-release-save duo golden", 256, 256);
    defer save_release_golden.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_release_golden.exit_code);
    try std.testing.expectEqualStrings("app suite release saved duo golden\n", save_release_golden.stdout);

    var mutate_suite = try runCapture(std.testing.allocator, "app-suite-save duo demo:canary", 256, 256);
    defer mutate_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), mutate_suite.exit_code);

    var save_release_staging = try runCapture(std.testing.allocator, "app-suite-release-save duo staging", 256, 256);
    defer save_release_staging.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_release_staging.exit_code);
    try std.testing.expectEqualStrings("app suite release saved duo staging\n", save_release_staging.stdout);

    var release_list = try runCapture(std.testing.allocator, "app-suite-release-list duo", 256, 256);
    defer release_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), release_list.exit_code);
    try std.testing.expectEqualStrings("golden\nstaging\n", release_list.stdout);

    var release_info = try runCapture(std.testing.allocator, "app-suite-release-info duo staging", 512, 256);
    defer release_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), release_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, release_info.stdout, "release=staging") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info.stdout, "saved_seq=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info.stdout, "entry=demo:canary") != null);

    var activate_release = try runCapture(std.testing.allocator, "app-suite-release-activate duo golden", 256, 256);
    defer activate_release.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_release.exit_code);
    try std.testing.expectEqualStrings("app suite release activated duo golden\n", activate_release.stdout);

    var suite_info = try runCapture(std.testing.allocator, "app-suite-info duo", 512, 256);
    defer suite_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), suite_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, suite_info.stdout, "entry=demo:golden") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info.stdout, "entry=aux:sidecar") != null);

    var delete_release = try runCapture(std.testing.allocator, "app-suite-release-delete duo staging", 256, 256);
    defer delete_release.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_release.exit_code);
    try std.testing.expectEqualStrings("app suite release deleted duo staging\n", delete_release.stdout);

    var mutate_fallback = try runCapture(std.testing.allocator, "app-suite-save duo demo:canary aux:sidecar", 256, 256);
    defer mutate_fallback.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), mutate_fallback.exit_code);

    var save_release_fallback = try runCapture(std.testing.allocator, "app-suite-release-save duo fallback", 256, 256);
    defer save_release_fallback.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_release_fallback.exit_code);
    try std.testing.expectEqualStrings("app suite release saved duo fallback\n", save_release_fallback.stdout);

    var prune_release = try runCapture(std.testing.allocator, "app-suite-release-prune duo 1", 256, 256);
    defer prune_release.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), prune_release.exit_code);
    try std.testing.expectEqualStrings("app suite release pruned duo keep=1 deleted=1 kept=1\n", prune_release.stdout);

    var release_list_after_prune = try runCapture(std.testing.allocator, "app-suite-release-list duo", 256, 256);
    defer release_list_after_prune.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), release_list_after_prune.exit_code);
    try std.testing.expectEqualStrings("fallback\n", release_list_after_prune.stdout);

    var set_channel_fallback = try runCapture(std.testing.allocator, "app-suite-release-channel-set duo stable fallback", 256, 256);
    defer set_channel_fallback.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), set_channel_fallback.exit_code);
    try std.testing.expectEqualStrings("app suite release channel set duo stable fallback\n", set_channel_fallback.stdout);

    var channel_list = try runCapture(std.testing.allocator, "app-suite-release-channel-list duo", 256, 256);
    defer channel_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), channel_list.exit_code);
    try std.testing.expectEqualStrings("stable\n", channel_list.stdout);

    var channel_info = try runCapture(std.testing.allocator, "app-suite-release-channel-info duo stable", 256, 256);
    defer channel_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), channel_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, channel_info.stdout, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, channel_info.stdout, "channel=stable") != null);
    try std.testing.expect(std.mem.indexOf(u8, channel_info.stdout, "release=fallback") != null);

    var activate_channel = try runCapture(std.testing.allocator, "app-suite-release-channel-activate duo stable", 256, 256);
    defer activate_channel.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_channel.exit_code);
    try std.testing.expectEqualStrings("app suite release channel activated duo stable\n", activate_channel.stdout);

    var suite_info_after_channel = try runCapture(std.testing.allocator, "app-suite-info duo", 512, 256);
    defer suite_info_after_channel.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), suite_info_after_channel.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, suite_info_after_channel.stdout, "entry=demo:canary") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info_after_channel.stdout, "entry=aux:sidecar") != null);
}

test "baremetal tool exec saves applies and deletes workspaces" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();
    vga_text_console.resetForTest();

    try trust_store.installBundle("root-a", "root-a-cert", 1);
    try trust_store.installBundle("root-b", "root-b-cert", 2);

    try package_store.installScriptPackage("demo", "echo release-r1", 3);
    try package_store.snapshotPackageRelease("demo", "r1", 4);
    try package_store.installScriptPackage("demo", "echo release-r2", 5);
    try package_store.snapshotPackageRelease("demo", "r2", 6);
    try package_store.setPackageReleaseChannel("demo", "stable", "r1", 7);
    try package_store.activatePackageReleaseChannel("demo", "stable", 8);

    try package_store.installScriptPackage("aux", "echo aux-sidecar", 9);

    var save_demo_plan = try runCapture(std.testing.allocator, "app-plan-save demo golden none root-a virtual 1024 768 1", 256, 256);
    defer save_demo_plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_demo_plan.exit_code);

    var save_demo_alt = try runCapture(std.testing.allocator, "app-plan-save demo alt none none virtual 640 400 0", 256, 256);
    defer save_demo_alt.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_demo_alt.exit_code);

    var save_aux_plan = try runCapture(std.testing.allocator, "app-plan-save aux sidecar none none virtual 800 600 0", 256, 256);
    defer save_aux_plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_aux_plan.exit_code);

    var save_aux_alt = try runCapture(std.testing.allocator, "app-plan-save aux fallback none none virtual 640 400 0", 256, 256);
    defer save_aux_alt.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_aux_alt.exit_code);

    var save_suite = try runCapture(std.testing.allocator, "app-suite-save duo demo:golden aux:sidecar", 256, 256);
    defer save_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_suite.exit_code);

    var save_workspace = try runCapture(std.testing.allocator, "workspace-save ops duo root-a 1024 768 demo:stable:r1", 256, 256);
    defer save_workspace.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace.exit_code);
    try std.testing.expectEqualStrings("workspace saved ops\n", save_workspace.stdout);

    var workspace_list = try runCapture(std.testing.allocator, "workspace-list", 256, 256);
    defer workspace_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_list.exit_code);
    try std.testing.expectEqualStrings("ops\n", workspace_list.stdout);

    var workspace_info = try runCapture(std.testing.allocator, "workspace-info ops", 512, 256);
    defer workspace_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, workspace_info.stdout, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_info.stdout, "trust_bundle=root-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_info.stdout, "display=1024x768") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_info.stdout, "channel=demo:stable:r1") != null);

    var save_workspace_plan_golden = try runCapture(std.testing.allocator, "workspace-plan-save ops golden duo root-a 1024 768 demo:stable:r1", 256, 256);
    defer save_workspace_plan_golden.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_plan_golden.exit_code);
    try std.testing.expectEqualStrings("workspace plan saved ops golden\n", save_workspace_plan_golden.stdout);

    var save_workspace_plan_staging = try runCapture(std.testing.allocator, "workspace-plan-save ops staging none none 640 400 demo:stable:r2", 256, 256);
    defer save_workspace_plan_staging.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_plan_staging.exit_code);
    try std.testing.expectEqualStrings("workspace plan saved ops staging\n", save_workspace_plan_staging.stdout);

    var workspace_plan_list = try runCapture(std.testing.allocator, "workspace-plan-list ops", 256, 256);
    defer workspace_plan_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_plan_list.exit_code);
    try std.testing.expectEqualStrings("golden\nstaging\n", workspace_plan_list.stdout);

    var workspace_plan_info = try runCapture(std.testing.allocator, "workspace-plan-info ops staging", 512, 256);
    defer workspace_plan_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_plan_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_info.stdout, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_info.stdout, "plan=staging") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_info.stdout, "suite=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_info.stdout, "trust_bundle=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_info.stdout, "display=640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_info.stdout, "channel=demo:stable:r2") != null);

    var apply_workspace_plan_staging = try runCapture(std.testing.allocator, "workspace-plan-apply ops staging", 256, 256);
    defer apply_workspace_plan_staging.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), apply_workspace_plan_staging.exit_code);
    try std.testing.expectEqualStrings("workspace plan applied ops staging\n", apply_workspace_plan_staging.stdout);

    var workspace_plan_active = try runCapture(std.testing.allocator, "workspace-plan-active ops", 512, 256);
    defer workspace_plan_active.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_plan_active.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_active.stdout, "active_plan=staging") != null);

    var staging_plan_workspace_info = try runCapture(std.testing.allocator, "workspace-info ops", 512, 256);
    defer staging_plan_workspace_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), staging_plan_workspace_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, staging_plan_workspace_info.stdout, "suite=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, staging_plan_workspace_info.stdout, "trust_bundle=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, staging_plan_workspace_info.stdout, "display=640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, staging_plan_workspace_info.stdout, "channel=demo:stable:r2") != null);

    var apply_workspace_plan_golden = try runCapture(std.testing.allocator, "workspace-plan-apply ops golden", 256, 256);
    defer apply_workspace_plan_golden.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), apply_workspace_plan_golden.exit_code);
    try std.testing.expectEqualStrings("workspace plan applied ops golden\n", apply_workspace_plan_golden.stdout);

    var restored_plan_workspace_info = try runCapture(std.testing.allocator, "workspace-info ops", 512, 256);
    defer restored_plan_workspace_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), restored_plan_workspace_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, restored_plan_workspace_info.stdout, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored_plan_workspace_info.stdout, "trust_bundle=root-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored_plan_workspace_info.stdout, "display=1024x768") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored_plan_workspace_info.stdout, "channel=demo:stable:r1") != null);

    var delete_workspace_plan_staging = try runCapture(std.testing.allocator, "workspace-plan-delete ops staging", 256, 256);
    defer delete_workspace_plan_staging.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_workspace_plan_staging.exit_code);
    try std.testing.expectEqualStrings("workspace plan deleted ops staging\n", delete_workspace_plan_staging.stdout);

    var workspace_plan_list_after_delete = try runCapture(std.testing.allocator, "workspace-plan-list ops", 256, 256);
    defer workspace_plan_list_after_delete.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_plan_list_after_delete.exit_code);
    try std.testing.expectEqualStrings("golden\n", workspace_plan_list_after_delete.stdout);

    var save_workspace_plan_release_v1 = try runCapture(std.testing.allocator, "workspace-plan-release-save ops golden v1", 256, 256);
    defer save_workspace_plan_release_v1.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_plan_release_v1.exit_code);
    try std.testing.expectEqualStrings("workspace plan release saved ops golden v1\n", save_workspace_plan_release_v1.stdout);

    var mutate_workspace_plan_golden = try runCapture(std.testing.allocator, "workspace-plan-save ops golden none root-b 800 600 demo:stable:r2", 256, 256);
    defer mutate_workspace_plan_golden.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), mutate_workspace_plan_golden.exit_code);
    try std.testing.expectEqualStrings("workspace plan saved ops golden\n", mutate_workspace_plan_golden.stdout);

    var save_workspace_plan_release_v2 = try runCapture(std.testing.allocator, "workspace-plan-release-save ops golden v2", 256, 256);
    defer save_workspace_plan_release_v2.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_plan_release_v2.exit_code);
    try std.testing.expectEqualStrings("workspace plan release saved ops golden v2\n", save_workspace_plan_release_v2.stdout);

    var workspace_plan_release_list = try runCapture(std.testing.allocator, "workspace-plan-release-list ops golden", 256, 256);
    defer workspace_plan_release_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_plan_release_list.exit_code);
    try std.testing.expectEqualStrings("v1\nv2\n", workspace_plan_release_list.stdout);

    var workspace_plan_release_info = try runCapture(std.testing.allocator, "workspace-plan-release-info ops golden v2", 512, 256);
    defer workspace_plan_release_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_plan_release_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_release_info.stdout, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_release_info.stdout, "plan=golden") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_release_info.stdout, "release=v2") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_release_info.stdout, "saved_seq=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_release_info.stdout, "trust_bundle=root-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_release_info.stdout, "display=800x600") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_plan_release_info.stdout, "channel=demo:stable:r2") != null);

    var activate_workspace_plan_release_v1 = try runCapture(std.testing.allocator, "workspace-plan-release-activate ops golden v1", 256, 256);
    defer activate_workspace_plan_release_v1.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_workspace_plan_release_v1.exit_code);
    try std.testing.expectEqualStrings("workspace plan release activated ops golden v1\n", activate_workspace_plan_release_v1.stdout);

    var restored_workspace_plan_info = try runCapture(std.testing.allocator, "workspace-plan-info ops golden", 512, 256);
    defer restored_workspace_plan_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), restored_workspace_plan_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, restored_workspace_plan_info.stdout, "trust_bundle=root-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored_workspace_plan_info.stdout, "display=1024x768") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored_workspace_plan_info.stdout, "channel=demo:stable:r1") != null);

    var delete_workspace_plan_release_v2 = try runCapture(std.testing.allocator, "workspace-plan-release-delete ops golden v2", 256, 256);
    defer delete_workspace_plan_release_v2.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_workspace_plan_release_v2.exit_code);
    try std.testing.expectEqualStrings("workspace plan release deleted ops golden v2\n", delete_workspace_plan_release_v2.stdout);

    var mutate_workspace_plan_golden_again = try runCapture(std.testing.allocator, "workspace-plan-save ops golden duo root-b 1280 720 demo:stable:r2", 256, 256);
    defer mutate_workspace_plan_golden_again.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), mutate_workspace_plan_golden_again.exit_code);
    try std.testing.expectEqualStrings("workspace plan saved ops golden\n", mutate_workspace_plan_golden_again.stdout);

    var save_workspace_plan_release_fallback = try runCapture(std.testing.allocator, "workspace-plan-release-save ops golden fallback", 256, 256);
    defer save_workspace_plan_release_fallback.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_plan_release_fallback.exit_code);
    try std.testing.expectEqualStrings("workspace plan release saved ops golden fallback\n", save_workspace_plan_release_fallback.stdout);

    var prune_workspace_plan_release = try runCapture(std.testing.allocator, "workspace-plan-release-prune ops golden 1", 256, 256);
    defer prune_workspace_plan_release.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), prune_workspace_plan_release.exit_code);
    try std.testing.expectEqualStrings("workspace plan release pruned ops golden keep=1 deleted=1 kept=1\n", prune_workspace_plan_release.stdout);

    var workspace_plan_release_list_after_prune = try runCapture(std.testing.allocator, "workspace-plan-release-list ops golden", 256, 256);
    defer workspace_plan_release_list_after_prune.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_plan_release_list_after_prune.exit_code);
    try std.testing.expectEqualStrings("fallback\n", workspace_plan_release_list_after_prune.stdout);

    var save_workspace_release = try runCapture(std.testing.allocator, "workspace-release-save ops golden", 256, 256);
    defer save_workspace_release.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_release.exit_code);
    try std.testing.expectEqualStrings("workspace release saved ops golden\n", save_workspace_release.stdout);

    var mutate_workspace = try runCapture(std.testing.allocator, "workspace-save ops duo root-b 640 400 demo:stable:r2", 256, 256);
    defer mutate_workspace.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), mutate_workspace.exit_code);
    try std.testing.expectEqualStrings("workspace saved ops\n", mutate_workspace.stdout);

    var save_workspace_release_staging = try runCapture(std.testing.allocator, "workspace-release-save ops staging", 256, 256);
    defer save_workspace_release_staging.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_release_staging.exit_code);
    try std.testing.expectEqualStrings("workspace release saved ops staging\n", save_workspace_release_staging.stdout);

    var workspace_release_list = try runCapture(std.testing.allocator, "workspace-release-list ops", 256, 256);
    defer workspace_release_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_release_list.exit_code);
    try std.testing.expectEqualStrings("golden\nstaging\n", workspace_release_list.stdout);

    var workspace_release_info = try runCapture(std.testing.allocator, "workspace-release-info ops staging", 512, 256);
    defer workspace_release_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_release_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, workspace_release_info.stdout, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_release_info.stdout, "release=staging") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_release_info.stdout, "saved_seq=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_release_info.stdout, "trust_bundle=root-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_release_info.stdout, "display=640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_release_info.stdout, "channel=demo:stable:r2") != null);

    var set_workspace_release_channel_staging = try runCapture(std.testing.allocator, "workspace-release-channel-set ops stable staging", 256, 256);
    defer set_workspace_release_channel_staging.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), set_workspace_release_channel_staging.exit_code);
    try std.testing.expectEqualStrings("workspace release channel set ops stable staging\n", set_workspace_release_channel_staging.stdout);

    var workspace_release_channel_list = try runCapture(std.testing.allocator, "workspace-release-channel-list ops", 256, 256);
    defer workspace_release_channel_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_release_channel_list.exit_code);
    try std.testing.expectEqualStrings("stable\n", workspace_release_channel_list.stdout);

    var workspace_release_channel_info = try runCapture(std.testing.allocator, "workspace-release-channel-info ops stable", 256, 256);
    defer workspace_release_channel_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_release_channel_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, workspace_release_channel_info.stdout, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_release_channel_info.stdout, "channel=stable") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_release_channel_info.stdout, "release=staging") != null);

    var activate_workspace_release_channel_staging = try runCapture(std.testing.allocator, "workspace-release-channel-activate ops stable", 256, 256);
    defer activate_workspace_release_channel_staging.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_workspace_release_channel_staging.exit_code);
    try std.testing.expectEqualStrings("workspace release channel activated ops stable\n", activate_workspace_release_channel_staging.stdout);

    var staging_workspace_info = try runCapture(std.testing.allocator, "workspace-info ops", 512, 256);
    defer staging_workspace_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), staging_workspace_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, staging_workspace_info.stdout, "trust_bundle=root-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, staging_workspace_info.stdout, "display=640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, staging_workspace_info.stdout, "channel=demo:stable:r2") != null);

    var set_workspace_release_channel_golden = try runCapture(std.testing.allocator, "workspace-release-channel-set ops stable golden", 256, 256);
    defer set_workspace_release_channel_golden.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), set_workspace_release_channel_golden.exit_code);
    try std.testing.expectEqualStrings("workspace release channel set ops stable golden\n", set_workspace_release_channel_golden.stdout);

    var activate_workspace_release_channel_golden = try runCapture(std.testing.allocator, "workspace-release-channel-activate ops stable", 256, 256);
    defer activate_workspace_release_channel_golden.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_workspace_release_channel_golden.exit_code);
    try std.testing.expectEqualStrings("workspace release channel activated ops stable\n", activate_workspace_release_channel_golden.stdout);

    var activate_workspace_release = try runCapture(std.testing.allocator, "workspace-release-activate ops golden", 256, 256);
    defer activate_workspace_release.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_workspace_release.exit_code);
    try std.testing.expectEqualStrings("workspace release activated ops golden\n", activate_workspace_release.stdout);

    var restored_workspace_info = try runCapture(std.testing.allocator, "workspace-info ops", 512, 256);
    defer restored_workspace_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), restored_workspace_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, restored_workspace_info.stdout, "trust_bundle=root-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored_workspace_info.stdout, "display=1024x768") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored_workspace_info.stdout, "channel=demo:stable:r1") != null);

    var delete_workspace_release = try runCapture(std.testing.allocator, "workspace-release-delete ops staging", 256, 256);
    defer delete_workspace_release.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_workspace_release.exit_code);
    try std.testing.expectEqualStrings("workspace release deleted ops staging\n", delete_workspace_release.stdout);

    var save_workspace_release_fallback = try runCapture(std.testing.allocator, "workspace-release-save ops fallback", 256, 256);
    defer save_workspace_release_fallback.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_release_fallback.exit_code);
    try std.testing.expectEqualStrings("workspace release saved ops fallback\n", save_workspace_release_fallback.stdout);

    var prune_workspace_release = try runCapture(std.testing.allocator, "workspace-release-prune ops 1", 256, 256);
    defer prune_workspace_release.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), prune_workspace_release.exit_code);
    try std.testing.expectEqualStrings("workspace release pruned ops keep=1 deleted=1 kept=1\n", prune_workspace_release.stdout);

    var workspace_release_list_after_prune = try runCapture(std.testing.allocator, "workspace-release-list ops", 256, 256);
    defer workspace_release_list_after_prune.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_release_list_after_prune.exit_code);
    try std.testing.expectEqualStrings("fallback\n", workspace_release_list_after_prune.stdout);

    try package_store.setPackageReleaseChannel("demo", "stable", "r2", 10);
    try package_store.activatePackageReleaseChannel("demo", "stable", 11);
    try trust_store.selectBundle("root-b", 12);
    try framebuffer_console.setMode(640, 400);

    var apply_demo_alt = try runCapture(std.testing.allocator, "app-plan-apply demo alt", 256, 256);
    defer apply_demo_alt.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), apply_demo_alt.exit_code);

    var apply_aux_alt = try runCapture(std.testing.allocator, "app-plan-apply aux fallback", 256, 256);
    defer apply_aux_alt.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), apply_aux_alt.exit_code);

    var apply_workspace = try runCapture(std.testing.allocator, "workspace-apply ops", 256, 256);
    defer apply_workspace.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), apply_workspace.exit_code);
    try std.testing.expectEqualStrings("workspace applied ops\n", apply_workspace.stdout);

    var trust_active = try runCapture(std.testing.allocator, "trust-active", 256, 256);
    defer trust_active.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), trust_active.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, trust_active.stdout, "name=root-a") != null);

    var display_info = try runCapture(std.testing.allocator, "display-info", 256, 256);
    defer display_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), display_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, display_info.stdout, "current=1024x768") != null);

    var demo_active = try runCapture(std.testing.allocator, "app-plan-active demo", 256, 256);
    defer demo_active.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), demo_active.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, demo_active.stdout, "active_plan=golden") != null);

    var aux_active = try runCapture(std.testing.allocator, "app-plan-active aux", 256, 256);
    defer aux_active.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), aux_active.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, aux_active.stdout, "active_plan=sidecar") != null);

    var workspace_run = try runCapture(std.testing.allocator, "workspace-run ops", 256, 256);
    defer workspace_run.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_run.exit_code);
    try std.testing.expectEqualStrings("release-r1\naux-sidecar\n", workspace_run.stdout);

    var workspace_state = try runCapture(std.testing.allocator, "workspace-state ops", 256, 256);
    defer workspace_state.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_state.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, workspace_state.stdout, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_state.stdout, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_state.stdout, "exit_code=0") != null);

    var workspace_history = try runCapture(std.testing.allocator, "workspace-history ops", 256, 256);
    defer workspace_history.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_history.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, workspace_history.stdout, "workspace=ops") != null);

    var workspace_stdout = try runCapture(std.testing.allocator, "workspace-stdout ops", 256, 256);
    defer workspace_stdout.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_stdout.exit_code);
    try std.testing.expectEqualStrings("release-r1\naux-sidecar\n", workspace_stdout.stdout);

    var workspace_stderr = try runCapture(std.testing.allocator, "workspace-stderr ops", 256, 256);
    defer workspace_stderr.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_stderr.exit_code);
    try std.testing.expectEqualStrings("", workspace_stderr.stdout);

    var delete_workspace = try runCapture(std.testing.allocator, "workspace-delete ops", 256, 256);
    defer delete_workspace.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_workspace.exit_code);
    try std.testing.expectEqualStrings("workspace deleted ops\n", delete_workspace.stdout);

    var workspace_list_after_delete = try runCapture(std.testing.allocator, "workspace-list", 256, 256);
    defer workspace_list_after_delete.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_list_after_delete.exit_code);
    try std.testing.expectEqualStrings("", workspace_list_after_delete.stdout);
}

test "baremetal tool exec persists and runs workspace suites" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();
    vga_text_console.resetForTest();

    try trust_store.installBundle("root-a", "root-a-cert", 1);
    try trust_store.installBundle("root-b", "root-b-cert", 2);
    try package_store.installScriptPackage("demo", "echo demo-workspace", 3);
    try package_store.installScriptPackage("aux", "echo aux-workspace", 4);

    var save_demo_plan = try runCapture(std.testing.allocator, "app-plan-save demo boot none none virtual 1024 768 0", 256, 256);
    defer save_demo_plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_demo_plan.exit_code);

    var save_aux_plan = try runCapture(std.testing.allocator, "app-plan-save aux sidecar none none virtual 800 600 0", 256, 256);
    defer save_aux_plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_aux_plan.exit_code);

    var save_demo_suite = try runCapture(std.testing.allocator, "app-suite-save demo-suite demo:boot", 256, 256);
    defer save_demo_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_demo_suite.exit_code);

    var save_aux_suite = try runCapture(std.testing.allocator, "app-suite-save aux-suite aux:sidecar", 256, 256);
    defer save_aux_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_aux_suite.exit_code);

    var save_ops = try runCapture(std.testing.allocator, "workspace-save ops demo-suite root-a 1024 768", 256, 256);
    defer save_ops.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_ops.exit_code);

    var save_sidecar = try runCapture(std.testing.allocator, "workspace-save sidecar aux-suite root-b 800 600", 256, 256);
    defer save_sidecar.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_sidecar.exit_code);

    var save_workspace_suite = try runCapture(std.testing.allocator, "workspace-suite-save crew ops sidecar", 256, 256);
    defer save_workspace_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_suite.exit_code);
    try std.testing.expectEqualStrings("workspace suite saved crew\n", save_workspace_suite.stdout);

    var workspace_suite_list = try runCapture(std.testing.allocator, "workspace-suite-list", 256, 256);
    defer workspace_suite_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_suite_list.exit_code);
    try std.testing.expectEqualStrings("crew\n", workspace_suite_list.stdout);

    var workspace_suite_info = try runCapture(std.testing.allocator, "workspace-suite-info crew", 256, 256);
    defer workspace_suite_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_suite_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, workspace_suite_info.stdout, "suite=crew") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_suite_info.stdout, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_suite_info.stdout, "workspace=sidecar") != null);

    var apply_workspace_suite = try runCapture(std.testing.allocator, "workspace-suite-apply crew", 256, 256);
    defer apply_workspace_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), apply_workspace_suite.exit_code);
    try std.testing.expectEqualStrings("workspace suite applied crew\n", apply_workspace_suite.stdout);

    var trust_active = try runCapture(std.testing.allocator, "trust-active", 256, 256);
    defer trust_active.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), trust_active.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, trust_active.stdout, "name=root-b") != null);

    var display_info = try runCapture(std.testing.allocator, "display-info", 256, 256);
    defer display_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), display_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, display_info.stdout, "current=800x600") != null);

    var workspace_suite_run = try runCapture(std.testing.allocator, "workspace-suite-run crew", 256, 256);
    defer workspace_suite_run.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_suite_run.exit_code);
    try std.testing.expectEqualStrings("demo-workspace\naux-workspace\n", workspace_suite_run.stdout);

    var delete_workspace_suite = try runCapture(std.testing.allocator, "workspace-suite-delete crew", 256, 256);
    defer delete_workspace_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_workspace_suite.exit_code);
    try std.testing.expectEqualStrings("workspace suite deleted crew\n", delete_workspace_suite.stdout);

    var workspace_suite_list_after_delete = try runCapture(std.testing.allocator, "workspace-suite-list", 256, 256);
    defer workspace_suite_list_after_delete.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), workspace_suite_list_after_delete.exit_code);
    try std.testing.expectEqualStrings("", workspace_suite_list_after_delete.stdout);
}

test "baremetal tool exec manages workspace suite releases" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();
    vga_text_console.resetForTest();

    try trust_store.installBundle("root-a", "root-a-cert", 1);
    try trust_store.installBundle("root-b", "root-b-cert", 2);
    try package_store.installScriptPackage("demo", "echo demo-workspace", 3);
    try package_store.installScriptPackage("aux", "echo aux-workspace", 4);
    try app_runtime.savePlan("demo", "boot", "", "", abi.display_connector_virtual, 1024, 768, false, 5);
    try app_runtime.savePlan("demo", "canary", "", "", abi.display_connector_virtual, 640, 400, false, 6);
    try app_runtime.savePlan("aux", "sidecar", "", "", abi.display_connector_virtual, 800, 600, false, 7);
    try app_runtime.saveSuite("demo-suite", "demo:boot", 8);
    try app_runtime.saveSuite("aux-suite", "aux:sidecar", 9);

    var save_ops = try runCapture(std.testing.allocator, "workspace-save ops demo-suite root-a 1024 768", 256, 256);
    defer save_ops.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_ops.exit_code);

    var save_sidecar = try runCapture(std.testing.allocator, "workspace-save sidecar aux-suite root-b 800 600", 256, 256);
    defer save_sidecar.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_sidecar.exit_code);

    var save_workspace_suite = try runCapture(std.testing.allocator, "workspace-suite-save crew ops sidecar", 256, 256);
    defer save_workspace_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_suite.exit_code);

    var save_release_golden = try runCapture(std.testing.allocator, "workspace-suite-release-save crew golden", 256, 256);
    defer save_release_golden.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_release_golden.exit_code);
    try std.testing.expectEqualStrings("workspace suite release saved crew golden\n", save_release_golden.stdout);

    var save_ops_canary = try runCapture(std.testing.allocator, "workspace-save ops demo-suite root-b 640 400", 256, 256);
    defer save_ops_canary.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_ops_canary.exit_code);

    var save_workspace_suite_staging = try runCapture(std.testing.allocator, "workspace-suite-save crew ops", 256, 256);
    defer save_workspace_suite_staging.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_suite_staging.exit_code);

    var save_release_staging = try runCapture(std.testing.allocator, "workspace-suite-release-save crew staging", 256, 256);
    defer save_release_staging.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_release_staging.exit_code);
    try std.testing.expectEqualStrings("workspace suite release saved crew staging\n", save_release_staging.stdout);

    var release_list = try runCapture(std.testing.allocator, "workspace-suite-release-list crew", 256, 256);
    defer release_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), release_list.exit_code);
    try std.testing.expectEqualStrings("golden\nstaging\n", release_list.stdout);

    var release_info = try runCapture(std.testing.allocator, "workspace-suite-release-info crew staging", 512, 256);
    defer release_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), release_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, release_info.stdout, "suite=crew") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info.stdout, "release=staging") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info.stdout, "saved_seq=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info.stdout, "workspace=ops") != null);

    var activate_release = try runCapture(std.testing.allocator, "workspace-suite-release-activate crew golden", 256, 256);
    defer activate_release.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_release.exit_code);
    try std.testing.expectEqualStrings("workspace suite release activated crew golden\n", activate_release.stdout);

    var suite_info = try runCapture(std.testing.allocator, "workspace-suite-info crew", 256, 256);
    defer suite_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), suite_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, suite_info.stdout, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info.stdout, "workspace=sidecar") != null);

    var delete_release = try runCapture(std.testing.allocator, "workspace-suite-release-delete crew staging", 256, 256);
    defer delete_release.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_release.exit_code);
    try std.testing.expectEqualStrings("workspace suite release deleted crew staging\n", delete_release.stdout);

    var release_list_after_delete = try runCapture(std.testing.allocator, "workspace-suite-release-list crew", 256, 256);
    defer release_list_after_delete.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), release_list_after_delete.exit_code);
    try std.testing.expectEqualStrings("golden\n", release_list_after_delete.stdout);

    var save_ops_fallback = try runCapture(std.testing.allocator, "workspace-save ops demo-suite root-b 640 400", 256, 256);
    defer save_ops_fallback.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_ops_fallback.exit_code);

    var save_workspace_suite_fallback = try runCapture(std.testing.allocator, "workspace-suite-save crew ops", 256, 256);
    defer save_workspace_suite_fallback.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_suite_fallback.exit_code);

    var save_release_fallback = try runCapture(std.testing.allocator, "workspace-suite-release-save crew fallback", 256, 256);
    defer save_release_fallback.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_release_fallback.exit_code);
    try std.testing.expectEqualStrings("workspace suite release saved crew fallback\n", save_release_fallback.stdout);

    var prune_release = try runCapture(std.testing.allocator, "workspace-suite-release-prune crew 1", 256, 256);
    defer prune_release.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), prune_release.exit_code);
    try std.testing.expectEqualStrings("workspace suite release pruned crew keep=1 deleted=1 kept=1\n", prune_release.stdout);

    var release_list_after_prune = try runCapture(std.testing.allocator, "workspace-suite-release-list crew", 256, 256);
    defer release_list_after_prune.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), release_list_after_prune.exit_code);
    try std.testing.expectEqualStrings("fallback\n", release_list_after_prune.stdout);
}

test "baremetal tool exec manages workspace suite release channels" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();
    vga_text_console.resetForTest();

    try trust_store.installBundle("root-a", "root-a-cert", 1);
    try trust_store.installBundle("root-b", "root-b-cert", 2);
    try package_store.installScriptPackage("demo", "echo demo-workspace", 3);
    try package_store.installScriptPackage("aux", "echo aux-workspace", 4);
    try app_runtime.savePlan("demo", "boot", "", "", abi.display_connector_virtual, 1024, 768, false, 5);
    try app_runtime.savePlan("demo", "canary", "", "", abi.display_connector_virtual, 640, 400, false, 6);
    try app_runtime.savePlan("aux", "sidecar", "", "", abi.display_connector_virtual, 800, 600, false, 7);
    try app_runtime.saveSuite("demo-suite", "demo:boot", 8);
    try app_runtime.saveSuite("aux-suite", "aux:sidecar", 9);

    var save_ops = try runCapture(std.testing.allocator, "workspace-save ops demo-suite root-a 1024 768", 256, 256);
    defer save_ops.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_ops.exit_code);

    var save_sidecar = try runCapture(std.testing.allocator, "workspace-save sidecar aux-suite root-b 800 600", 256, 256);
    defer save_sidecar.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_sidecar.exit_code);

    var save_workspace_suite = try runCapture(std.testing.allocator, "workspace-suite-save crew ops sidecar", 256, 256);
    defer save_workspace_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_suite.exit_code);

    var save_release_golden = try runCapture(std.testing.allocator, "workspace-suite-release-save crew golden", 256, 256);
    defer save_release_golden.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_release_golden.exit_code);

    var save_ops_canary = try runCapture(std.testing.allocator, "workspace-save ops demo-suite root-b 640 400", 256, 256);
    defer save_ops_canary.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_ops_canary.exit_code);

    var save_workspace_suite_staging = try runCapture(std.testing.allocator, "workspace-suite-save crew ops", 256, 256);
    defer save_workspace_suite_staging.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_workspace_suite_staging.exit_code);

    var save_release_staging = try runCapture(std.testing.allocator, "workspace-suite-release-save crew staging", 256, 256);
    defer save_release_staging.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_release_staging.exit_code);

    var set_channel_fallback = try runCapture(std.testing.allocator, "workspace-suite-release-channel-set crew stable staging", 256, 256);
    defer set_channel_fallback.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), set_channel_fallback.exit_code);
    try std.testing.expectEqualStrings("workspace suite release channel set crew stable staging\n", set_channel_fallback.stdout);

    var channel_list = try runCapture(std.testing.allocator, "workspace-suite-release-channel-list crew", 256, 256);
    defer channel_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), channel_list.exit_code);
    try std.testing.expectEqualStrings("stable\n", channel_list.stdout);

    var channel_info = try runCapture(std.testing.allocator, "workspace-suite-release-channel-info crew stable", 256, 256);
    defer channel_info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), channel_info.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, channel_info.stdout, "suite=crew") != null);
    try std.testing.expect(std.mem.indexOf(u8, channel_info.stdout, "channel=stable") != null);
    try std.testing.expect(std.mem.indexOf(u8, channel_info.stdout, "release=staging") != null);

    var activate_channel = try runCapture(std.testing.allocator, "workspace-suite-release-channel-activate crew stable", 256, 256);
    defer activate_channel.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), activate_channel.exit_code);
    try std.testing.expectEqualStrings("workspace suite release channel activated crew stable\n", activate_channel.stdout);

    var suite_info_after_channel = try runCapture(std.testing.allocator, "workspace-suite-info crew", 256, 256);
    defer suite_info_after_channel.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), suite_info_after_channel.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, suite_info_after_channel.stdout, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info_after_channel.stdout, "workspace=sidecar") == null);
}

test "baremetal tool exec persists and runs workspace autorun" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();
    vga_text_console.resetForTest();

    try package_store.installScriptPackage("demo", "echo demo-workspace", 1);
    try package_store.installScriptPackage("aux", "echo aux-workspace", 2);

    var save_demo_plan = try runCapture(std.testing.allocator, "app-plan-save demo boot none none virtual 1024 768 0", 256, 256);
    defer save_demo_plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_demo_plan.exit_code);

    var save_aux_plan = try runCapture(std.testing.allocator, "app-plan-save aux sidecar none none virtual 800 600 0", 256, 256);
    defer save_aux_plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_aux_plan.exit_code);

    var save_demo_suite = try runCapture(std.testing.allocator, "app-suite-save demo-suite demo:boot", 256, 256);
    defer save_demo_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_demo_suite.exit_code);

    var save_aux_suite = try runCapture(std.testing.allocator, "app-suite-save aux-suite aux:sidecar", 256, 256);
    defer save_aux_suite.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_aux_suite.exit_code);

    var save_ops = try runCapture(std.testing.allocator, "workspace-save ops demo-suite none 1024 768", 256, 256);
    defer save_ops.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_ops.exit_code);
    try std.testing.expectEqualStrings("workspace saved ops\n", save_ops.stdout);

    var save_sidecar = try runCapture(std.testing.allocator, "workspace-save sidecar aux-suite none 800 600", 256, 256);
    defer save_sidecar.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), save_sidecar.exit_code);
    try std.testing.expectEqualStrings("workspace saved sidecar\n", save_sidecar.stdout);

    var add_ops = try runCapture(std.testing.allocator, "workspace-autorun-add ops", 256, 256);
    defer add_ops.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), add_ops.exit_code);
    try std.testing.expectEqualStrings("workspace autorun add ops\n", add_ops.stdout);

    var add_sidecar = try runCapture(std.testing.allocator, "workspace-autorun-add sidecar", 256, 256);
    defer add_sidecar.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), add_sidecar.exit_code);
    try std.testing.expectEqualStrings("workspace autorun add sidecar\n", add_sidecar.stdout);

    var autorun_list = try runCapture(std.testing.allocator, "workspace-autorun-list", 256, 256);
    defer autorun_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), autorun_list.exit_code);
    try std.testing.expectEqualStrings("ops\nsidecar\n", autorun_list.stdout);

    var autorun_run = try runCapture(std.testing.allocator, "workspace-autorun-run", 256, 256);
    defer autorun_run.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), autorun_run.exit_code);
    try std.testing.expectEqualStrings("demo-workspace\naux-workspace\n", autorun_run.stdout);

    const sidecar_state = try workspace_runtime.stateAlloc(std.testing.allocator, "sidecar", 256);
    defer std.testing.allocator.free(sidecar_state);
    try std.testing.expect(std.mem.indexOf(u8, sidecar_state, "exit_code=0") != null);

    const sidecar_stdout = try workspace_runtime.stdoutAlloc(std.testing.allocator, "sidecar", 256);
    defer std.testing.allocator.free(sidecar_stdout);
    try std.testing.expectEqualStrings("aux-workspace\n", sidecar_stdout);

    var remove_ops = try runCapture(std.testing.allocator, "workspace-autorun-remove ops", 256, 256);
    defer remove_ops.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), remove_ops.exit_code);
    try std.testing.expectEqualStrings("workspace autorun remove ops\n", remove_ops.stdout);

    var updated_autorun_list = try runCapture(std.testing.allocator, "workspace-autorun-list", 256, 256);
    defer updated_autorun_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), updated_autorun_list.exit_code);
    try std.testing.expectEqualStrings("sidecar\n", updated_autorun_list.stdout);

    var delete_sidecar = try runCapture(std.testing.allocator, "workspace-delete sidecar", 256, 256);
    defer delete_sidecar.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), delete_sidecar.exit_code);

    var final_autorun_list = try runCapture(std.testing.allocator, "workspace-autorun-list", 256, 256);
    defer final_autorun_list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), final_autorun_list.exit_code);
    try std.testing.expectEqualStrings("", final_autorun_list.stdout);
}
