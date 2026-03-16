const builtin = @import("builtin");
const std = @import("std");
const config = @import("../config.zig");
const pal = @import("../pal/mod.zig");
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

pub const Snapshot = struct {
    statePath: []const u8,
    persisted: bool,
    sessions: usize,
    queueDepth: usize,
    leasedJobs: usize,
    recoveryBacklog: usize,
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

    pub fn snapshot(self: *const ToolRuntime) Snapshot {
        const runtime_snapshot = self.runtime_state.snapshot();
        return .{
            .statePath = runtime_snapshot.statePath,
            .persisted = runtime_snapshot.persisted,
            .sessions = runtime_snapshot.sessions,
            .queueDepth = runtime_snapshot.pendingJobs,
            .leasedJobs = runtime_snapshot.leasedJobs,
            .recoveryBacklog = runtime_snapshot.recoveryBacklog,
        };
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

    pub fn configureStatePersistence(
        self: *ToolRuntime,
        state_root: []const u8,
    ) !void {
        try self.runtime_state.configurePersistence(state_root);
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
        if (!self.exec_enabled or !pal.proc.isCommandAllowed(command, self.exec_allowlist)) {
            return error.CommandDenied;
        }

        const job_id = try self.runtime_state.enqueueJob(.exec, command);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        const argv = switch (builtin.os.tag) {
            .windows => [_][]const u8{ "C:\\Windows\\System32\\cmd.exe", "/C", command },
            .freestanding => [_][]const u8{command},
            else => [_][]const u8{ "/bin/sh", "-lc", command },
        };
        var run_result = try pal.proc.runCapture(
            self.allocator,
            self.io,
            &argv,
            timeout_ms,
            max_exec_output_bytes,
            max_exec_output_bytes,
        );
        defer run_result.deinit(self.allocator);

        const exit_code: i32 = pal.proc.termExitCode(run_result.term);

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

        const content = try pal.fs.readFileAlloc(self.io, allocator, effective_path, max_file_read_bytes);
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
                try pal.fs.createDirPath(self.io, dir_name);
                created_dirs = true;
            }
        }

        try self.verifyWritePathAfterMkdir(allocator, effective_path);

        try pal.fs.writeFile(self.io, effective_path, content);

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

        if (pal.sandbox.hasParentTraversal(path)) {
            return error.PathTraversalDetected;
        }

        if (builtin.os.tag == .freestanding) {
            return self.resolveFreestandingSandboxedPath(allocator, path, mode);
        }

        const absolute_path = try pal.sandbox.resolveAbsolutePath(self.io, allocator, path);
        errdefer allocator.free(absolute_path);

        var roots = try pal.sandbox.parseAllowedRoots(self.io, allocator, self.file_allowed_roots);
        defer pal.sandbox.freePathList(allocator, &roots);
        if (roots.items.len == 0) {
            return error.PathAccessDenied;
        }

        if (!pal.sandbox.isWithinAnyRoot(absolute_path, roots.items)) {
            return error.PathAccessDenied;
        }

        switch (mode) {
            .read => {
                const target_real_z = std.Io.Dir.realPathFileAbsoluteAlloc(self.io, absolute_path, allocator) catch return error.PathAccessDenied;
                defer allocator.free(target_real_z);
                const target_real = std.mem.sliceTo(target_real_z, 0);
                if (!pal.sandbox.isWithinAnyRoot(target_real, roots.items)) {
                    return error.PathAccessDenied;
                }
                const stat = pal.fs.statNoFollow(self.io, absolute_path) catch return error.PathAccessDenied;
                if (stat.kind == .sym_link) return error.PathSymlinkDisallowed;
            },
            .write => {
                const stat = pal.fs.statNoFollow(self.io, absolute_path) catch |err| switch (err) {
                    error.FileNotFound => null,
                    else => return error.PathAccessDenied,
                };
                if (stat) |entry| {
                    if (entry.kind == .sym_link) return error.PathSymlinkDisallowed;
                }

                const parent = std.fs.path.dirname(absolute_path) orelse return error.PathAccessDenied;
                const parent_real = try pal.sandbox.resolveNearestExistingPath(self.io, allocator, parent);
                defer allocator.free(parent_real);
                if (!pal.sandbox.isWithinAnyRoot(parent_real, roots.items)) {
                    return error.PathAccessDenied;
                }
            },
        }

        return absolute_path;
    }

    fn resolveFreestandingSandboxedPath(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        path: []const u8,
        mode: FileMode,
    ) ![]u8 {
        const normalized_path = try normalizeFreestandingPath(allocator, path);
        errdefer allocator.free(normalized_path);

        var roots = try parseFreestandingAllowedRoots(allocator, self.file_allowed_roots);
        defer pal.sandbox.freePathList(allocator, &roots);
        if (roots.items.len == 0) {
            return error.PathAccessDenied;
        }

        if (!pal.sandbox.isWithinAnyRoot(normalized_path, roots.items)) {
            return error.PathAccessDenied;
        }

        switch (mode) {
            .read => {
                const stat = pal.fs.statNoFollow(self.io, normalized_path) catch return error.PathAccessDenied;
                if (stat.kind == .sym_link) return error.PathSymlinkDisallowed;
            },
            .write => {
                const stat = pal.fs.statNoFollow(self.io, normalized_path) catch |err| switch (err) {
                    error.FileNotFound => null,
                    else => return error.PathAccessDenied,
                };
                if (stat) |entry| {
                    if (entry.kind == .sym_link) return error.PathSymlinkDisallowed;
                }

                const parent = freestandingParentPath(normalized_path) orelse return error.PathAccessDenied;
                if (!pal.sandbox.isWithinAnyRoot(parent, roots.items)) {
                    return error.PathAccessDenied;
                }
            },
        }

        return normalized_path;
    }

    fn verifyWritePathAfterMkdir(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        path: []const u8,
    ) !void {
        if (!self.file_sandbox_enabled) return;

        if (builtin.os.tag == .freestanding) {
            var roots = try parseFreestandingAllowedRoots(allocator, self.file_allowed_roots);
            defer pal.sandbox.freePathList(allocator, &roots);
            if (roots.items.len == 0) return error.PathAccessDenied;

            const parent = freestandingParentPath(path) orelse return error.PathAccessDenied;
            if (!pal.sandbox.isWithinAnyRoot(parent, roots.items)) {
                return error.PathAccessDenied;
            }
            return;
        }

        var roots = try pal.sandbox.parseAllowedRoots(self.io, allocator, self.file_allowed_roots);
        defer pal.sandbox.freePathList(allocator, &roots);
        if (roots.items.len == 0) return error.PathAccessDenied;

        const parent = std.fs.path.dirname(path) orelse return error.PathAccessDenied;
        const parent_real_z = std.Io.Dir.realPathFileAbsoluteAlloc(self.io, parent, allocator) catch return error.PathAccessDenied;
        defer allocator.free(parent_real_z);
        const parent_real = std.mem.sliceTo(parent_real_z, 0);
        if (!pal.sandbox.isWithinAnyRoot(parent_real, roots.items)) {
            return error.PathAccessDenied;
        }
    }
};

