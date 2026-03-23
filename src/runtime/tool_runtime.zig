const builtin = @import("builtin");
const std = @import("std");
const config = @import("../config.zig");
const pal = @import("../pal/mod.zig");
const envelope = @import("../protocol/envelope.zig");
const state = @import("state.zig");
const process_registry = @import("process_registry.zig");
const web_tools = @import("web_tools.zig");
const time_util = @import("../util/time.zig");

pub const InputError = error{
    InvalidParamsFrame,
    MissingCommand,
    MissingPath,
    MissingContent,
    MissingQuery,
    MissingOldText,
    MissingSessionId,
    MissingProcessId,
    MissingUrl,
    MissingLanguage,
    MissingCode,
    UnsupportedLanguage,
    CommandDenied,
    PathAccessDenied,
    PathTraversalDetected,
    PathSymlinkDisallowed,
    SessionNotFound,
    ProcessNotFound,
    ProcessManagementUnsupported,
    WebFetchUnsupported,
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

pub const ExecuteCodeResult = struct {
    ok: bool,
    status: u16,
    state: []const u8,
    jobId: u64,
    sessionId: []const u8,
    language: []const u8,
    runtimePath: []const u8,
    scriptPath: []const u8,
    cwd: []const u8,
    command: []const u8,
    exitCode: i32,
    stdout: []const u8,
    stderr: []const u8,
    keptFiles: bool,

    pub fn deinit(self: *ExecuteCodeResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.language);
        allocator.free(self.runtimePath);
        allocator.free(self.scriptPath);
        allocator.free(self.cwd);
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

pub const SearchMatch = struct {
    path: []const u8,
    line: usize,
    column: usize,
    preview: []const u8,

    pub fn deinit(self: *SearchMatch, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.preview);
    }
};

pub const FileSearchResult = struct {
    ok: bool,
    status: u16,
    state: []const u8,
    jobId: u64,
    sessionId: []const u8,
    path: []const u8,
    query: []const u8,
    filesScanned: usize,
    count: usize,
    items: []SearchMatch,

    pub fn deinit(self: *FileSearchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.path);
        allocator.free(self.query);
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const FilePatchResult = struct {
    ok: bool,
    status: u16,
    state: []const u8,
    jobId: u64,
    sessionId: []const u8,
    path: []const u8,
    oldText: []const u8,
    newText: []const u8,
    replacements: usize,
    bytes: usize,
    applied: bool,

    pub fn deinit(self: *FilePatchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.path);
        allocator.free(self.oldText);
        allocator.free(self.newText);
    }
};

pub const WebSearchItem = web_tools.SearchItem;
pub const WebSearchData = web_tools.SearchData;
pub const WebExtractPage = web_tools.ExtractPage;

pub const WebSearchResult = struct {
    ok: bool,
    status: u16,
    state: []const u8,
    jobId: u64,
    sessionId: []const u8,
    query: []const u8,
    provider: []const u8,
    requestUrl: []const u8,
    latencyMs: i64,
    count: usize,
    data: WebSearchData,

    pub fn deinit(self: *WebSearchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.query);
        allocator.free(self.provider);
        allocator.free(self.requestUrl);
        for (self.data.web) |*item| item.deinit(allocator);
        allocator.free(self.data.web);
    }
};

pub const WebExtractResult = struct {
    ok: bool,
    status: u16,
    state: []const u8,
    jobId: u64,
    sessionId: []const u8,
    count: usize,
    results: []WebExtractPage,

    pub fn deinit(self: *WebExtractResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        for (self.results) |*item| item.deinit(allocator);
        allocator.free(self.results);
    }
};

pub const ProcessSummary = struct {
    processId: []const u8,
    sessionId: []const u8,
    command: []const u8,
    cwd: []const u8,
    processState: []const u8,
    pid: i64,
    running: bool,
    startedAtMs: i64,
    updatedAtMs: i64,
    finishedAtMs: i64,
    exitCode: i32,
    hasExitCode: bool,
    stdoutBytes: usize,
    stderrBytes: usize,

    pub fn deinit(self: *ProcessSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.processId);
        allocator.free(self.sessionId);
        allocator.free(self.command);
        allocator.free(self.cwd);
        allocator.free(self.processState);
    }
};

pub const ProcessStartResult = struct {
    ok: bool,
    status: u16,
    state: []const u8,
    jobId: u64,
    sessionId: []const u8,
    processId: []const u8,
    command: []const u8,
    cwd: []const u8,
    pid: i64,
    startedAtMs: i64,
    stdoutPath: []const u8,
    stderrPath: []const u8,

    pub fn deinit(self: *ProcessStartResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.processId);
        allocator.free(self.command);
        allocator.free(self.cwd);
        allocator.free(self.stdoutPath);
        allocator.free(self.stderrPath);
    }
};

