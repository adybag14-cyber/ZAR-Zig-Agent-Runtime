const builtin = @import("builtin");
const std = @import("std");
const config = @import("../config.zig");
const state = @import("state.zig");
const time_util = @import("../util/time.zig");

pub const InputError = error{
    InvalidParamsFrame,
    MissingCommand,
    MissingPath,
    MissingContent,
    CommandDenied,
    PathAccessDenied,
    PathTraversalDetected,
    PathSymlinkDisallowed,
};

pub const ExecResult = struct {
    ok: bool,
    status: u16,
    state: []const u8,
    jobId: u64,
    sessionId: []const u8,
    command: []const u8,
    exitCode: i32,
    stdout: []const u8,
    stderr: []const u8,

    pub fn deinit(self: *ExecResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.command);
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

pub const FileReadResult = struct {
    ok: bool,
    status: u16,
    state: []const u8,
    jobId: u64,
    sessionId: []const u8,
    path: []const u8,
    bytes: usize,
    content: []const u8,

    pub fn deinit(self: *FileReadResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.path);
        allocator.free(self.content);
    }
};

pub const FileWriteResult = struct {
    ok: bool,
    status: u16,
    state: []const u8,
    jobId: u64,
    sessionId: []const u8,
    path: []const u8,
    bytes: usize,
    createdDirs: bool,

    pub fn deinit(self: *FileWriteResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.path);
    }
};

