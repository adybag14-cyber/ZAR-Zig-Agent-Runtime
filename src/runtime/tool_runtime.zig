const builtin = @import("builtin");
const std = @import("std");
const config = @import("../config.zig");
const pal = @import("../pal/mod.zig");
const envelope = @import("../protocol/envelope.zig");
const state = @import("state.zig");
const time_util = @import("../util/time.zig");

pub const InputError = error{
    InvalidParamsFrame,
    MissingCommand,
    MissingPath,
    MissingContent,
    MissingSessionId,
    CommandDenied,
    PathAccessDenied,
    PathTraversalDetected,
    PathSymlinkDisallowed,
    SessionNotFound,
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

    pub fn snapshotTextAlloc(self: *const ToolRuntime, allocator: std.mem.Allocator) ![]u8 {
        const runtime_snapshot = self.snapshot();
        return std.fmt.allocPrint(
            allocator,
            "state_path={s}\npersisted={d}\nsessions={d}\nqueue_depth={d}\nleased_jobs={d}\nrecovery_backlog={d}\n",
            .{
                runtime_snapshot.statePath,
                @intFromBool(runtime_snapshot.persisted),
                runtime_snapshot.sessions,
                runtime_snapshot.queueDepth,
                runtime_snapshot.leasedJobs,
                runtime_snapshot.recoveryBacklog,
            },
        );
    }

    pub fn sessionListTextAlloc(self: *const ToolRuntime, allocator: std.mem.Allocator) ![]u8 {
        var session_ids: std.ArrayList([]const u8) = .empty;
        defer session_ids.deinit(allocator);

        var iterator = self.runtime_state.sessions.iterator();
        while (iterator.next()) |entry| {
            try session_ids.append(allocator, entry.key_ptr.*);
        }

        std.mem.sort([]const u8, session_ids.items, {}, struct {
            fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
                return std.mem.lessThan(u8, lhs, rhs);
            }
        }.lessThan);

        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(allocator);
        for (session_ids.items) |session_id| {
            try output.appendSlice(allocator, session_id);
            try output.append(allocator, '\n');
        }
        return output.toOwnedSlice(allocator);
    }

    pub fn sessionInfoTextAlloc(
        self: *const ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
    ) ![]u8 {
        const session = self.runtime_state.getSession(session_id) orelse return error.SessionNotFound;
        return std.fmt.allocPrint(
            allocator,
            "id={s}\ncreated_unix_ms={d}\nupdated_unix_ms={d}\nlast_message={s}\n",
            .{
                session.id,
                session.created_unix_ms,
                session.updated_unix_ms,
                session.last_message,
            },
        );
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

    pub fn handleRpcFrameAlloc(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) ![]u8 {
        var request = envelope.parseRequest(allocator, frame_json) catch |err| {
            return envelope.encodeError(allocator, "0", .{
                .code = rpcErrorCode(err),
                .message = @errorName(err),
            });
        };
        defer request.deinit(allocator);

        if (std.mem.eql(u8, request.method, "exec.run")) {
            var exec_result = self.execRunFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer exec_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, .{
                .ok = exec_result.ok,
                .status = exec_result.status,
                .state = exec_result.state,
                .jobId = exec_result.jobId,
                .sessionId = exec_result.sessionId,
                .command = exec_result.command,
                .exitCode = exec_result.exitCode,
                .stdout = exec_result.stdout,
                .stderr = exec_result.stderr,
            });
        }

        if (std.mem.eql(u8, request.method, "file.read")) {
            var read_result = self.fileReadFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer read_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, .{
                .ok = read_result.ok,
                .status = read_result.status,
                .state = read_result.state,
                .jobId = read_result.jobId,
                .sessionId = read_result.sessionId,
                .path = read_result.path,
                .bytes = read_result.bytes,
                .content = read_result.content,
            });
        }

        if (std.mem.eql(u8, request.method, "file.write")) {
            var write_result = self.fileWriteFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer write_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, .{
                .ok = write_result.ok,
                .status = write_result.status,
                .state = write_result.state,
                .jobId = write_result.jobId,
                .sessionId = write_result.sessionId,
                .path = write_result.path,
                .bytes = write_result.bytes,
                .createdDirs = write_result.createdDirs,
            });
        }

        if (std.mem.eql(u8, request.method, "runtime.snapshot")) {
            const runtime_snapshot = self.snapshot();
            return envelope.encodeResult(allocator, request.id, .{
                .statePath = runtime_snapshot.statePath,
                .persisted = runtime_snapshot.persisted,
                .sessions = runtime_snapshot.sessions,
                .queueDepth = runtime_snapshot.queueDepth,
                .leasedJobs = runtime_snapshot.leasedJobs,
                .recoveryBacklog = runtime_snapshot.recoveryBacklog,
            });
        }

        if (std.mem.eql(u8, request.method, "runtime.session.list")) {
            var sessions: std.ArrayList(state.SessionSnapshot) = .empty;
            defer sessions.deinit(allocator);

            var iterator = self.runtime_state.sessions.iterator();
            while (iterator.next()) |entry| {
                try sessions.append(allocator, .{
                    .id = entry.key_ptr.*,
                    .created_unix_ms = entry.value_ptr.created_unix_ms,
                    .updated_unix_ms = entry.value_ptr.updated_unix_ms,
                    .last_message = entry.value_ptr.last_message,
                });
            }

            std.mem.sort(state.SessionSnapshot, sessions.items, {}, struct {
                fn lessThan(_: void, lhs: state.SessionSnapshot, rhs: state.SessionSnapshot) bool {
                    return std.mem.lessThan(u8, lhs.id, rhs.id);
                }
            }.lessThan);

            return envelope.encodeResult(allocator, request.id, .{
                .sessions = sessions.items,
            });
        }

        if (std.mem.eql(u8, request.method, "runtime.session.get")) {
            const session_id = parseSessionIdFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer allocator.free(session_id);
            const session = self.runtime_state.getSession(session_id) orelse {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(error.SessionNotFound),
                    .message = @errorName(error.SessionNotFound),
                });
            };
            return envelope.encodeResult(allocator, request.id, .{
                .id = session.id,
                .createdUnixMs = session.created_unix_ms,
                .updatedUnixMs = session.updated_unix_ms,
                .lastMessage = session.last_message,
            });
        }

        return envelope.encodeError(allocator, request.id, .{
            .code = -32601,
            .message = "MethodNotFound",
        });
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