pub const ProcessListResult = struct {
    ok: bool,
    status: u16,
    state: []const u8,
    jobId: u64,
    sessionId: []const u8,
    count: usize,
    items: []ProcessSummary,

    pub fn deinit(self: *ProcessListResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const ProcessStatusResult = struct {
    ok: bool,
    status: u16,
    state: []const u8,
    jobId: u64,
    sessionId: []const u8,
    processId: []const u8,
    command: []const u8,
    cwd: []const u8,
    processState: []const u8,
    pid: i64,
    running: bool,
    startedAtMs: i64,
    updatedAtMs: i64,
    finishedAtMs: i64,
    exitCode: i32,
    hasExitCode: bool,
    stdoutBytes: usize,
    stderrBytes: usize,
    stdout: []const u8,
    stderr: []const u8,
    timedOut: bool,
    signal: []const u8,
    requested: bool,

    pub fn deinit(self: *ProcessStatusResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.processId);
        allocator.free(self.command);
        allocator.free(self.cwd);
        allocator.free(self.processState);
        allocator.free(self.stdout);
        allocator.free(self.stderr);
        allocator.free(self.signal);
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
    process_registry: process_registry.ProcessRegistry,
    file_sandbox_enabled: bool,
    file_allowed_roots: []const u8,
    exec_enabled: bool,
    exec_allowlist: []const u8,

    const default_session_id = "session-local";
    const default_exec_timeout_ms: u32 = 20_000;
    const default_execute_code_timeout_ms: u32 = 120_000;
    const default_process_wait_timeout_ms: u32 = 30_000;
    const max_exec_output_bytes: usize = 1024 * 1024;
    const max_file_read_bytes: usize = 1024 * 1024;
    const max_process_log_bytes: usize = 256 * 1024;

    pub fn init(allocator: std.mem.Allocator, io: std.Io) ToolRuntime {
        return .{
            .allocator = allocator,
            .io = io,
            .runtime_state = state.RuntimeState.init(allocator),
            .process_registry = process_registry.ProcessRegistry.init(allocator, io),
            .file_sandbox_enabled = false,
            .file_allowed_roots = "",
            .exec_enabled = true,
            .exec_allowlist = "",
        };
    }

    pub fn deinit(self: *ToolRuntime) void {
        self.process_registry.deinit();
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

    pub fn executeCodeFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !ExecuteCodeResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const language = try getRequiredString(params, "language", "lang", error.MissingLanguage);
        const code = try getRequiredString(params, "code", "script", error.MissingCode);
        const session_id = getOptionalString(params, "sessionId", default_session_id);
        const timeout_ms = getOptionalU32(params, "timeoutMs", default_execute_code_timeout_ms);
        const cwd = getOptionalStringAliases(params, &.{ "cwd", "workingDirectory", "workdir" }, "");
        const runtime_path = getOptionalStringAliases(
            params,
            &.{ "runtimePath", "runtime", "binary", "interpreter", "nodePath", "pythonPath", "zigPath" },
            "",
        );
        const keep_files = getOptionalBool(params, "keepFiles", false);
        const args = try getOptionalStringListOwned(allocator, params, "args");
        defer freeOwnedStringList(allocator, args);
        return self.executeCode(allocator, session_id, language, code, cwd, runtime_path, timeout_ms, args, keep_files);
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

    pub fn fileSearchFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !FileSearchResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const root_path = getOptionalString(params, "path", getOptionalString(params, "root", "."));
        const query = try getRequiredString(params, "query", "pattern", error.MissingQuery);
        const session_id = getOptionalString(params, "sessionId", default_session_id);
        const max_results = blk: {
            const explicit = getOptionalU32(params, "maxResults", 0);
            if (explicit != 0) break :blk explicit;
            break :blk getOptionalU32(params, "limit", 50);
        };
        return self.fileSearch(allocator, session_id, root_path, query, max_results);
    }

    pub fn filePatchFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !FilePatchResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const path = try getRequiredString(params, "path", null, error.MissingPath);
        const old_text = try getRequiredString(params, "oldText", "search", error.MissingOldText);
        const new_text = getOptionalString(params, "newText", getOptionalString(params, "replace", ""));
        const session_id = getOptionalString(params, "sessionId", default_session_id);
        const replace_all = getOptionalBool(params, "replaceAll", getOptionalBool(params, "replace_all", false));
        return self.filePatch(allocator, session_id, path, old_text, new_text, replace_all);
    }

    pub fn webSearchFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !WebSearchResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const query = try getRequiredString(params, "query", "q", error.MissingQuery);
        const session_id = getOptionalString(params, "sessionId", default_session_id);
        const limit = getOptionalU32(params, "limit", 5);
        const endpoint = getOptionalString(params, "endpoint", "");
        const timeout_ms = getOptionalU32(params, "timeoutMs", web_tools.default_timeout_ms);
        return self.webSearch(allocator, session_id, query, limit, endpoint, timeout_ms);
    }

    pub fn webExtractFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !WebExtractResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const session_id = getOptionalString(params, "sessionId", default_session_id);
        const max_chars = getOptionalU32(params, "maxChars", @as(u32, @intCast(web_tools.default_extract_max_chars)));
        const timeout_ms = getOptionalU32(params, "timeoutMs", web_tools.default_timeout_ms);
        const urls = try getRequiredStringListOwned(allocator, params, "urls", "url", error.MissingUrl);
        defer freeOwnedStringList(allocator, urls);
        return self.webExtract(allocator, session_id, urls, max_chars, timeout_ms);
    }

    pub fn processStartFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !ProcessStartResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const command = try getRequiredString(params, "command", "cmd", error.MissingCommand);
        const session_id = getOptionalString(params, "sessionId", default_session_id);
        const cwd = getOptionalString(params, "cwd", getOptionalString(params, "workdir", ""));
        return self.processStart(allocator, session_id, command, cwd);
    }

    pub fn processListFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !ProcessListResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const session_id = getOptionalString(params, "sessionId", "");
        return self.processList(allocator, session_id);
    }

    pub fn processPollFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !ProcessStatusResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const process_id = try getRequiredString(params, "processId", "id", error.MissingProcessId);
        return self.processPoll(allocator, process_id);
    }

    pub fn processReadFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !ProcessStatusResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const process_id = try getRequiredString(params, "processId", "id", error.MissingProcessId);
        return self.processRead(allocator, process_id);
    }

    pub fn processWaitFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !ProcessStatusResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const process_id = try getRequiredString(params, "processId", "id", error.MissingProcessId);
        const timeout_ms = getOptionalU32(params, "timeoutMs", getOptionalU32(params, "timeout", default_process_wait_timeout_ms));
        return self.processWait(allocator, process_id, timeout_ms);
    }

    pub fn processKillFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !ProcessStatusResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const process_id = try getRequiredString(params, "processId", "id", error.MissingProcessId);
        return self.processKill(allocator, process_id);
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

        if (std.mem.eql(u8, request.method, "execute_code")) {
            var execute_code_result = self.executeCodeFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer execute_code_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, execute_code_result);
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

        if (std.mem.eql(u8, request.method, "file.search")) {
            var search_result = self.fileSearchFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer search_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, .{
                .ok = search_result.ok,
                .status = search_result.status,
                .state = search_result.state,
                .jobId = search_result.jobId,
                .sessionId = search_result.sessionId,
                .path = search_result.path,
                .query = search_result.query,
                .filesScanned = search_result.filesScanned,
                .count = search_result.count,
                .items = search_result.items,
            });
        }

        if (std.mem.eql(u8, request.method, "file.patch")) {
            var patch_result = self.filePatchFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer patch_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, .{
                .ok = patch_result.ok,
                .status = patch_result.status,
                .state = patch_result.state,
                .jobId = patch_result.jobId,
                .sessionId = patch_result.sessionId,
                .path = patch_result.path,
                .oldText = patch_result.oldText,
                .newText = patch_result.newText,
                .replacements = patch_result.replacements,
                .bytes = patch_result.bytes,
                .applied = patch_result.applied,
            });
        }

        if (std.mem.eql(u8, request.method, "web.search")) {
            var search_result = self.webSearchFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer search_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, search_result);
        }

        if (std.mem.eql(u8, request.method, "web.extract")) {
            var extract_result = self.webExtractFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer extract_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, extract_result);
        }

        if (std.mem.eql(u8, request.method, "process.start")) {
            var start_result = self.processStartFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer start_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, .{
                .ok = start_result.ok,
                .status = start_result.status,
                .state = start_result.state,
                .jobId = start_result.jobId,
                .sessionId = start_result.sessionId,
                .processId = start_result.processId,
                .command = start_result.command,
                .cwd = start_result.cwd,
                .pid = start_result.pid,
                .startedAtMs = start_result.startedAtMs,
                .stdoutPath = start_result.stdoutPath,
                .stderrPath = start_result.stderrPath,
            });
        }

        if (std.mem.eql(u8, request.method, "process.list")) {
            var list_result = self.processListFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer list_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, .{
                .ok = list_result.ok,
                .status = list_result.status,
                .state = list_result.state,
                .jobId = list_result.jobId,
                .sessionId = list_result.sessionId,
                .count = list_result.count,
                .items = list_result.items,
            });
        }

        if (std.mem.eql(u8, request.method, "process.poll")) {
            var poll_result = self.processPollFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer poll_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, .{
                .ok = poll_result.ok,
                .status = poll_result.status,
                .state = poll_result.state,
                .jobId = poll_result.jobId,
                .sessionId = poll_result.sessionId,
                .processId = poll_result.processId,
                .command = poll_result.command,
                .cwd = poll_result.cwd,
                .processState = poll_result.processState,
                .pid = poll_result.pid,
                .running = poll_result.running,
                .startedAtMs = poll_result.startedAtMs,
                .updatedAtMs = poll_result.updatedAtMs,
                .finishedAtMs = poll_result.finishedAtMs,
                .exitCode = poll_result.exitCode,
                .hasExitCode = poll_result.hasExitCode,
                .stdoutBytes = poll_result.stdoutBytes,
                .stderrBytes = poll_result.stderrBytes,
                .stdout = poll_result.stdout,
                .stderr = poll_result.stderr,
                .timedOut = poll_result.timedOut,
                .signal = poll_result.signal,
                .requested = poll_result.requested,
            });
        }

        if (std.mem.eql(u8, request.method, "process.read")) {
            var read_result = self.processReadFromFrame(allocator, frame_json) catch |err| {
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
                .processId = read_result.processId,
                .command = read_result.command,
                .cwd = read_result.cwd,
                .processState = read_result.processState,
                .pid = read_result.pid,
                .running = read_result.running,
                .startedAtMs = read_result.startedAtMs,
                .updatedAtMs = read_result.updatedAtMs,
                .finishedAtMs = read_result.finishedAtMs,
                .exitCode = read_result.exitCode,
                .hasExitCode = read_result.hasExitCode,
                .stdoutBytes = read_result.stdoutBytes,
                .stderrBytes = read_result.stderrBytes,
                .stdout = read_result.stdout,
                .stderr = read_result.stderr,
                .timedOut = read_result.timedOut,
                .signal = read_result.signal,
                .requested = read_result.requested,
            });
        }

        if (std.mem.eql(u8, request.method, "process.wait")) {
            var wait_result = self.processWaitFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer wait_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, .{
                .ok = wait_result.ok,
                .status = wait_result.status,
                .state = wait_result.state,
                .jobId = wait_result.jobId,
                .sessionId = wait_result.sessionId,
                .processId = wait_result.processId,
                .command = wait_result.command,
                .cwd = wait_result.cwd,
                .processState = wait_result.processState,
                .pid = wait_result.pid,
                .running = wait_result.running,
                .startedAtMs = wait_result.startedAtMs,
                .updatedAtMs = wait_result.updatedAtMs,
                .finishedAtMs = wait_result.finishedAtMs,
                .exitCode = wait_result.exitCode,
                .hasExitCode = wait_result.hasExitCode,
                .stdoutBytes = wait_result.stdoutBytes,
                .stderrBytes = wait_result.stderrBytes,
                .stdout = wait_result.stdout,
                .stderr = wait_result.stderr,
                .timedOut = wait_result.timedOut,
                .signal = wait_result.signal,
                .requested = wait_result.requested,
            });
        }

        if (std.mem.eql(u8, request.method, "process.kill")) {
            var kill_result = self.processKillFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer kill_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, .{
                .ok = kill_result.ok,
                .status = kill_result.status,
                .state = kill_result.state,
                .jobId = kill_result.jobId,
                .sessionId = kill_result.sessionId,
                .processId = kill_result.processId,
                .command = kill_result.command,
                .cwd = kill_result.cwd,
                .processState = kill_result.processState,
                .pid = kill_result.pid,
                .running = kill_result.running,
                .startedAtMs = kill_result.startedAtMs,
                .updatedAtMs = kill_result.updatedAtMs,
                .finishedAtMs = kill_result.finishedAtMs,
                .exitCode = kill_result.exitCode,
                .hasExitCode = kill_result.hasExitCode,
                .stdoutBytes = kill_result.stdoutBytes,
                .stderrBytes = kill_result.stderrBytes,
                .stdout = kill_result.stdout,
                .stderr = kill_result.stderr,
                .timedOut = kill_result.timedOut,
                .signal = kill_result.signal,
                .requested = kill_result.requested,
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

    fn executeCode(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        language_raw: []const u8,
        code: []const u8,
        cwd: []const u8,
        runtime_path_override: []const u8,
        timeout_ms: u32,
        args: []const []const u8,
        keep_files: bool,
    ) !ExecuteCodeResult {
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
            return error.ProcessManagementUnsupported;
        }

        const language = try normalizeExecuteCodeLanguage(language_raw);
        const effective_cwd = try self.resolveProcessCwdAlloc(allocator, cwd);
        defer allocator.free(effective_cwd);

        const runtime_path_value = blk: {
            const trimmed = std.mem.trim(u8, runtime_path_override, " \t\r\n");
            if (trimmed.len > 0) break :blk trimmed;
            break :blk defaultRuntimePathForExecuteCodeLanguage(language);
        };
        if (!self.exec_enabled or !pal.proc.isCommandAllowed(runtime_path_value, self.exec_allowlist)) {
            return error.CommandDenied;
        }

        const job_note = try std.fmt.allocPrint(self.allocator, "execute_code:{s}", .{language});
        defer self.allocator.free(job_note);
        const job_id = try self.runtime_state.enqueueJob(.exec, job_note);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        const scratch_root = try self.executeCodeScratchRootAlloc(allocator);
        defer allocator.free(scratch_root);
        try pal.fs.createDirPath(self.io, scratch_root);

        const exec_dir_name = try std.fmt.allocPrint(allocator, "exec-{d}", .{job_id});
        defer allocator.free(exec_dir_name);
        const exec_dir = try std.fs.path.join(allocator, &.{ scratch_root, exec_dir_name });
        defer allocator.free(exec_dir);
        defer if (!keep_files) self.cleanupExecuteCodeDir(exec_dir);
        try pal.fs.createDirPath(self.io, exec_dir);

        const script_name = try std.fmt.allocPrint(allocator, "snippet{s}", .{executeCodeExtension(language)});
        defer allocator.free(script_name);
        const script_path = try std.fs.path.join(allocator, &.{ exec_dir, script_name });
        errdefer allocator.free(script_path);
        try pal.fs.writeFile(self.io, script_path, code);

        const zig_global_cache_dir = if (std.mem.eql(u8, language, "zig")) try std.fs.path.join(allocator, &.{ exec_dir, "zig-global-cache" }) else null;
        defer if (zig_global_cache_dir) |value| allocator.free(value);
        const zig_local_cache_dir = if (std.mem.eql(u8, language, "zig")) try std.fs.path.join(allocator, &.{ exec_dir, "zig-local-cache" }) else null;
        defer if (zig_local_cache_dir) |value| allocator.free(value);
        if (zig_global_cache_dir) |value| try pal.fs.createDirPath(self.io, value);
        if (zig_local_cache_dir) |value| try pal.fs.createDirPath(self.io, value);

        const argv = try buildExecuteCodeArgvOwned(allocator, language, runtime_path_value, script_path, args, zig_local_cache_dir, zig_global_cache_dir);
        defer allocator.free(argv);

        const command_copy = try buildCommandPreviewAlloc(allocator, argv);
        errdefer allocator.free(command_copy);

        const run_result = try std.process.run(allocator, self.io, .{
            .argv = argv,
            .cwd = .{ .path = effective_cwd },
            .timeout = pal.proc.timeoutFromMs(timeout_ms),
            .stdout_limit = .limited(max_exec_output_bytes),
            .stderr_limit = .limited(max_exec_output_bytes),
            .create_no_window = true,
        });
        errdefer allocator.free(run_result.stdout);
        errdefer allocator.free(run_result.stderr);

        const exit_code: i32 = pal.proc.termExitCode(run_result.term);
        const session_copy = try allocator.dupe(u8, session_id);
        errdefer allocator.free(session_copy);
        const language_copy = try allocator.dupe(u8, language);
        errdefer allocator.free(language_copy);
        const runtime_path_copy = try allocator.dupe(u8, runtime_path_value);
        errdefer allocator.free(runtime_path_copy);
        const cwd_copy = try allocator.dupe(u8, effective_cwd);
        errdefer allocator.free(cwd_copy);

        const session_note = try std.fmt.allocPrint(self.allocator, "execute_code:{s}:{d}", .{ language, exit_code });
        defer self.allocator.free(session_note);
        try self.runtime_state.upsertSession(session_id, session_note, nowUnixMilliseconds(self.io));

        return .{
            .ok = exit_code == 0,
            .status = if (exit_code == 0) 200 else 500,
            .state = "completed",
            .jobId = job_id,
            .sessionId = session_copy,
            .language = language_copy,
            .runtimePath = runtime_path_copy,
            .scriptPath = script_path,
            .cwd = cwd_copy,
            .command = command_copy,
            .exitCode = exit_code,
            .stdout = run_result.stdout,
            .stderr = run_result.stderr,
            .keptFiles = keep_files,
        };
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

    fn fileSearch(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        path: []const u8,
        query: []const u8,
        max_results_u32: u32,
    ) !FileSearchResult {
        const effective_path = try self.resolveSandboxedPath(allocator, path, .read);
        defer allocator.free(effective_path);

        const absolute_path = if (builtin.os.tag == .freestanding or std.fs.path.isAbsolute(effective_path))
            try allocator.dupe(u8, effective_path)
        else
            try pal.sandbox.resolveAbsolutePath(self.io, allocator, effective_path);
        defer allocator.free(absolute_path);

        const job_id = try self.runtime_state.enqueueJob(.file_read, absolute_path);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        const max_results: usize = if (max_results_u32 == 0) 50 else @as(usize, @intCast(max_results_u32));
        var matches: std.ArrayList(SearchMatch) = .empty;
        errdefer deinitSearchMatchList(allocator, &matches);

        var files_scanned: usize = 0;
        try self.collectFileSearchMatches(allocator, absolute_path, query, max_results, &matches, &files_scanned);

        const session_copy = try allocator.dupe(u8, session_id);
        errdefer allocator.free(session_copy);
        const path_copy = try allocator.dupe(u8, absolute_path);
        errdefer allocator.free(path_copy);
        const query_copy = try allocator.dupe(u8, query);
        errdefer allocator.free(query_copy);
        const items = try matches.toOwnedSlice(allocator);

        const session_note = try std.fmt.allocPrint(self.allocator, "file.search:{s}:{s}", .{ absolute_path, query });
        defer self.allocator.free(session_note);
        try self.runtime_state.upsertSession(session_id, session_note, nowUnixMilliseconds(self.io));

        return .{
            .ok = true,
            .status = 200,
            .state = "completed",
            .jobId = job_id,
            .sessionId = session_copy,
            .path = path_copy,
            .query = query_copy,
            .filesScanned = files_scanned,
            .count = items.len,
            .items = items,
        };
    }

    fn filePatch(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        path: []const u8,
        old_text: []const u8,
        new_text: []const u8,
        replace_all: bool,
    ) !FilePatchResult {
        if (std.mem.trim(u8, old_text, " \t\r\n").len == 0) return error.MissingOldText;

        const effective_path = try self.resolveSandboxedPath(allocator, path, .write);
        defer allocator.free(effective_path);

        const job_id = try self.runtime_state.enqueueJob(.file_write, effective_path);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        const current = try pal.fs.readFileAlloc(self.io, allocator, effective_path, max_file_read_bytes);
        defer allocator.free(current);

        const total_matches = countOccurrences(current, old_text);
        const applied = total_matches > 0;

        var bytes_written = current.len;
        if (applied) {
            const updated = if (replace_all)
                try std.mem.replaceOwned(u8, allocator, current, old_text, new_text)
            else
                try replaceFirstOwned(allocator, current, old_text, new_text);
            defer allocator.free(updated);

            try self.verifyWritePathAfterMkdir(allocator, effective_path);
            try pal.fs.writeFile(self.io, effective_path, updated);
            bytes_written = updated.len;
        }

        const replacements = if (applied and !replace_all) @as(usize, 1) else total_matches;
        const session_copy = try allocator.dupe(u8, session_id);
        errdefer allocator.free(session_copy);
        const path_copy = try allocator.dupe(u8, effective_path);
        errdefer allocator.free(path_copy);
        const old_copy = try allocator.dupe(u8, old_text);
        errdefer allocator.free(old_copy);
        const new_copy = try allocator.dupe(u8, new_text);
        errdefer allocator.free(new_copy);

        const session_note = try std.fmt.allocPrint(self.allocator, "file.patch:{s}:{d}", .{ effective_path, replacements });
        defer self.allocator.free(session_note);
        try self.runtime_state.upsertSession(session_id, session_note, nowUnixMilliseconds(self.io));

        return .{
            .ok = true,
            .status = 200,
            .state = "completed",
            .jobId = job_id,
            .sessionId = session_copy,
            .path = path_copy,
            .oldText = old_copy,
            .newText = new_copy,
            .replacements = replacements,
            .bytes = bytes_written,
            .applied = applied,
        };
    }

    fn webSearch(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        query: []const u8,
        limit: u32,
        endpoint: []const u8,
        timeout_ms: u32,
    ) !WebSearchResult {
        const job_id = try self.runtime_state.enqueueJob(.exec, query);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        var search_result = try web_tools.search(allocator, query, limit, endpoint, timeout_ms);
        errdefer search_result.deinit(allocator);

        const session_copy = try allocator.dupe(u8, session_id);
        errdefer allocator.free(session_copy);
        const query_copy = try allocator.dupe(u8, query);
        errdefer allocator.free(query_copy);

        const session_note = try std.fmt.allocPrint(self.allocator, "web.search:{s}", .{query});
        defer self.allocator.free(session_note);
        try self.runtime_state.upsertSession(session_id, session_note, nowUnixMilliseconds(self.io));

        return .{
            .ok = true,
            .status = 200,
            .state = "completed",
            .jobId = job_id,
            .sessionId = session_copy,
            .query = query_copy,
            .provider = search_result.provider,
            .requestUrl = search_result.requestUrl,
            .latencyMs = search_result.latencyMs,
            .count = search_result.count,
            .data = search_result.data,
        };
    }

    fn webExtract(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        urls: []const []const u8,
        max_chars_u32: u32,
        timeout_ms: u32,
    ) !WebExtractResult {
        const job_id = try self.runtime_state.enqueueJob(.exec, "web.extract");
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        const max_chars: usize = if (max_chars_u32 == 0) web_tools.default_extract_max_chars else @as(usize, @intCast(max_chars_u32));
        var extract_result = try web_tools.extract(allocator, urls, max_chars, timeout_ms);
        errdefer extract_result.deinit(allocator);

        const session_copy = try allocator.dupe(u8, session_id);
        errdefer allocator.free(session_copy);

        const session_note = try std.fmt.allocPrint(self.allocator, "web.extract:{d}", .{urls.len});
        defer self.allocator.free(session_note);
        try self.runtime_state.upsertSession(session_id, session_note, nowUnixMilliseconds(self.io));

        return .{
            .ok = true,
            .status = 200,
            .state = "completed",
            .jobId = job_id,
            .sessionId = session_copy,
            .count = extract_result.count,
            .results = extract_result.results,
        };
    }

    fn processStart(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        command: []const u8,
        cwd: []const u8,
    ) !ProcessStartResult {
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
            return error.ProcessManagementUnsupported;
        }
        if (!self.exec_enabled or !pal.proc.isCommandAllowed(command, self.exec_allowlist)) {
            return error.CommandDenied;
        }

        const effective_cwd = try self.resolveProcessCwdAlloc(allocator, cwd);
        defer allocator.free(effective_cwd);

        const job_id = try self.runtime_state.enqueueJob(.exec, command);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        const log_root = try self.processLogRootAlloc(allocator);
        defer allocator.free(log_root);
        try pal.fs.createDirPath(self.io, log_root);

        const stdout_name = try std.fmt.allocPrint(allocator, "process-{d}.stdout.log", .{job_id});
        defer allocator.free(stdout_name);
        const stderr_name = try std.fmt.allocPrint(allocator, "process-{d}.stderr.log", .{job_id});
        defer allocator.free(stderr_name);
        const stdout_path = try std.fs.path.join(allocator, &.{ log_root, stdout_name });
        defer allocator.free(stdout_path);
        const stderr_path = try std.fs.path.join(allocator, &.{ log_root, stderr_name });
        defer allocator.free(stderr_path);

        var stdout_file = try std.Io.Dir.createFileAbsolute(self.io, stdout_path, .{});
        defer stdout_file.close(self.io);
        var stderr_file = try std.Io.Dir.createFileAbsolute(self.io, stderr_path, .{});
        defer stderr_file.close(self.io);

        const argv = [_][]const u8{ "/bin/sh", "-lc", command };
        var child = try std.process.spawn(self.io, .{
            .argv = &argv,
            .cwd = .{ .path = effective_cwd },
            .stdin = .ignore,
            .stdout = .{ .file = stdout_file },
            .stderr = .{ .file = stderr_file },
            .create_no_window = true,
        });
        errdefer child.kill(self.io);

        const child_id = child.id orelse return error.ProcessManagementUnsupported;
        const pid: i64 = @intCast(child_id);
        const started_at_ms = nowUnixMilliseconds(self.io);

        var proc_snapshot = try self.process_registry.addProcess(
            allocator,
            session_id,
            command,
            effective_cwd,
            stdout_path,
            stderr_path,
            pid,
            started_at_ms,
        );
        defer proc_snapshot.deinit(allocator);

        const session_note = try std.fmt.allocPrint(
            self.allocator,
            "process.start:{s}:{s}",
            .{ proc_snapshot.process_id, command },
        );
        defer self.allocator.free(session_note);
        try self.runtime_state.upsertSession(session_id, session_note, started_at_ms);

        return .{
            .ok = true,
            .status = 202,
            .state = "started",
            .jobId = job_id,
            .sessionId = try allocator.dupe(u8, proc_snapshot.session_id),
            .processId = try allocator.dupe(u8, proc_snapshot.process_id),
            .command = try allocator.dupe(u8, proc_snapshot.command),
            .cwd = try allocator.dupe(u8, proc_snapshot.cwd),
            .pid = proc_snapshot.pid,
            .startedAtMs = proc_snapshot.started_at_ms,
            .stdoutPath = try allocator.dupe(u8, proc_snapshot.stdout_path),
            .stderrPath = try allocator.dupe(u8, proc_snapshot.stderr_path),
        };
    }

    fn processList(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
    ) !ProcessListResult {
        const session_filter = blk: {
            const trimmed = std.mem.trim(u8, session_id, " \t\r\n");
            if (trimmed.len == 0) break :blk null;
            break :blk session_id;
        };

        const payload = session_filter orelse "process.list";
        const job_id = try self.runtime_state.enqueueJob(.file_read, payload);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        const snapshots = try self.process_registry.listSnapshotsOwned(allocator, session_filter);
        defer {
            for (snapshots) |*proc_snapshot| proc_snapshot.deinit(allocator);
            allocator.free(snapshots);
        }

        var items = try allocator.alloc(ProcessSummary, snapshots.len);
        var out_index: usize = 0;
        errdefer {
            for (items[0..out_index]) |*item| item.deinit(allocator);
            allocator.free(items);
        }
        for (snapshots) |*proc_snapshot| {
            items[out_index] = try self.processSummaryFromSnapshot(allocator, proc_snapshot);
            out_index += 1;
        }

        return .{
            .ok = true,
            .status = 200,
            .state = "completed",
            .jobId = job_id,
            .sessionId = try allocator.dupe(u8, session_filter orelse ""),
            .count = items.len,
            .items = items,
        };
    }

    fn processPoll(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        process_id: []const u8,
    ) !ProcessStatusResult {
        const job_id = try self.runtime_state.enqueueJob(.file_read, process_id);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        var proc_snapshot = self.process_registry.getSnapshotOwned(allocator, process_id) catch |err| switch (err) {
            error.ProcessNotFound => return error.ProcessNotFound,
            else => return err,
        };
        defer proc_snapshot.deinit(allocator);

        return self.processStatusFromSnapshot(allocator, job_id, &proc_snapshot, false, false, "");
    }

    fn processRead(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        process_id: []const u8,
    ) !ProcessStatusResult {
        const job_id = try self.runtime_state.enqueueJob(.file_read, process_id);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        var proc_snapshot = self.process_registry.getSnapshotOwned(allocator, process_id) catch |err| switch (err) {
            error.ProcessNotFound => return error.ProcessNotFound,
            else => return err,
        };
        defer proc_snapshot.deinit(allocator);

        return self.processStatusFromSnapshot(allocator, job_id, &proc_snapshot, false, false, "");
    }

    fn processWait(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        process_id: []const u8,
        timeout_ms: u32,
    ) !ProcessStatusResult {
        const job_id = try self.runtime_state.enqueueJob(.exec, process_id);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        const started_ms = nowUnixMilliseconds(self.io);
        while (true) {
            var proc_snapshot = self.process_registry.getSnapshotOwned(allocator, process_id) catch |err| switch (err) {
                error.ProcessNotFound => return error.ProcessNotFound,
                else => return err,
            };

            const elapsed_ms = nowUnixMilliseconds(self.io) - started_ms;
            const timed_out = elapsed_ms >= @as(i64, @intCast(timeout_ms));
            const done = proc_snapshot.lifecycle_state != .running;
            if (done or timed_out) {
                const result = try self.processStatusFromSnapshot(allocator, job_id, &proc_snapshot, timed_out and !done, false, "");
                proc_snapshot.deinit(allocator);
                return result;
            }

            proc_snapshot.deinit(allocator);
            try std.Io.sleep(self.io, std.Io.Duration.fromMilliseconds(50), .awake);
        }
    }

    fn processKill(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        process_id: []const u8,
    ) !ProcessStatusResult {
        const job_id = try self.runtime_state.enqueueJob(.exec, process_id);
        const queued = self.runtime_state.dequeueJob() orelse return error.JobQueueInvariant;
        defer self.runtime_state.releaseJob(queued);

        var proc_snapshot = try self.process_registry.requestTerminate(allocator, process_id, nowUnixMilliseconds(self.io));

        if (proc_snapshot.lifecycle_state == .running) {
            try std.Io.sleep(self.io, std.Io.Duration.fromMilliseconds(50), .awake);
            proc_snapshot.deinit(allocator);
            proc_snapshot = try self.process_registry.getSnapshotOwned(allocator, process_id);
        }
        defer proc_snapshot.deinit(allocator);

        const session_note = try std.fmt.allocPrint(self.allocator, "process.kill:{s}", .{process_id});
        defer self.allocator.free(session_note);
        try self.runtime_state.upsertSession(proc_snapshot.session_id, session_note, nowUnixMilliseconds(self.io));

        return self.processStatusFromSnapshot(allocator, job_id, &proc_snapshot, false, true, "TERM");
    }

    fn resolveProcessCwdAlloc(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        cwd: []const u8,
    ) ![]u8 {
        const trimmed = std.mem.trim(u8, cwd, " \t\r\n");
        if (self.file_sandbox_enabled) {
            return self.resolveSandboxedPath(allocator, if (trimmed.len == 0) "." else trimmed, .read);
        }
        if (trimmed.len == 0) {
            const cwd_real_z = try std.Io.Dir.cwd().realPathFileAlloc(self.io, ".", allocator);
            defer allocator.free(cwd_real_z);
            return allocator.dupe(u8, std.mem.sliceTo(cwd_real_z, 0));
        }
        return pal.sandbox.resolveAbsolutePath(self.io, allocator, trimmed);
    }

    fn processLogRootAlloc(self: *ToolRuntime, allocator: std.mem.Allocator) ![]u8 {
        const runtime_snapshot = self.runtime_state.snapshot();
        if (runtime_snapshot.persisted and !std.mem.startsWith(u8, runtime_snapshot.statePath, "memory://")) {
            if (std.fs.path.dirname(runtime_snapshot.statePath)) |parent| {
                return std.fs.path.join(allocator, &.{ parent, "processes" });
            }
        }
        return allocator.dupe(u8, "/tmp/openclaw-zig-processes");
    }

    fn executeCodeScratchRootAlloc(self: *ToolRuntime, allocator: std.mem.Allocator) ![]u8 {
        const runtime_snapshot = self.runtime_state.snapshot();
        if (runtime_snapshot.persisted and !std.mem.startsWith(u8, runtime_snapshot.statePath, "memory://")) {
            if (std.fs.path.dirname(runtime_snapshot.statePath)) |parent| {
                return std.fs.path.join(allocator, &.{ parent, "execute-code" });
            }
        }
        return allocator.dupe(u8, "/tmp/openclaw-zig-execute-code");
    }

    fn cleanupExecuteCodeDir(self: *ToolRuntime, absolute_path: []const u8) void {
        if (builtin.os.tag == .freestanding) return;
        const parent = std.fs.path.dirname(absolute_path) orelse return;
        var dir = std.Io.Dir.openDirAbsolute(self.io, parent, .{}) catch return;
        defer dir.close(self.io);
        dir.deleteTree(self.io, std.fs.path.basename(absolute_path)) catch {};
    }

    fn processSummaryFromSnapshot(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        proc_snapshot: *const process_registry.ProcessSnapshot,
    ) !ProcessSummary {
        return .{
            .processId = try allocator.dupe(u8, proc_snapshot.process_id),
            .sessionId = try allocator.dupe(u8, proc_snapshot.session_id),
            .command = try allocator.dupe(u8, proc_snapshot.command),
            .cwd = try allocator.dupe(u8, proc_snapshot.cwd),
            .processState = try allocator.dupe(u8, process_registry.lifecycleStateText(proc_snapshot.lifecycle_state)),
            .pid = proc_snapshot.pid,
            .running = proc_snapshot.lifecycle_state == .running,
            .startedAtMs = proc_snapshot.started_at_ms,
            .updatedAtMs = proc_snapshot.updated_at_ms,
            .finishedAtMs = proc_snapshot.finished_at_ms,
            .exitCode = proc_snapshot.exit_code,
            .hasExitCode = proc_snapshot.has_exit_code,
            .stdoutBytes = logFileSizeOrZero(self.io, proc_snapshot.stdout_path),
            .stderrBytes = logFileSizeOrZero(self.io, proc_snapshot.stderr_path),
        };
    }

    fn processStatusFromSnapshot(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        job_id: u64,
        proc_snapshot: *const process_registry.ProcessSnapshot,
        timed_out: bool,
        requested: bool,
        requested_signal: []const u8,
    ) !ProcessStatusResult {
        const stdout_bytes = logFileSizeOrZero(self.io, proc_snapshot.stdout_path);
        const stderr_bytes = logFileSizeOrZero(self.io, proc_snapshot.stderr_path);
        const stdout = try readProcessLogAlloc(self.io, allocator, proc_snapshot.stdout_path, max_process_log_bytes);
        errdefer allocator.free(stdout);
        const stderr = try readProcessLogAlloc(self.io, allocator, proc_snapshot.stderr_path, max_process_log_bytes);
        errdefer allocator.free(stderr);
        const signal_name = if (requested_signal.len > 0) requested_signal else signalNameFromExitCode(proc_snapshot.exit_code);

        return .{
            .ok = if (requested) true else processOperationOk(proc_snapshot),
            .status = processHttpStatus(proc_snapshot, timed_out, requested),
            .state = processResultState(proc_snapshot, timed_out, requested),
            .jobId = job_id,
            .sessionId = try allocator.dupe(u8, proc_snapshot.session_id),
            .processId = try allocator.dupe(u8, proc_snapshot.process_id),
            .command = try allocator.dupe(u8, proc_snapshot.command),
            .cwd = try allocator.dupe(u8, proc_snapshot.cwd),
            .processState = try allocator.dupe(u8, process_registry.lifecycleStateText(proc_snapshot.lifecycle_state)),
            .pid = proc_snapshot.pid,
            .running = proc_snapshot.lifecycle_state == .running,
            .startedAtMs = proc_snapshot.started_at_ms,
            .updatedAtMs = proc_snapshot.updated_at_ms,
            .finishedAtMs = proc_snapshot.finished_at_ms,
            .exitCode = proc_snapshot.exit_code,
            .hasExitCode = proc_snapshot.has_exit_code,
            .stdoutBytes = stdout_bytes,
            .stderrBytes = stderr_bytes,
            .stdout = stdout,
            .stderr = stderr,
            .timedOut = timed_out,
            .signal = try allocator.dupe(u8, signal_name),
            .requested = requested,
        };
    }

    fn collectFileSearchMatches(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        absolute_path: []const u8,
        query: []const u8,
        max_results: usize,
        matches: *std.ArrayList(SearchMatch),
        files_scanned: *usize,
    ) !void {
        const stat = try pal.fs.statNoFollow(self.io, absolute_path);
        if (stat.kind == .directory) {
            if (builtin.os.tag == .freestanding) return error.PathAccessDenied;

            var dir = try std.Io.Dir.openDirAbsolute(self.io, absolute_path, .{
                .iterate = true,
                .access_sub_paths = true,
                .follow_symlinks = false,
            });
            defer dir.close(self.io);

            var walker = try dir.walk(allocator);
            defer walker.deinit();

            while (try walker.next(self.io)) |entry| {
                if (matches.items.len >= max_results) break;
                if (entry.kind != .file) continue;

                const full_path = try std.fs.path.join(allocator, &.{ absolute_path, entry.path });
                defer allocator.free(full_path);
                self.scanFileForQuery(allocator, full_path, query, max_results, matches, files_scanned) catch continue;
            }
            return;
        }

        try self.scanFileForQuery(allocator, absolute_path, query, max_results, matches, files_scanned);
    }

    fn scanFileForQuery(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        file_path: []const u8,
        query: []const u8,
        max_results: usize,
        matches: *std.ArrayList(SearchMatch),
        files_scanned: *usize,
    ) !void {
        const content = try pal.fs.readFileAlloc(self.io, allocator, file_path, max_file_read_bytes);
        defer allocator.free(content);
        files_scanned.* += 1;

        if (std.mem.indexOfScalar(u8, content, 0) != null) return;

        var line_it = std.mem.splitScalar(u8, content, '\n');
        var line_number: usize = 1;
        while (line_it.next()) |line_raw| : (line_number += 1) {
            const line = std.mem.trimEnd(u8, line_raw, "\r");
            var search_start: usize = 0;
            while (std.mem.indexOfPos(u8, line, search_start, query)) |match_index| {
                const path_copy = try allocator.dupe(u8, file_path);
                errdefer allocator.free(path_copy);
                const preview_copy = try allocator.dupe(u8, previewSlice(line));
                errdefer allocator.free(preview_copy);
                try matches.append(allocator, .{
                    .path = path_copy,
                    .line = line_number,
                    .column = match_index + 1,
                    .preview = preview_copy,
                });
                if (matches.items.len >= max_results) return;
                search_start = match_index + @max(query.len, 1);
            }
        }
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

fn processOperationOk(proc_snapshot: *const process_registry.ProcessSnapshot) bool {
    if (proc_snapshot.lifecycle_state == .running) return true;
    if (proc_snapshot.lifecycle_state == .killed) return true;
    if (!proc_snapshot.has_exit_code) return proc_snapshot.lifecycle_state != .failed;
    return proc_snapshot.exit_code == 0;
}

fn processHttpStatus(
    proc_snapshot: *const process_registry.ProcessSnapshot,
    timed_out: bool,
    requested: bool,
) u16 {
    if (timed_out) return 202;
    if (requested and proc_snapshot.lifecycle_state == .running) return 202;
    if (requested and proc_snapshot.lifecycle_state == .killed) return 200;
    if (proc_snapshot.lifecycle_state == .running) return 202;
    if (proc_snapshot.lifecycle_state == .failed) return 500;
    if (proc_snapshot.lifecycle_state == .killed) return 200;
    if (proc_snapshot.has_exit_code and proc_snapshot.exit_code != 0) return 500;
    return 200;
}

fn processResultState(
    proc_snapshot: *const process_registry.ProcessSnapshot,
    timed_out: bool,
    requested: bool,
) []const u8 {
    if (timed_out) return "timed_out";
    if (requested and proc_snapshot.lifecycle_state == .running) return "signaled";
    if (proc_snapshot.lifecycle_state == .running) return "running";
    return "completed";
}

fn signalNameFromExitCode(exit_code: i32) []const u8 {
    if (exit_code >= 0) return "";
    return switch (-exit_code) {
        2 => "INT",
        9 => "KILL",
        15 => "TERM",
        else => "",
    };
}

fn readProcessLogAlloc(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    limit: usize,
) ![]u8 {
    var file = std.Io.Dir.openFileAbsolute(io, path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return allocator.dupe(u8, ""),
        else => return err,
    };
    defer file.close(io);

    const stat = try file.stat(io);
    const want_u64: u64 = @min(stat.size, @as(u64, @intCast(limit)));
    const want: usize = @intCast(want_u64);
    var buffer = try allocator.alloc(u8, want);
    errdefer allocator.free(buffer);
    const offset = stat.size - want_u64;
    const read_count = try file.readPositionalAll(io, buffer, offset);
    if (read_count == want) return buffer;

    const sized = try allocator.dupe(u8, buffer[0..read_count]);
    allocator.free(buffer);
    return sized;
}

fn logFileSizeOrZero(io: std.Io, path: []const u8) usize {
    const stat = pal.fs.statNoFollow(io, path) catch return 0;
    return @intCast(@min(stat.size, @as(u64, @intCast(std.math.maxInt(usize)))));
}

fn deinitSearchMatchList(allocator: std.mem.Allocator, list: *std.ArrayList(SearchMatch)) void {
    for (list.items) |*item| item.deinit(allocator);
    list.deinit(allocator);
}

fn previewSlice(line: []const u8) []const u8 {
    const max_preview_bytes: usize = 240;
    return if (line.len <= max_preview_bytes) line else line[0..max_preview_bytes];
}

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    if (needle.len == 0) return 0;
    var count: usize = 0;
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, start, needle)) |idx| {
        count += 1;
        start = idx + needle.len;
    }
    return count;
}