fn parseFreestandingAllowedRoots(
    allocator: std.mem.Allocator,
    csv: []const u8,
) !std.ArrayList([]u8) {
    var roots: std.ArrayList([]u8) = .empty;
    errdefer pal.sandbox.freePathList(allocator, &roots);

    const trimmed = std.mem.trim(u8, csv, " \t\r\n");
    if (trimmed.len == 0) {
        try roots.append(allocator, try allocator.dupe(u8, "/"));
        return roots;
    }

    var it = std.mem.tokenizeAny(u8, trimmed, ",;");
    while (it.next()) |entry_raw| {
        const entry = std.mem.trim(u8, entry_raw, " \t\r\n");
        if (entry.len == 0) continue;
        const normalized = normalizeFreestandingPath(allocator, entry) catch continue;
        errdefer allocator.free(normalized);
        try roots.append(allocator, normalized);
    }

    return roots;
}

fn normalizeFreestandingPath(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]u8 {
    const trimmed = std.mem.trim(u8, path, " \t\r\n");
    if (trimmed.len == 0) return error.PathAccessDenied;
    if (pal.sandbox.hasParentTraversal(trimmed)) return error.PathTraversalDetected;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.append(allocator, '/');
    var appended_segment = false;
    var it = std.mem.tokenizeAny(u8, trimmed, "/\\");
    while (it.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".")) continue;
        if (std.mem.eql(u8, segment, "..")) return error.PathTraversalDetected;
        if (appended_segment) try out.append(allocator, '/');
        try out.appendSlice(allocator, segment);
        appended_segment = true;
    }

    return out.toOwnedSlice(allocator);
}

fn freestandingParentPath(path: []const u8) ?[]const u8 {
    if (path.len == 0 or !std.mem.startsWith(u8, path, "/")) return null;
    if (std.mem.eql(u8, path, "/")) return "/";

    var idx = path.len;
    while (idx > 1) : (idx -= 1) {
        if (path[idx - 1] == '/') {
            return if (idx == 1) "/" else path[0 .. idx - 1];
        }
    }

    return "/";
}

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

fn testingToolIo() std.Io {
    if (builtin.os.tag == .freestanding) return undefined;
    return std.testing.io;
}

fn testingHostedIo() std.Io {
    if (builtin.os.tag == .freestanding) return undefined;
    return std.Io.Threaded.global_single_threaded.io();
}