pub const ToolRuntime = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    runtime_state: state.RuntimeState,
    file_sandbox_enabled: bool,
    file_allowed_roots: []const u8,
    exec_enabled: bool,
    exec_allowlist: []const u8,

    const default_session_id = "session-local";
    const default_exec_timeout_ms: u32 = 20_000;
    const max_exec_output_bytes: usize = 1024 * 1024;
    const max_file_read_bytes: usize = 1024 * 1024;

    pub fn init(allocator: std.mem.Allocator, io: std.Io) ToolRuntime {
        return .{
            .allocator = allocator,
            .io = io,
            .runtime_state = state.RuntimeState.init(allocator),
            .file_sandbox_enabled = false,
            .file_allowed_roots = "",
            .exec_enabled = true,
            .exec_allowlist = "",
        };
    }

    pub fn deinit(self: *ToolRuntime) void {
        self.runtime_state.deinit();
    }

    pub fn queueDepth(self: *const ToolRuntime) usize {
        return self.runtime_state.queueDepth();
    }

    pub fn sessionCount(self: *const ToolRuntime) usize {
        return self.runtime_state.sessionCount();
    }

    pub fn configureRuntimePolicy(
        self: *ToolRuntime,
        runtime_cfg: config.RuntimeConfig,
    ) void {
        self.file_sandbox_enabled = runtime_cfg.file_sandbox_enabled;
        self.file_allowed_roots = runtime_cfg.file_allowed_roots;
        self.exec_enabled = runtime_cfg.exec_enabled;
        self.exec_allowlist = runtime_cfg.exec_allowlist;
    }

    pub fn execRunFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !ExecResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const command = try getRequiredString(params, "command", "cmd", error.MissingCommand);
        const session_id = getOptionalString(params, "sessionId", default_session_id);
        const timeout_ms = getOptionalU32(params, "timeoutMs", default_exec_timeout_ms);
        return self.execRun(allocator, session_id, command, timeout_ms);
    }

    pub fn fileReadFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !FileReadResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const path = try getRequiredString(params, "path", null, error.MissingPath);
        const session_id = getOptionalString(params, "sessionId", default_session_id);
        return self.fileRead(allocator, session_id, path);
    }

    pub fn fileWriteFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !FileWriteResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const path = try getRequiredString(params, "path", null, error.MissingPath);
        const content = try getRequiredString(params, "content", null, error.MissingContent);
        const session_id = getOptionalString(params, "sessionId", default_session_id);
        return self.fileWrite(allocator, session_id, path, content);
    }

    fn execRun(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        command: []const u8,
        timeout_ms: u32,
    ) !ExecResult {
        if (!self.exec_enabled or !isCommandAllowed(command, self.exec_allowlist)) {
            return error.CommandDenied;
        }

        const job_id = try self.runtime_state.enqueueJob(.exec, command);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        const argv = switch (builtin.os.tag) {
            .windows => [_][]const u8{ "C:\\Windows\\System32\\cmd.exe", "/C", command },
            else => [_][]const u8{ "/bin/sh", "-lc", command },
        };
        const timeout: std.Io.Timeout = switch (builtin.os.tag) {
            .windows => .none,
            else => .{
                .duration = std.Io.Clock.Duration{
                    .clock = .awake,
                    .raw = std.Io.Duration.fromMilliseconds(timeout_ms),
                },
            },
        };

        const run_result = try std.process.run(self.allocator, self.io, .{
            .argv = &argv,
            .timeout = timeout,
            .stdout_limit = .limited(max_exec_output_bytes),
            .stderr_limit = .limited(max_exec_output_bytes),
        });
        defer self.allocator.free(run_result.stdout);
        defer self.allocator.free(run_result.stderr);

        const exit_code: i32 = switch (run_result.term) {
            .exited => |code| code,
            .signal => |sig| -@as(i32, @intCast(@intFromEnum(sig))),
            .stopped, .unknown => -1,
        };

        const session_copy = try allocator.dupe(u8, session_id);
        errdefer allocator.free(session_copy);
        const command_copy = try allocator.dupe(u8, command);
        errdefer allocator.free(command_copy);
        const stdout_copy = try allocator.dupe(u8, run_result.stdout);
        errdefer allocator.free(stdout_copy);
        const stderr_copy = try allocator.dupe(u8, run_result.stderr);
        errdefer allocator.free(stderr_copy);

        try self.runtime_state.upsertSession(session_id, command, nowUnixMilliseconds(self.io));

        return .{
            .ok = exit_code == 0,
            .status = if (exit_code == 0) 200 else 500,
            .state = "completed",
            .jobId = job_id,
            .sessionId = session_copy,
            .command = command_copy,
            .exitCode = exit_code,
            .stdout = stdout_copy,
            .stderr = stderr_copy,
        };
    }

    fn fileRead(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        path: []const u8,
    ) !FileReadResult {
        const effective_path = try self.resolveSandboxedPath(allocator, path, .read);
        defer allocator.free(effective_path);

        const job_id = try self.runtime_state.enqueueJob(.file_read, effective_path);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        const content = try std.Io.Dir.cwd().readFileAlloc(self.io, effective_path, allocator, .limited(max_file_read_bytes));
        errdefer allocator.free(content);
        const session_copy = try allocator.dupe(u8, session_id);
        errdefer allocator.free(session_copy);
        const path_copy = try allocator.dupe(u8, effective_path);
        errdefer allocator.free(path_copy);

        const session_note = try std.fmt.allocPrint(self.allocator, "file.read:{s}", .{effective_path});
        defer self.allocator.free(session_note);
        try self.runtime_state.upsertSession(session_id, session_note, nowUnixMilliseconds(self.io));

        return .{
            .ok = true,
            .status = 200,
            .state = "completed",
            .jobId = job_id,
            .sessionId = session_copy,
            .path = path_copy,
            .bytes = content.len,
            .content = content,
        };
    }

    fn fileWrite(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        path: []const u8,
        content: []const u8,
    ) !FileWriteResult {
        const effective_path = try self.resolveSandboxedPath(allocator, path, .write);
        defer allocator.free(effective_path);

        const job_id = try self.runtime_state.enqueueJob(.file_write, effective_path);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        var created_dirs = false;
        if (std.fs.path.dirname(effective_path)) |dir_name| {
            if (dir_name.len > 0) {
                try std.Io.Dir.cwd().createDirPath(self.io, dir_name);
                created_dirs = true;
            }
        }

        try self.verifyWritePathAfterMkdir(allocator, effective_path);

        try std.Io.Dir.cwd().writeFile(self.io, .{
            .sub_path = effective_path,
            .data = content,
        });

        const session_copy = try allocator.dupe(u8, session_id);
        errdefer allocator.free(session_copy);
        const path_copy = try allocator.dupe(u8, effective_path);
        errdefer allocator.free(path_copy);

        const session_note = try std.fmt.allocPrint(self.allocator, "file.write:{s}", .{effective_path});
        defer self.allocator.free(session_note);
        try self.runtime_state.upsertSession(session_id, session_note, nowUnixMilliseconds(self.io));

        return .{
            .ok = true,
            .status = 200,
            .state = "completed",
            .jobId = job_id,
            .sessionId = session_copy,
            .path = path_copy,
            .bytes = content.len,
            .createdDirs = created_dirs,
        };
    }

    const FileMode = enum { read, write };

    fn resolveSandboxedPath(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        path: []const u8,
        mode: FileMode,
    ) ![]u8 {
        if (!self.file_sandbox_enabled) {
            return allocator.dupe(u8, path);
        }

        if (hasParentTraversal(path)) {
            return error.PathTraversalDetected;
        }

        const absolute_path = try resolveAbsolutePath(self.io, allocator, path);
        errdefer allocator.free(absolute_path);

        var roots = try parseAllowedRoots(self.io, allocator, self.file_allowed_roots);
        defer freePathList(allocator, &roots);
        if (roots.items.len == 0) {
            return error.PathAccessDenied;
        }

        if (!isWithinAnyRoot(absolute_path, roots.items)) {
            return error.PathAccessDenied;
        }

        switch (mode) {
            .read => {
                const target_real_z = std.Io.Dir.realPathFileAbsoluteAlloc(self.io, absolute_path, allocator) catch return error.PathAccessDenied;
                defer allocator.free(target_real_z);
                const target_real = std.mem.sliceTo(target_real_z, 0);
                if (!isWithinAnyRoot(target_real, roots.items)) {
                    return error.PathAccessDenied;
                }
                const stat = std.Io.Dir.cwd().statFile(self.io, absolute_path, .{ .follow_symlinks = false }) catch return error.PathAccessDenied;
                if (stat.kind == .sym_link) return error.PathSymlinkDisallowed;
            },
            .write => {
                const stat = std.Io.Dir.cwd().statFile(self.io, absolute_path, .{ .follow_symlinks = false }) catch |err| switch (err) {
                    error.FileNotFound => null,
                    else => return error.PathAccessDenied,
                };
                if (stat) |entry| {
                    if (entry.kind == .sym_link) return error.PathSymlinkDisallowed;
                }

                const parent = std.fs.path.dirname(absolute_path) orelse return error.PathAccessDenied;
                const parent_real = try resolveNearestExistingPath(self.io, allocator, parent);
                defer allocator.free(parent_real);
                if (!isWithinAnyRoot(parent_real, roots.items)) {
                    return error.PathAccessDenied;
                }
            },
        }

        return absolute_path;
    }

    fn verifyWritePathAfterMkdir(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        path: []const u8,
    ) !void {
        if (!self.file_sandbox_enabled) return;

        var roots = try parseAllowedRoots(self.io, allocator, self.file_allowed_roots);
        defer freePathList(allocator, &roots);
        if (roots.items.len == 0) return error.PathAccessDenied;

        const parent = std.fs.path.dirname(path) orelse return error.PathAccessDenied;
        const parent_real_z = std.Io.Dir.realPathFileAbsoluteAlloc(self.io, parent, allocator) catch return error.PathAccessDenied;
        defer allocator.free(parent_real_z);
        const parent_real = std.mem.sliceTo(parent_real_z, 0);
        if (!isWithinAnyRoot(parent_real, roots.items)) {
            return error.PathAccessDenied;
        }
    }
};