fn replaceFirstOwned(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, input);
    const idx = std.mem.indexOf(u8, input, needle) orelse return allocator.dupe(u8, input);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, input[0..idx]);
    try out.appendSlice(allocator, replacement);
    try out.appendSlice(allocator, input[idx + needle.len ..]);
    return out.toOwnedSlice(allocator);
}

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

fn getOptionalStringAliases(
    params: std.json.Value,
    keys: []const []const u8,
    default_value: []const u8,
) []const u8 {
    for (keys) |key| {
        const value = getOptionalString(params, key, "");
        if (std.mem.trim(u8, value, " \t\r\n").len > 0) return value;
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

fn getOptionalBool(
    params: std.json.Value,
    key: []const u8,
    default_value: bool,
) bool {
    if (params.object.get(key)) |value| switch (value) {
        .bool => |raw| return raw,
        .integer => |raw| return raw != 0,
        .string => |raw| {
            const trimmed = std.mem.trim(u8, raw, " \t\r\n");
            if (std.ascii.eqlIgnoreCase(trimmed, "true") or std.ascii.eqlIgnoreCase(trimmed, "1") or std.ascii.eqlIgnoreCase(trimmed, "yes")) return true;
            if (std.ascii.eqlIgnoreCase(trimmed, "false") or std.ascii.eqlIgnoreCase(trimmed, "0") or std.ascii.eqlIgnoreCase(trimmed, "no")) return false;
        },
        else => {},
    };
    return default_value;
}

fn freeOwnedStringList(allocator: std.mem.Allocator, list: []const []const u8) void {
    for (list) |item| allocator.free(item);
    allocator.free(list);
}

fn getOptionalStringListOwned(
    allocator: std.mem.Allocator,
    params: std.json.Value,
    key: []const u8,
) ![]const []const u8 {
    if (params.object.get(key)) |value| {
        if (value == .array and value.array.items.len > 0) {
            var list: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (list.items) |item| allocator.free(item);
                list.deinit(allocator);
            }
            for (value.array.items) |entry| {
                if (entry != .string) continue;
                const trimmed = std.mem.trim(u8, entry.string, " \t\r\n");
                if (trimmed.len == 0) continue;
                try list.append(allocator, try allocator.dupe(u8, trimmed));
            }
            return list.toOwnedSlice(allocator);
        }
        if (value == .string) {
            const trimmed = std.mem.trim(u8, value.string, " \t\r\n");
            if (trimmed.len > 0) {
                const duped = try allocator.dupe(u8, trimmed);
                errdefer allocator.free(duped);
                var out = try allocator.alloc([]const u8, 1);
                out[0] = duped;
                return out;
            }
        }
    }
    return allocator.alloc([]const u8, 0);
}

fn getRequiredStringListOwned(
    allocator: std.mem.Allocator,
    params: std.json.Value,
    key: []const u8,
    fallback_key: ?[]const u8,
    err_tag: anyerror,
) ![]const []const u8 {
    if (params.object.get(key)) |value| {
        if (value == .array and value.array.items.len > 0) {
            var list: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (list.items) |item| allocator.free(item);
                list.deinit(allocator);
            }
            for (value.array.items) |entry| {
                if (entry != .string) continue;
                const trimmed = std.mem.trim(u8, entry.string, " \t\r\n");
                if (trimmed.len == 0) continue;
                try list.append(allocator, try allocator.dupe(u8, trimmed));
            }
            if (list.items.len > 0) return list.toOwnedSlice(allocator);
        }
    }
    if (fallback_key) |fallback| {
        if (params.object.get(fallback)) |value| {
            if (value == .string and std.mem.trim(u8, value.string, " \t\r\n").len > 0) {
                const duped = try allocator.dupe(u8, std.mem.trim(u8, value.string, " \t\r\n"));
                var out = try allocator.alloc([]const u8, 1);
                out[0] = duped;
                return out;
            }
        }
    }
    return err_tag;
}