test "tool runtime file write/read lifecycle with session state" {
    const allocator = std.testing.allocator;
    var runtime = ToolRuntime.init(std.heap.page_allocator, testingToolIo());
    defer runtime.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = testingHostedIo();
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
    var runtime = ToolRuntime.init(std.heap.page_allocator, testingToolIo());
    defer runtime.deinit();

    const command = switch (builtin.os.tag) {
        .windows => "echo phase3-exec",
        .freestanding => "echo phase3-exec",
        else => "printf phase3-exec",
    };

    var result = runtime.execRun(allocator, "sess-exec", command, 20_000) catch return error.SkipZigTest;
    defer result.deinit(allocator);
    try std.testing.expect(result.ok);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "phase3-exec") != null);
    try std.testing.expectEqual(@as(usize, 0), runtime.queueDepth());
}

test "tool runtime persistence roundtrip restores freestanding-safe state posture" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = std.Io.Threaded.global_single_threaded.io();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    const test_path = try std.fs.path.join(allocator, &.{ root, "runtime-roundtrip.txt" });
    defer allocator.free(test_path);

    {
        var runtime = ToolRuntime.init(std.heap.page_allocator, testingToolIo());
        defer runtime.deinit();
        try runtime.configureStatePersistence(root);

        var write_result = try runtime.fileWrite(allocator, "sess-roundtrip", test_path, "roundtrip-data");
        defer write_result.deinit(allocator);
        try std.testing.expect(write_result.ok);

        const command = switch (builtin.os.tag) {
            .windows => "echo phase3-roundtrip",
            .freestanding => "echo phase3-roundtrip",
            else => "printf phase3-roundtrip",
        };
        var exec_result = runtime.execRun(allocator, "sess-roundtrip", command, 20_000) catch return error.SkipZigTest;
        defer exec_result.deinit(allocator);
        try std.testing.expect(exec_result.ok);
    }

    {
        var restored = ToolRuntime.init(std.heap.page_allocator, testingToolIo());
        defer restored.deinit();
        try restored.configureStatePersistence(root);

        const snapshot = restored.snapshot();
        try std.testing.expect(snapshot.persisted);
        try std.testing.expect(std.mem.endsWith(u8, snapshot.statePath, "runtime-state.json"));
        try std.testing.expectEqual(@as(usize, 1), snapshot.sessions);
        try std.testing.expectEqual(@as(usize, 0), snapshot.queueDepth);

        const session = restored.runtime_state.getSession("sess-roundtrip").?;
        try std.testing.expect(std.mem.indexOf(u8, session.last_message, "phase3-roundtrip") != null);
    }
}

test "tool runtime file sandbox blocks traversal and out-of-root writes" {
    const allocator = std.testing.allocator;
    var runtime = ToolRuntime.init(std.heap.page_allocator, testingToolIo());
    defer runtime.deinit();

    var root_tmp = std.testing.tmpDir(.{});
    defer root_tmp.cleanup();
    var outside_tmp = std.testing.tmpDir(.{});
    defer outside_tmp.cleanup();

    const io = testingHostedIo();
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
    var runtime = ToolRuntime.init(std.heap.page_allocator, testingToolIo());
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

test "tool runtime freestanding path normalization keeps logical roots bounded" {
    const allocator = std.testing.allocator;

    const normalized_relative = try normalizeFreestandingPath(allocator, "runtime\\state\\session.json");
    defer allocator.free(normalized_relative);
    try std.testing.expectEqualStrings("/runtime/state/session.json", normalized_relative);

    const normalized_absolute = try normalizeFreestandingPath(allocator, "/runtime/state/./session.json");
    defer allocator.free(normalized_absolute);
    try std.testing.expectEqualStrings("/runtime/state/session.json", normalized_absolute);

    try std.testing.expectEqualStrings("/runtime/state", freestandingParentPath("/runtime/state/session.json").?);
    try std.testing.expectEqualStrings("/", freestandingParentPath("/runtime").?);
    try std.testing.expectError(error.PathTraversalDetected, normalizeFreestandingPath(allocator, "/runtime/../escape"));
}

test "tool runtime snapshot exposes queue and persistence posture" {
    const allocator = std.testing.allocator;
    var runtime = ToolRuntime.init(std.heap.page_allocator, testingToolIo());
    defer runtime.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = testingHostedIo();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);

    try runtime.configureStatePersistence(root);
    _ = try runtime.runtime_state.enqueueJob(.exec, "{\"cmd\":\"echo hi\"}");
    _ = try runtime.runtime_state.enqueueJob(.file_read, "{\"path\":\"README.md\"}");
    const leased = runtime.runtime_state.dequeueJob().?;
    defer runtime.runtime_state.releaseJob(leased);

    const snapshot = runtime.snapshot();
    try std.testing.expect(snapshot.persisted);
    try std.testing.expect(std.mem.endsWith(u8, snapshot.statePath, "runtime-state.json"));
    try std.testing.expectEqual(@as(usize, 1), snapshot.queueDepth);
    try std.testing.expectEqual(@as(usize, 1), snapshot.leasedJobs);
    try std.testing.expectEqual(@as(usize, 2), snapshot.recoveryBacklog);
}