fn getParamsObject(frame: std.json.Value) !std.json.Value {
    if (frame != .object) return error.InvalidParamsFrame;
    const params_value = frame.object.get("params") orelse return error.InvalidParamsFrame;
    if (params_value != .object) return error.InvalidParamsFrame;
    return params_value;
}

fn getRequiredString(
    params: std.json.Value,
    key: []const u8,
    fallback_key: ?[]const u8,
    err_tag: anyerror,
) ![]const u8 {
    if (params.object.get(key)) |value| {
        if (value == .string and std.mem.trim(u8, value.string, " \t\r\n").len > 0) {
            return value.string;
        }
    }
    if (fallback_key) |fallback| {
        if (params.object.get(fallback)) |value| {
            if (value == .string and std.mem.trim(u8, value.string, " \t\r\n").len > 0) {
                return value.string;
            }
        }
    }
    return err_tag;
}

fn getOptionalString(
    params: std.json.Value,
    key: []const u8,
    default_value: []const u8,
) []const u8 {
    if (params.object.get(key)) |value| {
        if (value == .string and std.mem.trim(u8, value.string, " \t\r\n").len > 0) {
            return value.string;
        }
    }
    return default_value;
}

fn getOptionalU32(
    params: std.json.Value,
    key: []const u8,
    default_value: u32,
) u32 {
    if (params.object.get(key)) |value| switch (value) {
        .integer => |raw| {
            if (raw > 0 and raw <= std.math.maxInt(u32)) return @as(u32, @intCast(raw));
        },
        .float => |raw| {
            if (raw > 0 and raw <= @as(f64, @floatFromInt(std.math.maxInt(u32)))) return @as(u32, @intFromFloat(raw));
        },
        .string => |raw| {
            const trimmed = std.mem.trim(u8, raw, " \t\r\n");
            if (trimmed.len > 0) {
                const parsed = std.fmt.parseInt(u32, trimmed, 10) catch return default_value;
                if (parsed > 0) return parsed;
            }
        },
        else => {},
    };
    return default_value;
}