fn executeCodeExtension(language: []const u8) []const u8 {
    if (std.mem.eql(u8, language, "javascript")) return ".js";
    if (std.mem.eql(u8, language, "python")) return ".py";
    if (std.mem.eql(u8, language, "zig")) return ".zig";
    return ".sh";
}

fn defaultRuntimePathForExecuteCodeLanguage(language: []const u8) []const u8 {
    if (std.mem.eql(u8, language, "javascript")) return "node";
    if (std.mem.eql(u8, language, "python")) return "python3";
    if (std.mem.eql(u8, language, "zig")) return "zig";
    if (std.mem.eql(u8, language, "bash")) return "bash";
    return "/bin/sh";
}

fn normalizeExecuteCodeLanguage(language_raw: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, language_raw, " \t\r\n");
    if (trimmed.len == 0) return error.MissingLanguage;
    if (std.ascii.eqlIgnoreCase(trimmed, "javascript") or std.ascii.eqlIgnoreCase(trimmed, "js") or std.ascii.eqlIgnoreCase(trimmed, "node")) return "javascript";
    if (std.ascii.eqlIgnoreCase(trimmed, "python") or std.ascii.eqlIgnoreCase(trimmed, "py")) return "python";
    if (std.ascii.eqlIgnoreCase(trimmed, "zig")) return "zig";
    if (std.ascii.eqlIgnoreCase(trimmed, "bash")) return "bash";
    if (std.ascii.eqlIgnoreCase(trimmed, "shell") or std.ascii.eqlIgnoreCase(trimmed, "sh")) return "shell";
    return error.UnsupportedLanguage;
}