fn parseSessionIdFromFrame(allocator: std.mem.Allocator, frame_json: []const u8) ![]const u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
    defer parsed.deinit();

    const params = try getParamsObject(parsed.value);
    const session_id = try getRequiredString(params, "sessionId", "session", error.MissingSessionId);
    return allocator.dupe(u8, session_id);
}

fn rpcErrorCode(err: anyerror) i64 {
    return switch (err) {
        error.InvalidFrame,
        error.InvalidMethod,
        error.InvalidId,
        => -32600,
        error.InvalidParamsFrame,
        error.MissingCommand,
        error.MissingPath,
        error.MissingContent,
        error.MissingSessionId,
        => -32602,
        error.CommandDenied => -32010,
        error.PathAccessDenied,
        error.PathTraversalDetected,
        error.PathSymlinkDisallowed,
        => -32011,
        error.SessionNotFound => -32044,
        else => -32000,
    };
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

test "tool runtime snapshot and session queries expose deterministic text" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = testingHostedIo();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    const test_path = try std.fs.path.join(allocator, &.{ root, "runtime-query.txt" });
    defer allocator.free(test_path);

    var runtime = ToolRuntime.init(std.heap.page_allocator, testingToolIo());
    defer runtime.deinit();
    try runtime.configureStatePersistence(root);

    var write_result = try runtime.fileWrite(allocator, "sess-query", test_path, "query-data");
    defer write_result.deinit(allocator);
    try std.testing.expect(write_result.ok);

    const snapshot_text = try runtime.snapshotTextAlloc(allocator);
    defer allocator.free(snapshot_text);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_text, "state_path=") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_text, "sessions=1") != null);

    const sessions_text = try runtime.sessionListTextAlloc(allocator);
    defer allocator.free(sessions_text);
    try std.testing.expectEqualStrings("sess-query\n", sessions_text);

    const session_text = try runtime.sessionInfoTextAlloc(allocator, "sess-query");
    defer allocator.free(session_text);
    try std.testing.expect(std.mem.indexOf(u8, session_text, "id=sess-query") != null);
    try std.testing.expect(std.mem.indexOf(u8, session_text, "last_message=file.write:") != null);
}

