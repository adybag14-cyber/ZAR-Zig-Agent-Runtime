const std = @import("std");
const abi = @import("abi.zig");
const filesystem = @import("filesystem.zig");
const package_store = @import("package_store.zig");
const trust_store = @import("trust_store.zig");
const display_output = @import("display_output.zig");
const framebuffer_console = @import("framebuffer_console.zig");
const vga_text_console = @import("vga_text_console.zig");
const storage_backend = @import("storage_backend.zig");

pub const Error = filesystem.Error || trust_store.Error || std.mem.Allocator.Error || error{
    MissingCommand,
    MissingPath,
    StreamTooLong,
    InvalidQuotedArgument,
    ScriptDepthExceeded,
};

const max_script_depth: usize = 4;

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

pub fn runCapture(
    allocator: std.mem.Allocator,
    command: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
) Error!Result {
    var stdout_buffer = OutputBuffer.init(allocator, stdout_limit, true);
    errdefer stdout_buffer.deinit();
    var stderr_buffer = OutputBuffer.init(allocator, stderr_limit, true);
    errdefer stderr_buffer.deinit();

    var exit_code: u8 = 0;
    try filesystem.init();

    const parsed = parseCommand(command) catch |err| {
        exit_code = 2;
        try writeCommandError(&stderr_buffer, err, "command");
        return .{
            .exit_code = exit_code,
            .stdout = try stdout_buffer.toOwnedSlice(),
            .stderr = try stderr_buffer.toOwnedSlice(),
        };
    };

    execute(parsed, &stdout_buffer, &stderr_buffer, &exit_code, allocator, 0) catch |err| {
        exit_code = 1;
        try stderr_buffer.appendFmt("{s}\n", .{@errorName(err)});
    };

    return .{
        .exit_code = exit_code,
        .stdout = try stdout_buffer.toOwnedSlice(),
        .stderr = try stderr_buffer.toOwnedSlice(),
    };
}

fn execute(
    parsed: ParsedCommand,
    stdout_buffer: *OutputBuffer,
    stderr_buffer: *OutputBuffer,
    exit_code: *u8,
    allocator: std.mem.Allocator,
    depth: usize,
) Error!void {
    if (depth > max_script_depth) return error.ScriptDepthExceeded;

    if (std.ascii.eqlIgnoreCase(parsed.name, "help")) {
        try stdout_buffer.appendLine("OpenClaw bare-metal builtins: help, echo, cat, write-file, mkdir, stat, ls, package-info, package-ls, package-cat, trust-list, trust-info, trust-active, trust-select, trust-delete, display-info, display-modes, run-script, run-package");
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "echo")) {
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
        filesystem.createDirPath(arg.arg) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("mkdir failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("created {s}\n", .{arg.arg});
        return;
    }

    if (std.ascii.eqlIgnoreCase(parsed.name, "cat")) {
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
        const content = filesystem.readFileAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
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
        const content = arg.rest;
        if (content.len == 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: write-file <path> <content>");
            return;
        }
        ensureParentDirectory(arg.arg) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("write-file failed: {s}\n", .{@errorName(err)});
            return;
        };
        filesystem.writeFile(arg.arg, content, 0) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("write-file failed: {s}\n", .{@errorName(err)});
            return;
        };
        try stdout_buffer.appendFmt("wrote {d} bytes to {s}\n", .{ content.len, arg.arg });
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
        const stat = filesystem.statSummary(arg.arg) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("stat failed: {s}\n", .{@errorName(err)});
            return;
        };
        const kind = switch (stat.kind) {
            .directory => "directory",
            .file => "file",
            else => "unknown",
        };
        try stdout_buffer.appendFmt("path={s} kind={s} size={d}\n", .{ arg.arg, kind, stat.size });
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
        const listing = filesystem.listDirectoryAlloc(allocator, arg.arg, stdout_buffer.limit) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("ls failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(listing);
        try stdout_buffer.appendSlice(listing);
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

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-info")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-info");
            return;
        }
        _ = framebuffer_console.init();
        const output = display_output.statePtr();
        try stdout_buffer.appendFmt(
            "backend={s} controller={s} connector={s} connected={d} hardware_backed={d} current={d}x{d} preferred={d}x{d} scanouts={d} active={d} capabilities=0x{x}\n",
            .{
                displayBackendName(output.backend),
                displayControllerName(output.controller),
                displayConnectorName(output.connector_type),
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

    if (std.ascii.eqlIgnoreCase(parsed.name, "display-modes")) {
        if (parsed.rest.len != 0) {
            exit_code.* = 2;
            try stderr_buffer.appendLine("usage: display-modes");
            return;
        }
        _ = framebuffer_console.init();
        var index: u16 = 0;
        while (index < framebuffer_console.supportedModeCount()) : (index += 1) {
            try stdout_buffer.appendFmt(
                "mode {d} {d}x{d}\n",
                .{ index, framebuffer_console.supportedModeWidth(index), framebuffer_console.supportedModeHeight(index) },
            );
        }
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

        var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
        const entrypoint = package_store.entrypointPath(arg.arg, &entrypoint_buf) catch |err| {
            exit_code.* = 1;
            try stderr_buffer.appendFmt("run-package failed: {s}\n", .{@errorName(err)});
            return;
        };
        try executeScriptPath(entrypoint, "run-package", stdout_buffer, stderr_buffer, exit_code, allocator, depth);
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
        const end_index = std.mem.indexOfScalarPos(u8, trimmed, 1, quote) orelse return error.InvalidQuotedArgument;
        const arg = trimmed[1..end_index];
        const rest = trimLeftWhitespace(trimmed[end_index + 1 ..]);
        return .{ .arg = arg, .rest = rest };
    }

    var idx: usize = 0;
    while (idx < trimmed.len and !std.ascii.isWhitespace(trimmed[idx])) : (idx += 1) {}
    return .{
        .arg = trimmed[0..idx],
        .rest = trimLeftWhitespace(trimmed[idx..]),
    };
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

    var lines = std.mem.splitScalar(u8, script, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const nested = parseCommand(line) catch |err| {
            exit_code.* = 2;
            try writeCommandError(stderr_buffer, err, operation);
            return;
        };
        try execute(nested, stdout_buffer, stderr_buffer, exit_code, allocator, depth + 1);
        if (exit_code.* != 0) return;
    }
}

fn writeCommandError(stderr_buffer: *OutputBuffer, err: anyerror, usage: []const u8) Error!void {
    switch (err) {
        error.MissingCommand, error.MissingPath, error.InvalidQuotedArgument => {
            try stderr_buffer.appendFmt("usage: {s}\n", .{usage});
        },
        else => try stderr_buffer.appendFmt("{s}\n", .{@errorName(err)}),
    }
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

    var info_result = try runCapture(std.testing.allocator, "package-info demo", 256, 256);
    defer info_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), info_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "root=/packages/demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_result.stdout, "script_bytes=15") != null);
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

    var modes_result = try runCapture(std.testing.allocator, "display-modes", 256, 256);
    defer modes_result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), modes_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, modes_result.stdout, "mode 0 640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, modes_result.stdout, "mode 4 1280x1024") != null);
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