fn buildExecuteCodeArgvOwned(
    allocator: std.mem.Allocator,
    language: []const u8,
    runtime_path: []const u8,
    script_path: []const u8,
    args: []const []const u8,
    zig_local_cache_dir: ?[]const u8,
    zig_global_cache_dir: ?[]const u8,
) ![][]const u8 {
    const is_zig = std.mem.eql(u8, language, "zig");
    const zig_cache_args: usize = if (is_zig) 4 else 0;
    const leading_args: usize = if (is_zig) 2 + zig_cache_args else 1;
    const separator_args: usize = if (is_zig and args.len > 0) 1 else 0;
    var argv = try allocator.alloc([]const u8, 1 + leading_args + separator_args + args.len);
    var index: usize = 0;
    argv[index] = runtime_path;
    index += 1;
    if (is_zig) {
        argv[index] = "run";
        index += 1;
        argv[index] = "--cache-dir";
        index += 1;
        argv[index] = zig_local_cache_dir orelse script_path;
        index += 1;
        argv[index] = "--global-cache-dir";
        index += 1;
        argv[index] = zig_global_cache_dir orelse script_path;
        index += 1;
        argv[index] = script_path;
        index += 1;
        if (args.len > 0) {
            argv[index] = "--";
            index += 1;
        }
    } else {
        argv[index] = script_path;
        index += 1;
    }
    for (args) |arg| {
        argv[index] = arg;
        index += 1;
    }
    return argv;
}