fn nowUnixMilliseconds(io: std.Io) i64 {
    _ = io;
    return time_util.nowMs();
}

fn hasParentTraversal(path: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    while (it.next()) |segment| {
        if (std.mem.eql(u8, segment, "..")) return true;
    }
    return false;
}

fn resolveAbsolutePath(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
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

fn parseAllowedRoots(
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

fn resolveNearestExistingPath(
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

fn freePathList(allocator: std.mem.Allocator, list: *std.ArrayList([]u8)) void {
    for (list.items) |entry| allocator.free(entry);
    list.deinit(allocator);
}

fn isWithinAnyRoot(path: []const u8, roots: []const []const u8) bool {
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

fn isCommandAllowed(command: []const u8, allowlist_csv: []const u8) bool {
    const trimmed_command = std.mem.trim(u8, command, " \t\r\n");
    if (trimmed_command.len == 0) return false;
    const trimmed_allowlist = std.mem.trim(u8, allowlist_csv, " \t\r\n");
    if (trimmed_allowlist.len == 0) return true;

    var it = std.mem.tokenizeAny(u8, trimmed_allowlist, ",;");
    while (it.next()) |entry_raw| {
        const entry = std.mem.trim(u8, entry_raw, " \t\r\n");
        if (entry.len == 0) continue;
        if (std.ascii.startsWithIgnoreCase(trimmed_command, entry)) return true;
    }
    return false;
}

test "tool runtime file write/read lifecycle with session state" {
    const allocator = std.testing.allocator;
    var runtime = ToolRuntime.init(std.heap.page_allocator, std.testing.io);
    defer runtime.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = std.Io.Threaded.global_single_threaded.io();
    const base_path = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(base_path);
    const test_path = try std.fs.path.join(allocator, &.{ base_path, "runtime-file.txt" });
    defer allocator.free(test_path);

    var write_result = try runtime.fileWrite(allocator, "sess-phase3", test_path, "phase3-data");
    defer write_result.deinit(allocator);
    try std.testing.expect(write_result.ok);
    try std.testing.expectEqual(@as(usize, 0), runtime.queueDepth());

    var read_result = try runtime.fileRead(allocator, "sess-phase3", test_path);
    defer read_result.deinit(allocator);
    try std.testing.expect(read_result.ok);
    try std.testing.expect(std.mem.eql(u8, read_result.content, "phase3-data"));
    try std.testing.expectEqual(@as(usize, 0), runtime.queueDepth());
    try std.testing.expectEqual(@as(usize, 1), runtime.sessionCount());

    const session = runtime.runtime_state.getSession("sess-phase3").?;
    try std.testing.expect(std.mem.indexOf(u8, session.last_message, "file.read:") != null);
}

test "tool runtime exec lifecycle returns output and keeps queue empty" {
    const allocator = std.testing.allocator;
    var runtime = ToolRuntime.init(std.heap.page_allocator, std.testing.io);
    defer runtime.deinit();

    const command = switch (builtin.os.tag) {
        .windows => "echo phase3-exec",
        else => "printf phase3-exec",
    };

    var result = runtime.execRun(allocator, "sess-exec", command, 20_000) catch return error.SkipZigTest;
    defer result.deinit(allocator);
    try std.testing.expect(result.ok);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "phase3-exec") != null);
    try std.testing.expectEqual(@as(usize, 0), runtime.queueDepth());
}

test "tool runtime file sandbox blocks traversal and out-of-root writes" {
    const allocator = std.testing.allocator;
    var runtime = ToolRuntime.init(std.heap.page_allocator, std.testing.io);
    defer runtime.deinit();

    var root_tmp = std.testing.tmpDir(.{});
    defer root_tmp.cleanup();
    var outside_tmp = std.testing.tmpDir(.{});
    defer outside_tmp.cleanup();

    const io = std.Io.Threaded.global_single_threaded.io();
    const root_path = try root_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root_path);
    const outside_path = try outside_tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(outside_path);

    runtime.file_sandbox_enabled = true;
    runtime.file_allowed_roots = root_path;

    const blocked_traversal_path = try std.fs.path.join(allocator, &.{ std.mem.sliceTo(root_path, 0), "..", "escape.txt" });
    defer allocator.free(blocked_traversal_path);
    try std.testing.expectError(error.PathTraversalDetected, runtime.fileWrite(allocator, "sess-sbx", blocked_traversal_path, "x"));

    const blocked_outside_path = try std.fs.path.join(allocator, &.{ std.mem.sliceTo(outside_path, 0), "outside.txt" });
    defer allocator.free(blocked_outside_path);
    try std.testing.expectError(error.PathAccessDenied, runtime.fileWrite(allocator, "sess-sbx", blocked_outside_path, "x"));

    const allowed_path = try std.fs.path.join(allocator, &.{ std.mem.sliceTo(root_path, 0), "allowed.txt" });
    defer allocator.free(allowed_path);
    var write_ok = try runtime.fileWrite(allocator, "sess-sbx", allowed_path, "ok");
    defer write_ok.deinit(allocator);
    try std.testing.expect(write_ok.ok);
}

test "tool runtime exec policy denies non-allowlisted commands" {
    const allocator = std.testing.allocator;
    var runtime = ToolRuntime.init(std.heap.page_allocator, std.testing.io);
    defer runtime.deinit();

    runtime.exec_enabled = true;
    runtime.exec_allowlist = if (builtin.os.tag == .windows) "echo" else "printf";

    const allowed = if (builtin.os.tag == .windows) "echo exec-allow" else "printf exec-allow";
    var ok_result = try runtime.execRun(allocator, "sess-exec-policy", allowed, 20_000);
    defer ok_result.deinit(allocator);
    try std.testing.expect(ok_result.ok);

    const blocked = if (builtin.os.tag == .windows) "dir" else "uname -a";
    try std.testing.expectError(error.CommandDenied, runtime.execRun(allocator, "sess-exec-policy", blocked, 20_000));
}