test "tool runtime RPC frame bridge serves file exec and session methods" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = testingHostedIo();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);
    const test_path = try std.fs.path.join(allocator, &.{ root, "runtime-rpc.txt" });
    defer allocator.free(test_path);
    const json_test_path = try std.mem.replaceOwned(u8, allocator, test_path, "\\", "\\\\");
    defer allocator.free(json_test_path);

    var runtime = ToolRuntime.init(std.heap.page_allocator, testingToolIo());
    defer runtime.deinit();
    try runtime.configureStatePersistence(root);
    runtime.exec_enabled = true;
    runtime.exec_allowlist = if (builtin.os.tag == .windows) "echo" else "printf";

    const write_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-write\",\"method\":\"file.write\",\"params\":{{\"sessionId\":\"sess-rpc\",\"path\":\"{s}\",\"content\":\"rpc-data\"}}}}",
        .{json_test_path},
    );
    defer allocator.free(write_frame);
    const write_response = try runtime.handleRpcFrameAlloc(allocator, write_frame);
    defer allocator.free(write_response);
    try std.testing.expect(std.mem.indexOf(u8, write_response, "\"id\":\"rt-write\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, write_response, "\"bytes\":8") != null);

    const read_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-read\",\"method\":\"file.read\",\"params\":{{\"sessionId\":\"sess-rpc\",\"path\":\"{s}\"}}}}",
        .{json_test_path},
    );
    defer allocator.free(read_frame);
    const read_response = try runtime.handleRpcFrameAlloc(allocator, read_frame);
    defer allocator.free(read_response);
    try std.testing.expect(std.mem.indexOf(u8, read_response, "\"content\":\"rpc-data\"") != null);

    const exec_command = if (builtin.os.tag == .windows) "echo rpc-bridge" else "printf rpc-bridge";
    const exec_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-exec\",\"method\":\"exec.run\",\"params\":{{\"sessionId\":\"sess-rpc\",\"command\":\"{s}\",\"timeoutMs\":1000}}}}",
        .{exec_command},
    );
    defer allocator.free(exec_frame);
    const exec_response = runtime.handleRpcFrameAlloc(allocator, exec_frame) catch return error.SkipZigTest;
    defer allocator.free(exec_response);
    try std.testing.expect(std.mem.indexOf(u8, exec_response, "\"id\":\"rt-exec\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, exec_response, "rpc-bridge") != null);

    const snapshot_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-snapshot\",\"method\":\"runtime.snapshot\",\"params\":{}}",
    );
    defer allocator.free(snapshot_response);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_response, "\"id\":\"rt-snapshot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_response, "\"sessions\":1") != null);

    const list_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-list\",\"method\":\"runtime.session.list\",\"params\":{}}",
    );
    defer allocator.free(list_response);
    try std.testing.expect(std.mem.indexOf(u8, list_response, "\"id\":\"sess-rpc\"") != null);

    const session_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-session\",\"method\":\"runtime.session.get\",\"params\":{\"sessionId\":\"sess-rpc\"}}",
    );
    defer allocator.free(session_response);
    try std.testing.expect(std.mem.indexOf(u8, session_response, "\"id\":\"rt-session\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, session_response, "\"lastMessage\"") != null);
}