fn buildCommandPreviewAlloc(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    for (argv, 0..) |arg, index| {
        if (index != 0) try output.append(allocator, ' ');
        const needs_quotes = std.mem.indexOfAny(u8, arg, " \t\r\n\"") != null;
        if (needs_quotes) try output.append(allocator, '"');
        for (arg) |ch| {
            if (ch == '"') {
                try output.append(allocator, '\\');
                try output.append(allocator, '"');
            } else {
                try output.append(allocator, ch);
            }
        }
        if (needs_quotes) try output.append(allocator, '"');
    }

    return output.toOwnedSlice(allocator);
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
        error.MissingQuery,
        error.MissingOldText,
        error.MissingSessionId,
        error.MissingProcessId,
        error.MissingUrl,
        error.MissingLanguage,
        error.MissingCode,
        error.UnsupportedLanguage,
        => -32602,
        error.CommandDenied => -32010,
        error.PathAccessDenied,
        error.PathTraversalDetected,
        error.PathSymlinkDisallowed,
        => -32011,
        error.ProcessManagementUnsupported => -32012,
        error.WebFetchUnsupported => -32013,
        error.SessionNotFound => -32044,
        error.ProcessNotFound => -32045,
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

test "tool runtime file search and patch provide coding-agent primitives" {
    const allocator = std.testing.allocator;
    var runtime = ToolRuntime.init(std.heap.page_allocator, testingToolIo());
    defer runtime.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = testingHostedIo();
    const base_path = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(base_path);
    const file_a = try std.fs.path.join(allocator, &.{ base_path, "a.txt" });
    defer allocator.free(file_a);
    const file_b = try std.fs.path.join(allocator, &.{ base_path, "nested", "b.txt" });
    defer allocator.free(file_b);

    var write_a = try runtime.fileWrite(allocator, "sess-coding", file_a, "alpha\nneedle here\nomega\n");
    defer write_a.deinit(allocator);
    var write_b = try runtime.fileWrite(allocator, "sess-coding", file_b, "nested needle line\n");
    defer write_b.deinit(allocator);

    var search_result = try runtime.fileSearch(allocator, "sess-coding", base_path, "needle", 10);
    defer search_result.deinit(allocator);
    try std.testing.expect(search_result.ok);
    try std.testing.expect(search_result.count >= 2);
    try std.testing.expect(search_result.filesScanned >= 2);
    try std.testing.expect(search_result.items.len >= 1);
    try std.testing.expect(std.mem.indexOf(u8, search_result.items[0].preview, "needle") != null);

    var patch_result = try runtime.filePatch(allocator, "sess-coding", file_a, "needle here", "needle there", false);
    defer patch_result.deinit(allocator);
    try std.testing.expect(patch_result.ok);
    try std.testing.expect(patch_result.applied);
    try std.testing.expectEqual(@as(usize, 1), patch_result.replacements);

    var patched = try runtime.fileRead(allocator, "sess-coding", file_a);
    defer patched.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, patched.content, "needle there") != null);
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

test "tool runtime execute_code runs shell snippets with cwd isolation" {
    const allocator = std.testing.allocator;
    var runtime = ToolRuntime.init(std.heap.page_allocator, testingToolIo());
    defer runtime.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = testingHostedIo();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(root);

    var result = runtime.executeCode(
        allocator,
        "sess-exec-code",
        "shell",
        "printf exec-code-ok:$PWD",
        root,
        "",
        20_000,
        &.{},
        false,
    ) catch return error.SkipZigTest;
    defer result.deinit(allocator);
    try std.testing.expect(result.ok);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "exec-code-ok:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, root) != null);
    try std.testing.expect(std.mem.eql(u8, result.language, "shell"));
    try std.testing.expect(std.mem.indexOf(u8, result.command, "snippet.sh") != null);

    const session = runtime.runtime_state.getSession("sess-exec-code").?;
    try std.testing.expect(std.mem.indexOf(u8, session.last_message, "execute_code:shell:0") != null);
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

    const json_root = try std.mem.replaceOwned(u8, allocator, root, "\\", "\\\\");
    defer allocator.free(json_root);
    const search_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-search\",\"method\":\"file.search\",\"params\":{{\"sessionId\":\"sess-rpc\",\"path\":\"{s}\",\"query\":\"rpc-data\",\"maxResults\":5}}}}",
        .{json_root},
    );
    defer allocator.free(search_frame);
    const search_response = try runtime.handleRpcFrameAlloc(allocator, search_frame);
    defer allocator.free(search_response);
    try std.testing.expect(std.mem.indexOf(u8, search_response, "\"id\":\"rt-search\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, search_response, "\"count\":1") != null);

    const patch_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-patch\",\"method\":\"file.patch\",\"params\":{{\"sessionId\":\"sess-rpc\",\"path\":\"{s}\",\"oldText\":\"rpc-data\",\"newText\":\"rpc-updated\"}}}}",
        .{json_test_path},
    );
    defer allocator.free(patch_frame);
    const patch_response = try runtime.handleRpcFrameAlloc(allocator, patch_frame);
    defer allocator.free(patch_response);
    try std.testing.expect(std.mem.indexOf(u8, patch_response, "\"applied\":true") != null);

    const read_after_patch = try runtime.handleRpcFrameAlloc(allocator, read_frame);
    defer allocator.free(read_after_patch);
    try std.testing.expect(std.mem.indexOf(u8, read_after_patch, "rpc-updated") != null);

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
