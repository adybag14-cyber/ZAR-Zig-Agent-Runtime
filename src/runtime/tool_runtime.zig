const builtin = @import("builtin");
const std = @import("std");
const config = @import("../config.zig");
const pal = @import("../pal/mod.zig");
const envelope = @import("../protocol/envelope.zig");
const state = @import("state.zig");
const task_receipts = @import("task_receipts.zig");
const process_registry = @import("process_registry.zig");
const web_tools = @import("web_tools.zig");
const tool_contract = @import("tool_contract.zig");
const delegate_task = @import("../gateway/delegate_task.zig");
const time_util = @import("../util/time.zig");

pub const InputError = error{
    InvalidParamsFrame,
    MissingCommand,
    MissingPath,
    MissingContent,
    MissingQuery,
    MissingOldText,
    MissingSessionId,
    MissingTaskId,
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
    SessionCancelled,
    TaskNotFound,
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

pub const SessionHistoryItem = struct {
    sessionId: []const u8,
    createdAtMs: i64,
    updatedAtMs: i64,
    lastMessage: []const u8,

    pub fn deinit(self: *SessionHistoryItem, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.lastMessage);
    }
};

pub const SessionHistoryResult = struct {
    sessionId: []const u8,
    count: usize,
    items: []SessionHistoryItem,

    pub fn deinit(self: *SessionHistoryResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const SessionSearchItem = struct {
    sessionId: []const u8,
    createdAtMs: i64,
    updatedAtMs: i64,
    lastMessage: []const u8,
    preview: []const u8,
    score: f64,

    pub fn deinit(self: *SessionSearchItem, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.lastMessage);
        allocator.free(self.preview);
    }
};

pub const SessionSearchResult = struct {
    query: []const u8,
    count: usize,
    items: []SessionSearchItem,
    neighborCount: usize,
    neighbors: []SessionSearchItem,

    pub fn deinit(self: *SessionSearchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.query);
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        for (self.neighbors) |*item| item.deinit(allocator);
        allocator.free(self.neighbors);
    }
};

pub const AcpSessionItem = struct {
    sessionId: []const u8,
    createdAtMs: i64,
    updatedAtMs: i64,
    cwd: []const u8,
    title: []const u8,
    sourceSessionId: ?[]const u8 = null,
    status: []const u8,
    cancelRequested: bool,
    lastMessage: []const u8,
    messageCount: usize,
    eventCount: usize,
    taskCount: usize,
    latestMessageId: u64,
    latestEventId: u64,

    pub fn deinit(self: *AcpSessionItem, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.cwd);
        allocator.free(self.title);
        if (self.sourceSessionId) |value| allocator.free(value);
        allocator.free(self.status);
        allocator.free(self.lastMessage);
    }
};

pub const AcpSessionsListResult = struct {
    count: usize,
    items: []AcpSessionItem,

    pub fn deinit(self: *AcpSessionsListResult, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const AcpSessionGetResult = struct {
    session: AcpSessionItem,

    pub fn deinit(self: *AcpSessionGetResult, allocator: std.mem.Allocator) void {
        self.session.deinit(allocator);
    }
};

pub const AcpMessageItem = struct {
    messageId: u64,
    sessionId: []const u8,
    role: []const u8,
    kind: []const u8,
    text: []const u8,
    taskId: ?[]const u8 = null,
    createdAtMs: i64,

    pub fn deinit(self: *AcpMessageItem, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.role);
        allocator.free(self.kind);
        allocator.free(self.text);
        if (self.taskId) |value| allocator.free(value);
    }
};

pub const AcpSessionMessagesResult = struct {
    sessionId: []const u8,
    count: usize,
    cursor: u64,
    hasMore: bool,
    items: []AcpMessageItem,

    pub fn deinit(self: *AcpSessionMessagesResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const AcpSessionNewResult = struct {
    created: bool,
    session: AcpSessionItem,

    pub fn deinit(self: *AcpSessionNewResult, allocator: std.mem.Allocator) void {
        self.session.deinit(allocator);
    }
};

pub const AcpSessionLoadResult = struct {
    loaded: bool,
    session: AcpSessionItem,

    pub fn deinit(self: *AcpSessionLoadResult, allocator: std.mem.Allocator) void {
        self.session.deinit(allocator);
    }
};

pub const AcpSessionResumeResult = struct {
    created: bool,
    session: AcpSessionItem,

    pub fn deinit(self: *AcpSessionResumeResult, allocator: std.mem.Allocator) void {
        self.session.deinit(allocator);
    }
};

pub const AcpSessionForkResult = struct {
    sourceSessionId: []const u8,
    clonedMessages: usize,
    session: AcpSessionItem,

    pub fn deinit(self: *AcpSessionForkResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sourceSessionId);
        self.session.deinit(allocator);
    }
};

pub const AcpSessionCancelResult = struct {
    cancelRequested: bool,
    session: AcpSessionItem,

    pub fn deinit(self: *AcpSessionCancelResult, allocator: std.mem.Allocator) void {
        self.session.deinit(allocator);
    }
};

pub const AcpSessionEventItem = struct {
    eventId: u64,
    sessionId: []const u8,
    taskId: ?[]const u8 = null,
    messageId: ?u64 = null,
    atMs: i64,
    kind: []const u8,
    role: ?[]const u8 = null,
    toolCallId: ?[]const u8 = null,
    tool: ?[]const u8 = null,
    toolKind: ?[]const u8 = null,
    status: ?[]const u8 = null,
    preview: ?[]const u8 = null,

    pub fn deinit(self: *AcpSessionEventItem, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        if (self.taskId) |value| allocator.free(value);
        allocator.free(self.kind);
        if (self.role) |value| allocator.free(value);
        if (self.toolCallId) |value| allocator.free(value);
        if (self.tool) |value| allocator.free(value);
        if (self.toolKind) |value| allocator.free(value);
        if (self.status) |value| allocator.free(value);
        if (self.preview) |value| allocator.free(value);
    }
};

pub const AcpSessionEventsResult = struct {
    sessionId: []const u8,
    count: usize,
    cursor: u64,
    hasMore: bool,
    items: []AcpSessionEventItem,

    pub fn deinit(self: *AcpSessionEventsResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const AcpContentBlock = struct {
    type: []const u8,
    text: []const u8,
};

pub const AcpAuthMethod = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,

    pub fn deinit(self: *AcpAuthMethod, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.description);
    }
};

pub const AcpInitializeResult = struct {
    protocolVersion: u32,
    agentInfo: struct {
        name: []const u8,
        displayName: []const u8,
        version: []const u8,
        description: []const u8,
    },
    agentCapabilities: struct {
        sessionCapabilities: struct {
            fork: bool,
            list: bool,
            updates: bool,
            search: bool,
        },
        prompt: bool,
        approvals: bool,
        contentBlocks: struct {
            text: bool,
            image: bool,
            audio: bool,
            resource: bool,
        },
    },
    runtimeTarget: []const u8,
    authMethodCount: usize,
    authMethods: []AcpAuthMethod,

    pub fn deinit(self: *AcpInitializeResult, allocator: std.mem.Allocator) void {
        for (self.authMethods) |*item| item.deinit(allocator);
        allocator.free(self.authMethods);
    }
};

pub const AcpAuthenticateResult = struct {
    ok: bool,
    authenticated: bool,
    methodId: []const u8,
    provider: []const u8,
    runtimeTarget: []const u8,
    message: []const u8,

    pub fn deinit(self: *AcpAuthenticateResult, allocator: std.mem.Allocator) void {
        allocator.free(self.methodId);
        allocator.free(self.provider);
        allocator.free(self.message);
    }
};

pub const AcpSessionUpdateItem = struct {
    updateId: u64,
    sessionId: []const u8,
    taskId: ?[]const u8 = null,
    messageId: ?u64 = null,
    atMs: i64,
    type: []const u8,
    kind: []const u8,
    role: ?[]const u8 = null,
    status: ?[]const u8 = null,
    toolCallId: ?[]const u8 = null,
    tool: ?[]const u8 = null,
    toolKind: ?[]const u8 = null,
    title: ?[]const u8 = null,
    text: ?[]const u8 = null,

    pub fn deinit(self: *AcpSessionUpdateItem, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.type);
        allocator.free(self.kind);
        if (self.taskId) |value| allocator.free(value);
        if (self.role) |value| allocator.free(value);
        if (self.status) |value| allocator.free(value);
        if (self.toolCallId) |value| allocator.free(value);
        if (self.tool) |value| allocator.free(value);
        if (self.toolKind) |value| allocator.free(value);
        if (self.title) |value| allocator.free(value);
        if (self.text) |value| allocator.free(value);
    }
};

pub const AcpSessionUpdatesResult = struct {
    sessionId: []const u8,
    count: usize,
    cursor: u64,
    hasMore: bool,
    items: []AcpSessionUpdateItem,

    pub fn deinit(self: *AcpSessionUpdatesResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const AcpSessionSearchItem = struct {
    sessionId: []const u8,
    title: []const u8,
    cwd: []const u8,
    status: []const u8,
    sourceSessionId: ?[]const u8 = null,
    lastMessage: []const u8,
    snippet: []const u8,
    score: f64,
    createdAtMs: i64,
    updatedAtMs: i64,
    messageCount: usize,
    eventCount: usize,
    taskCount: usize,

    pub fn deinit(self: *AcpSessionSearchItem, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.title);
        allocator.free(self.cwd);
        allocator.free(self.status);
        if (self.sourceSessionId) |value| allocator.free(value);
        allocator.free(self.lastMessage);
        allocator.free(self.snippet);
    }
};

pub const AcpSessionSearchResult = struct {
    query: []const u8,
    sessionId: []const u8,
    status: []const u8,
    count: usize,
    items: []AcpSessionSearchItem,

    pub fn deinit(self: *AcpSessionSearchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.query);
        allocator.free(self.sessionId);
        allocator.free(self.status);
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
    }
};

pub const AcpPromptResult = struct {
    ok: bool,
    session: AcpSessionItem,
    promptText: []const u8,
    promptBlocks: usize,
    taskCount: usize,
    latestEventId: u64,
    tasks: []TaskListItem,
    assistantMessage: AcpMessageItem,
    response: []AcpContentBlock,

    pub fn deinit(self: *AcpPromptResult, allocator: std.mem.Allocator) void {
        self.session.deinit(allocator);
        allocator.free(self.promptText);
        allocator.free(self.tasks);
        self.assistantMessage.deinit(allocator);
        allocator.free(self.response);
    }
};

const AcpPromptText = struct {
    text: []u8,
    blockCount: usize,

    fn deinit(self: *AcpPromptText, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
    }
};

pub const TaskListItem = struct {
    taskId: []const u8,
    sessionId: []const u8,
    status: []const u8,
    goal: []const u8,
    summary: []const u8,
    createdAtMs: i64,
    updatedAtMs: i64,
    totalSteps: usize,
    completedSteps: usize,
    successCount: usize,
    failureCount: usize,
    approvalRequiredCount: usize,
    eventCount: usize,
};

pub const TaskListResult = struct {
    sessionId: []const u8,
    status: []const u8,
    count: usize,
    items: []TaskListItem,

    pub fn deinit(self: *TaskListResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sessionId);
        allocator.free(self.status);
        allocator.free(self.items);
    }
};

pub const TaskGetResult = struct {
    task: TaskListItem,
    context: []const u8,
    cwd: []const u8,
    latestEventId: u64,

    pub fn deinit(self: *TaskGetResult, allocator: std.mem.Allocator) void {
        allocator.free(self.context);
        allocator.free(self.cwd);
    }
};

pub const TaskEventItem = struct {
    eventId: u64,
    taskId: []const u8,
    sessionId: []const u8,
    atMs: i64,
    kind: []const u8,
    stepIndex: ?usize = null,
    toolCallId: ?[]const u8 = null,
    tool: ?[]const u8 = null,
    status: ?[]const u8 = null,
    preview: ?[]const u8 = null,
};

pub const TaskEventsResult = struct {
    taskId: []const u8,
    sessionId: []const u8,
    count: usize,
    cursor: u64,
    hasMore: bool,
    items: []TaskEventItem,

    pub fn deinit(self: *TaskEventsResult, allocator: std.mem.Allocator) void {
        allocator.free(self.taskId);
        allocator.free(self.sessionId);
        allocator.free(self.items);
    }
};

pub const TaskSearchItem = struct {
    taskId: []const u8,
    sessionId: []const u8,
    status: []const u8,
    goal: []const u8,
    summary: []const u8,
    score: f64,
    updatedAtMs: i64,
};

pub const TaskSearchResult = struct {
    query: []const u8,
    sessionId: []const u8,
    count: usize,
    items: []TaskSearchItem,

    pub fn deinit(self: *TaskSearchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.query);
        allocator.free(self.sessionId);
        allocator.free(self.items);
    }
};

pub const Snapshot = struct {
    statePath: []const u8,
    persisted: bool,
    sessions: usize,
    sessionMessages: usize,
    sessionEvents: usize,
    tasks: usize,
    taskEvents: usize,
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
            .sessionMessages = runtime_snapshot.sessionMessages,
            .sessionEvents = runtime_snapshot.sessionEvents,
            .tasks = runtime_snapshot.tasks,
            .taskEvents = runtime_snapshot.taskEvents,
            .queueDepth = runtime_snapshot.pendingJobs,
            .leasedJobs = runtime_snapshot.leasedJobs,
            .recoveryBacklog = runtime_snapshot.recoveryBacklog,
        };
    }

    pub fn snapshotTextAlloc(self: *const ToolRuntime, allocator: std.mem.Allocator) ![]u8 {
        const runtime_snapshot = self.snapshot();
        return std.fmt.allocPrint(
            allocator,
            "state_path={s}\npersisted={d}\nsessions={d}\nsession_messages={d}\nsession_events={d}\ntasks={d}\ntask_events={d}\nqueue_depth={d}\nleased_jobs={d}\nrecovery_backlog={d}\n",
            .{
                runtime_snapshot.statePath,
                @intFromBool(runtime_snapshot.persisted),
                runtime_snapshot.sessions,
                runtime_snapshot.sessionMessages,
                runtime_snapshot.sessionEvents,
                runtime_snapshot.tasks,
                runtime_snapshot.taskEvents,
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

    fn sessionsHistory(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        scope: []const u8,
        limit: usize,
    ) !SessionHistoryResult {
        var items: std.ArrayList(SessionHistoryItem) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }

        var iterator = self.runtime_state.sessions.iterator();
        while (iterator.next()) |entry| {
            const session_id = entry.key_ptr.*;
            const session = entry.value_ptr.*;
            if (scope.len > 0 and !std.mem.eql(u8, session_id, scope)) continue;
            try items.append(allocator, .{
                .sessionId = try allocator.dupe(u8, session_id),
                .createdAtMs = session.created_unix_ms,
                .updatedAtMs = session.updated_unix_ms,
                .lastMessage = try allocator.dupe(u8, session.last_message),
            });
        }

        std.mem.sort(SessionHistoryItem, items.items, {}, struct {
            fn lessThan(_: void, lhs: SessionHistoryItem, rhs: SessionHistoryItem) bool {
                if (lhs.updatedAtMs == rhs.updatedAtMs) return std.mem.lessThan(u8, lhs.sessionId, rhs.sessionId);
                return lhs.updatedAtMs > rhs.updatedAtMs;
            }
        }.lessThan);

        const capped_limit = if (limit == 0) 50 else limit;
        if (items.items.len > capped_limit) {
            for (items.items[capped_limit..]) |*item| item.deinit(allocator);
            items.items.len = capped_limit;
        }

        return .{
            .sessionId = try allocator.dupe(u8, scope),
            .count = items.items.len,
            .items = try items.toOwnedSlice(allocator),
        };
    }

    fn sessionsHistoryFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !SessionHistoryResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const scope = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "scope" }, ""), " \t\r\n");
        const limit = @as(usize, @intCast(getOptionalU32(params, "limit", 50)));
        return self.sessionsHistory(allocator, scope, limit);
    }

    fn sessionsSearch(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        query: []const u8,
        limit: usize,
    ) !SessionSearchResult {
        var items: std.ArrayList(SessionSearchItem) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }

        var iterator = self.runtime_state.sessions.iterator();
        while (iterator.next()) |entry| {
            const session_id = entry.key_ptr.*;
            const session = entry.value_ptr.*;
            const score = sessionSearchScore(session_id, session.last_message, query);
            if (score <= 0) continue;
            try items.append(allocator, .{
                .sessionId = try allocator.dupe(u8, session_id),
                .createdAtMs = session.created_unix_ms,
                .updatedAtMs = session.updated_unix_ms,
                .lastMessage = try allocator.dupe(u8, session.last_message),
                .preview = try allocator.dupe(u8, previewSlice(session.last_message)),
                .score = score,
            });
        }

        std.mem.sort(SessionSearchItem, items.items, {}, struct {
            fn lessThan(_: void, lhs: SessionSearchItem, rhs: SessionSearchItem) bool {
                if (lhs.score == rhs.score) {
                    if (lhs.updatedAtMs == rhs.updatedAtMs) return std.mem.lessThan(u8, lhs.sessionId, rhs.sessionId);
                    return lhs.updatedAtMs > rhs.updatedAtMs;
                }
                return lhs.score > rhs.score;
            }
        }.lessThan);

        const capped_limit = if (limit == 0) 5 else limit;
        if (items.items.len > capped_limit) {
            for (items.items[capped_limit..]) |*item| item.deinit(allocator);
            items.items.len = capped_limit;
        }

        return .{
            .query = try allocator.dupe(u8, query),
            .count = items.items.len,
            .items = try items.toOwnedSlice(allocator),
            .neighborCount = 0,
            .neighbors = try allocator.alloc(SessionSearchItem, 0),
        };
    }

    fn sessionsSearchFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !SessionSearchResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const query = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "query", "text" }, ""), " \t\r\n");
        if (query.len == 0) return error.MissingQuery;
        const limit = @as(usize, @intCast(getOptionalU32(params, "limit", 5)));
        return self.sessionsSearch(allocator, query, limit);
    }

    fn taskCountForSession(self: *const ToolRuntime, session_id: []const u8) usize {
        var count: usize = 0;
        for (self.runtime_state.task_receipts.items) |entry| {
            if (std.mem.eql(u8, entry.session_id, session_id)) count += 1;
        }
        return count;
    }

    fn buildAcpSessionItem(
        self: *const ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
    ) !AcpSessionItem {
        const session = self.runtime_state.getSession(session_id) orelse return error.SessionNotFound;
        return .{
            .sessionId = try allocator.dupe(u8, session.id),
            .createdAtMs = session.created_unix_ms,
            .updatedAtMs = session.updated_unix_ms,
            .cwd = try allocator.dupe(u8, session.cwd),
            .title = try allocator.dupe(u8, session.title),
            .sourceSessionId = if (session.source_session_id) |value| try allocator.dupe(u8, value) else null,
            .status = try allocator.dupe(u8, session.status),
            .cancelRequested = session.cancel_requested,
            .lastMessage = try allocator.dupe(u8, session.last_message),
            .messageCount = self.runtime_state.sessionMessageCount(session_id),
            .eventCount = self.runtime_state.sessionEventCount(session_id),
            .taskCount = self.taskCountForSession(session_id),
            .latestMessageId = self.runtime_state.latestSessionMessageId(session_id),
            .latestEventId = self.runtime_state.latestSessionEventId(session_id),
        };
    }

    fn buildAcpMessageItem(
        _: *const ToolRuntime,
        allocator: std.mem.Allocator,
        message: *const state.SessionMessage,
    ) !AcpMessageItem {
        return .{
            .messageId = message.message_id,
            .sessionId = try allocator.dupe(u8, message.session_id),
            .role = try allocator.dupe(u8, message.role),
            .kind = try allocator.dupe(u8, message.kind),
            .text = try allocator.dupe(u8, message.text),
            .taskId = if (message.task_id) |value| try allocator.dupe(u8, value) else null,
            .createdAtMs = message.created_unix_ms,
        };
    }

    fn buildAcpSessionEventItem(
        _: *const ToolRuntime,
        allocator: std.mem.Allocator,
        event: *const state.SessionEvent,
    ) !AcpSessionEventItem {
        return .{
            .eventId = event.event_id,
            .sessionId = try allocator.dupe(u8, event.session_id),
            .taskId = if (event.task_id) |value| try allocator.dupe(u8, value) else null,
            .messageId = event.message_id,
            .atMs = event.at_unix_ms,
            .kind = try allocator.dupe(u8, event.kind),
            .role = if (event.role) |value| try allocator.dupe(u8, value) else null,
            .toolCallId = if (event.tool_call_id) |value| try allocator.dupe(u8, value) else null,
            .tool = if (event.tool) |value| try allocator.dupe(u8, value) else null,
            .toolKind = if (event.tool_kind) |value| try allocator.dupe(u8, value) else null,
            .status = if (event.status) |value| try allocator.dupe(u8, value) else null,
            .preview = if (event.preview) |value| try allocator.dupe(u8, value) else null,
        };
    }


    fn appendAcpAuthMethod(
        allocator: std.mem.Allocator,
        items: *std.ArrayList(AcpAuthMethod),
        id: []const u8,
        name: []const u8,
        description: []const u8,
    ) !void {
        try items.append(allocator, .{
            .id = try allocator.dupe(u8, id),
            .name = try allocator.dupe(u8, name),
            .description = try allocator.dupe(u8, description),
        });
    }

    fn buildAcpAuthMethods(_: *const ToolRuntime, allocator: std.mem.Allocator) ![]AcpAuthMethod {
        var items: std.ArrayList(AcpAuthMethod) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }

        try appendAcpAuthMethod(
            allocator,
            &items,
            "openai-api-key",
            "OpenAI API key",
            "Use OPENAI_API_KEY or OPENCLAW_ZIG_OPENAI_API_KEY from the current runtime environment when available.",
        );
        try appendAcpAuthMethod(
            allocator,
            &items,
            "anthropic-api-key",
            "Anthropic API key",
            "Use ANTHROPIC_API_KEY or OPENCLAW_ZIG_ANTHROPIC_API_KEY from the current runtime environment when available.",
        );
        try appendAcpAuthMethod(
            allocator,
            &items,
            "google-api-key",
            "Google API key",
            "Use GOOGLE_API_KEY from the current runtime environment when available.",
        );
        return items.toOwnedSlice(allocator);
    }

    fn envVarPresent(io: std.Io, allocator: std.mem.Allocator, name: []const u8) !bool {
        return switch (builtin.os.tag) {
            .freestanding, .wasi => false,
            .linux => blk: {
                const env_blob = pal.fs.readFileAlloc(io, allocator, "/proc/self/environ", 64 * 1024) catch break :blk false;
                defer allocator.free(env_blob);
                var entries = std.mem.splitScalar(u8, env_blob, 0);
                while (entries.next()) |entry| {
                    if (entry.len <= name.len or entry[name.len] != '=') continue;
                    if (!std.mem.eql(u8, entry[0..name.len], name)) continue;
                    break :blk entry.len > name.len + 1;
                }
                break :blk false;
            },
            else => false,
        };
    }

    fn acpProviderConfigured(self: *const ToolRuntime, allocator: std.mem.Allocator, provider: []const u8) !bool {
        if (std.mem.eql(u8, provider, "openai")) {
            return (try envVarPresent(self.io, allocator, "OPENAI_API_KEY")) or
                (try envVarPresent(self.io, allocator, "OPENCLAW_ZIG_OPENAI_API_KEY")) or
                (try envVarPresent(self.io, allocator, "OPENCLAW_GO_OPENAI_API_KEY")) or
                (try envVarPresent(self.io, allocator, "OPENCLAW_RS_OPENAI_API_KEY")) or
                (try envVarPresent(self.io, allocator, "OPENCLAW_ZIG_BROWSER_OPENAI_API_KEY"));
        }
        if (std.mem.eql(u8, provider, "anthropic")) {
            return (try envVarPresent(self.io, allocator, "ANTHROPIC_API_KEY")) or
                (try envVarPresent(self.io, allocator, "OPENCLAW_ZIG_ANTHROPIC_API_KEY")) or
                (try envVarPresent(self.io, allocator, "OPENCLAW_GO_ANTHROPIC_API_KEY")) or
                (try envVarPresent(self.io, allocator, "OPENCLAW_RS_ANTHROPIC_API_KEY")) or
                (try envVarPresent(self.io, allocator, "OPENCLAW_ZIG_BROWSER_ANTHROPIC_API_KEY"));
        }
        if (std.mem.eql(u8, provider, "google")) {
            return try envVarPresent(self.io, allocator, "GOOGLE_API_KEY");
        }
        return false;
    }

    fn acpUpdateTypeForKind(kind: []const u8) []const u8 {
        if (std.mem.startsWith(u8, kind, "message.")) return "message";
        if (std.mem.startsWith(u8, kind, "session.")) return "session";
        if (std.mem.startsWith(u8, kind, "task.")) return "task";
        if (std.mem.startsWith(u8, kind, "tool.")) return "task";
        if (std.mem.eql(u8, kind, "approval_required")) return "task";
        return "event";
    }

    fn buildAcpSessionUpdateItem(
        _: *const ToolRuntime,
        allocator: std.mem.Allocator,
        event: *const state.SessionEvent,
    ) !AcpSessionUpdateItem {
        const update_type = acpUpdateTypeForKind(event.kind);
        return .{
            .updateId = event.event_id,
            .sessionId = try allocator.dupe(u8, event.session_id),
            .taskId = if (event.task_id) |value| try allocator.dupe(u8, value) else null,
            .messageId = event.message_id,
            .atMs = event.at_unix_ms,
            .type = try allocator.dupe(u8, update_type),
            .kind = try allocator.dupe(u8, event.kind),
            .role = if (event.role) |value| try allocator.dupe(u8, value) else null,
            .status = if (event.status) |value| try allocator.dupe(u8, value) else null,
            .toolCallId = if (event.tool_call_id) |value| try allocator.dupe(u8, value) else null,
            .tool = if (event.tool) |value| try allocator.dupe(u8, value) else null,
            .toolKind = if (event.tool_kind) |value| try allocator.dupe(u8, value) else null,
            .title = try allocator.dupe(u8, event.kind),
            .text = if (event.preview) |value| try allocator.dupe(u8, value) else null,
        };
    }

    fn buildTaskListItemFromSnapshot(self: *const ToolRuntime, receipt: state.TaskReceiptSnapshot) TaskListItem {
        return .{
            .taskId = receipt.task_id,
            .sessionId = receipt.session_id,
            .status = receipt.status,
            .goal = receipt.goal,
            .summary = receipt.summary,
            .createdAtMs = receipt.created_unix_ms,
            .updatedAtMs = receipt.updated_unix_ms,
            .totalSteps = receipt.total_steps,
            .completedSteps = receipt.completed_steps,
            .successCount = receipt.success_count,
            .failureCount = receipt.failure_count,
            .approvalRequiredCount = receipt.approval_required_count,
            .eventCount = self.taskEventCountForTask(receipt.task_id),
        };
    }

    fn acpSessionsList(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        limit: usize,
    ) !AcpSessionsListResult {
        var items: std.ArrayList(AcpSessionItem) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }

        var iterator = self.runtime_state.sessions.iterator();
        while (iterator.next()) |entry| {
            try items.append(allocator, try self.buildAcpSessionItem(allocator, entry.key_ptr.*));
        }

        std.mem.sort(AcpSessionItem, items.items, {}, struct {
            fn lessThan(_: void, lhs: AcpSessionItem, rhs: AcpSessionItem) bool {
                if (lhs.updatedAtMs == rhs.updatedAtMs) return std.mem.lessThan(u8, lhs.sessionId, rhs.sessionId);
                return lhs.updatedAtMs > rhs.updatedAtMs;
            }
        }.lessThan);

        const capped_limit = if (limit == 0) 25 else limit;
        if (items.items.len > capped_limit) {
            for (items.items[capped_limit..]) |*item| item.deinit(allocator);
            items.items.len = capped_limit;
        }

        return .{
            .count = items.items.len,
            .items = try items.toOwnedSlice(allocator),
        };
    }

    fn acpSessionsListFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpSessionsListResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const limit = @as(usize, @intCast(getOptionalU32(params, "limit", 25)));
        return self.acpSessionsList(allocator, limit);
    }

    fn acpSessionGet(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
    ) !AcpSessionGetResult {
        return .{ .session = try self.buildAcpSessionItem(allocator, session_id) };
    }

    fn acpSessionGetFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpSessionGetResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const session_id = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "session" }, ""), " \t\r\n");
        if (session_id.len == 0) return error.MissingSessionId;
        return self.acpSessionGet(allocator, session_id);
    }

    fn acpSessionNewFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpSessionNewResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const now_ms = nowUnixMilliseconds(self.io);
        const session_id_raw = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "session" }, ""), " \t\r\n");
        const cwd = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "cwd", "workdir", "workingDirectory" }, ""), " \t\r\n");
        const title = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "title", "sessionTitle" }, ""), " \t\r\n");
        const session_id = if (session_id_raw.len > 0)
            try allocator.dupe(u8, session_id_raw)
        else
            try generateAcpSessionIdAlloc(allocator, now_ms, self.runtime_state.next_session_message_id);
        defer allocator.free(session_id);
        const created = self.runtime_state.getSession(session_id) == null;
        try self.runtime_state.ensureSessionMeta(session_id, cwd, title, null, now_ms);
        try self.runtime_state.setSessionStatus(session_id, "idle", false, now_ms);
        _ = try self.runtime_state.recordSessionEvent(session_id, null, null, now_ms, if (created) "session.new" else "session.update", null, null, null, null, "ready", if (title.len > 0) title else session_id);
        return .{ .created = created, .session = try self.buildAcpSessionItem(allocator, session_id) };
    }

    fn acpSessionLoadFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpSessionLoadResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const session_id = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "session" }, ""), " \t\r\n");
        if (session_id.len == 0) return error.MissingSessionId;
        if (self.runtime_state.getSession(session_id) == null) return error.SessionNotFound;

        const now_ms = nowUnixMilliseconds(self.io);
        const cwd = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "cwd", "workdir", "workingDirectory" }, ""), " \t\r\n");
        const title = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "title", "sessionTitle" }, ""), " \t\r\n");
        try self.runtime_state.ensureSessionMeta(session_id, cwd, title, null, now_ms);
        _ = try self.runtime_state.recordSessionEvent(session_id, null, null, now_ms, "session.load", null, null, null, null, "loaded", if (title.len > 0) title else session_id);
        return .{ .loaded = true, .session = try self.buildAcpSessionItem(allocator, session_id) };
    }

    fn acpSessionResumeFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpSessionResumeResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const now_ms = nowUnixMilliseconds(self.io);
        const session_id_raw = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "session" }, ""), " \t\r\n");
        const cwd = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "cwd", "workdir", "workingDirectory" }, ""), " \t\r\n");
        const title = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "title", "sessionTitle" }, ""), " \t\r\n");
        const session_id = if (session_id_raw.len > 0)
            try allocator.dupe(u8, session_id_raw)
        else
            try generateAcpSessionIdAlloc(allocator, now_ms, self.runtime_state.next_session_message_id);
        defer allocator.free(session_id);

        const created = self.runtime_state.getSession(session_id) == null;
        try self.runtime_state.ensureSessionMeta(session_id, cwd, title, null, now_ms);
        try self.runtime_state.setSessionStatus(session_id, "idle", false, now_ms);
        _ = try self.runtime_state.recordSessionEvent(session_id, null, null, now_ms, "session.resume", null, null, null, null, "ready", if (title.len > 0) title else session_id);
        return .{ .created = created, .session = try self.buildAcpSessionItem(allocator, session_id) };
    }

    fn acpSessionMessages(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        after_message_id: u64,
        limit: usize,
    ) !AcpSessionMessagesResult {
        if (self.runtime_state.getSession(session_id) == null) return error.SessionNotFound;

        var items: std.ArrayList(AcpMessageItem) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }

        const capped_limit = if (limit == 0) 100 else limit;
        var cursor = after_message_id;
        var has_more = false;

        for (self.runtime_state.session_messages.items) |*entry| {
            if (!std.mem.eql(u8, entry.session_id, session_id)) continue;
            if (entry.message_id <= after_message_id) continue;
            if (items.items.len < capped_limit) {
                try items.append(allocator, try self.buildAcpMessageItem(allocator, entry));
                cursor = entry.message_id;
            } else {
                has_more = true;
                break;
            }
        }

        return .{
            .sessionId = try allocator.dupe(u8, session_id),
            .count = items.items.len,
            .cursor = cursor,
            .hasMore = has_more,
            .items = try items.toOwnedSlice(allocator),
        };
    }

    fn acpSessionMessagesFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpSessionMessagesResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const session_id = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "session" }, ""), " \t\r\n");
        if (session_id.len == 0) return error.MissingSessionId;
        const after_message_id = getOptionalU64(params, "afterMessageId", getOptionalU64(params, "cursor", 0));
        const limit = @as(usize, @intCast(getOptionalU32(params, "limit", 100)));
        return self.acpSessionMessages(allocator, session_id, after_message_id, limit);
    }

    fn acpSessionEvents(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        after_event_id: u64,
        limit: usize,
    ) !AcpSessionEventsResult {
        if (self.runtime_state.getSession(session_id) == null) return error.SessionNotFound;

        var items: std.ArrayList(AcpSessionEventItem) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }

        const capped_limit = if (limit == 0) 100 else limit;
        var cursor = after_event_id;
        var has_more = false;

        for (self.runtime_state.session_events.items) |*entry| {
            if (!std.mem.eql(u8, entry.session_id, session_id)) continue;
            if (entry.event_id <= after_event_id) continue;
            if (items.items.len < capped_limit) {
                try items.append(allocator, try self.buildAcpSessionEventItem(allocator, entry));
                cursor = entry.event_id;
            } else {
                has_more = true;
                break;
            }
        }

        return .{
            .sessionId = try allocator.dupe(u8, session_id),
            .count = items.items.len,
            .cursor = cursor,
            .hasMore = has_more,
            .items = try items.toOwnedSlice(allocator),
        };
    }

    fn acpSessionEventsFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpSessionEventsResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const session_id = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "session" }, ""), " \t\r\n");
        if (session_id.len == 0) return error.MissingSessionId;
        const after_event_id = getOptionalU64(params, "afterEventId", getOptionalU64(params, "cursor", 0));
        const limit = @as(usize, @intCast(getOptionalU32(params, "limit", 100)));
        return self.acpSessionEvents(allocator, session_id, after_event_id, limit);
    }

    fn acpInitialize(self: *ToolRuntime, allocator: std.mem.Allocator) !AcpInitializeResult {
        const auth_methods = try self.buildAcpAuthMethods(allocator);
        return .{
            .protocolVersion = 1,
            .agentInfo = .{
                .name = "openclaw-zig",
                .displayName = "ZAR / OpenClaw Zig Runtime",
                .version = "v11-port",
                .description = "Hermes-guided ACP handshake, approvals, and portable session/task/event surfaces for the Zig runtime.",
            },
            .agentCapabilities = .{
                .sessionCapabilities = .{
                    .fork = true,
                    .list = true,
                    .updates = true,
                    .search = true,
                },
                .prompt = true,
                .approvals = true,
                .contentBlocks = .{
                    .text = true,
                    .image = false,
                    .audio = false,
                    .resource = false,
                },
            },
            .runtimeTarget = tool_contract.currentRuntimeTargetLabel(builtin.os.tag),
            .authMethodCount = auth_methods.len,
            .authMethods = auth_methods,
        };
    }

    fn acpInitializeFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpInitializeResult {
        _ = frame_json;
        return self.acpInitialize(allocator);
    }

    fn acpAuthenticateFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpAuthenticateResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const requested_method_id = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "methodId", "method", "id" }, ""), " \t\r\n");
        const requested_provider = std.mem.trim(u8, getOptionalString(params, "provider", ""), " \t\r\n");

        var method_id: []const u8 = requested_method_id;
        var provider: []const u8 = requested_provider;

        if (method_id.len == 0 and provider.len == 0) {
            if (try self.acpProviderConfigured(allocator, "openai")) {
                method_id = "openai-api-key";
                provider = "openai";
            } else if (try self.acpProviderConfigured(allocator, "anthropic")) {
                method_id = "anthropic-api-key";
                provider = "anthropic";
            } else if (try self.acpProviderConfigured(allocator, "google")) {
                method_id = "google-api-key";
                provider = "google";
            } else {
                method_id = "openai-api-key";
                provider = "openai";
            }
        } else if (method_id.len == 0) {
            if (std.ascii.eqlIgnoreCase(provider, "anthropic")) {
                method_id = "anthropic-api-key";
                provider = "anthropic";
            } else if (std.ascii.eqlIgnoreCase(provider, "google")) {
                method_id = "google-api-key";
                provider = "google";
            } else {
                method_id = "openai-api-key";
                provider = if (provider.len > 0) provider else "openai";
            }
        } else if (provider.len == 0) {
            if (std.ascii.eqlIgnoreCase(method_id, "anthropic-api-key")) {
                provider = "anthropic";
            } else if (std.ascii.eqlIgnoreCase(method_id, "google-api-key")) {
                provider = "google";
            } else {
                provider = "openai";
            }
        }

        const normalized_provider = if (std.ascii.eqlIgnoreCase(provider, "anthropic"))
            "anthropic"
        else if (std.ascii.eqlIgnoreCase(provider, "google"))
            "google"
        else if (std.ascii.eqlIgnoreCase(provider, "openai"))
            "openai"
        else
            provider;
        const authenticated = try self.acpProviderConfigured(allocator, normalized_provider);
        const runtime_target = tool_contract.currentRuntimeTargetLabel(builtin.os.tag);
        const message = if (authenticated)
            try std.fmt.allocPrint(allocator, "{s} credentials are available in the current {s} runtime environment.", .{ normalized_provider, runtime_target })
        else if (builtin.os.tag == .freestanding or builtin.os.tag == .wasi)
            try std.fmt.allocPrint(allocator, "No {s} credentials are visible from the current {s} runtime environment.", .{ normalized_provider, runtime_target })
        else
            try std.fmt.allocPrint(allocator, "No {s} credentials are currently configured for the {s} runtime environment.", .{ normalized_provider, runtime_target });

        return .{
            .ok = true,
            .authenticated = authenticated,
            .methodId = try allocator.dupe(u8, method_id),
            .provider = try allocator.dupe(u8, normalized_provider),
            .runtimeTarget = runtime_target,
            .message = message,
        };
    }

    fn acpSessionUpdates(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_id: []const u8,
        after_update_id: u64,
        limit: usize,
    ) !AcpSessionUpdatesResult {
        if (self.runtime_state.getSession(session_id) == null) return error.SessionNotFound;

        var items: std.ArrayList(AcpSessionUpdateItem) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }

        const capped_limit = if (limit == 0) 100 else limit;
        var cursor = after_update_id;
        var has_more = false;

        for (self.runtime_state.session_events.items) |*entry| {
            if (!std.mem.eql(u8, entry.session_id, session_id)) continue;
            if (entry.event_id <= after_update_id) continue;
            if (items.items.len < capped_limit) {
                try items.append(allocator, try self.buildAcpSessionUpdateItem(allocator, entry));
                cursor = entry.event_id;
            } else {
                has_more = true;
                break;
            }
        }

        return .{
            .sessionId = try allocator.dupe(u8, session_id),
            .count = items.items.len,
            .cursor = cursor,
            .hasMore = has_more,
            .items = try items.toOwnedSlice(allocator),
        };
    }

    fn acpSessionUpdatesFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpSessionUpdatesResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const session_id = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "session" }, ""), " \t\r\n");
        if (session_id.len == 0) return error.MissingSessionId;
        const after_update_id = getOptionalU64(params, "afterUpdateId", getOptionalU64(params, "afterEventId", getOptionalU64(params, "cursor", 0)));
        const limit = @as(usize, @intCast(getOptionalU32(params, "limit", 100)));
        return self.acpSessionUpdates(allocator, session_id, after_update_id, limit);
    }

    fn acpSessionSearch(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        query: []const u8,
        session_scope: []const u8,
        status_filter: []const u8,
        limit: usize,
    ) !AcpSessionSearchResult {
        const trimmed = std.mem.trim(u8, query, " \t\r\n");
        if (trimmed.len == 0) return error.MissingQuery;
        if (session_scope.len > 0 and self.runtime_state.getSession(session_scope) == null) return error.SessionNotFound;

        const score_text = struct {
            fn call(text: []const u8, query_inner: []const u8, direct_weight: f64, token_weight: f64) f64 {
                if (text.len == 0) return 0;
                var score: f64 = 0;
                if (std.ascii.indexOfIgnoreCase(text, query_inner) != null) score += direct_weight;
                var token_it = std.mem.tokenizeAny(u8, query_inner, " \t\r\n");
                while (token_it.next()) |token| {
                    if (token.len == 0 or std.mem.eql(u8, token, query_inner)) continue;
                    if (std.ascii.indexOfIgnoreCase(text, token) != null) score += token_weight;
                }
                return score;
            }
        }.call;

        var items: std.ArrayList(AcpSessionSearchItem) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }

        var iterator = self.runtime_state.sessions.iterator();
        while (iterator.next()) |entry| {
            const session_id = entry.key_ptr.*;
            const session = entry.value_ptr.*;
            if (session_scope.len > 0 and !std.mem.eql(u8, session_id, session_scope)) continue;
            if (status_filter.len > 0 and !std.ascii.eqlIgnoreCase(session.status, status_filter)) continue;

            var score: f64 = 0;
            var snippet_text: []const u8 = session.last_message;
            var snippet_score: f64 = 0;

            const session_id_score = score_text(session_id, trimmed, 1.0, 0.25);
            score += session_id_score;
            if (session_id_score > snippet_score) {
                snippet_score = session_id_score;
                snippet_text = session_id;
            }

            const title_score = score_text(session.title, trimmed, 3.5, 0.75);
            score += title_score;
            if (title_score > snippet_score) {
                snippet_score = title_score;
                snippet_text = session.title;
            }

            const cwd_score = score_text(session.cwd, trimmed, 1.25, 0.25);
            score += cwd_score;
            if (cwd_score > snippet_score) {
                snippet_score = cwd_score;
                snippet_text = session.cwd;
            }

            const status_score = score_text(session.status, trimmed, 0.75, 0.2);
            score += status_score;
            if (status_score > snippet_score) {
                snippet_score = status_score;
                snippet_text = session.status;
            }

            if (session.source_session_id) |value| {
                const source_score = score_text(value, trimmed, 1.0, 0.25);
                score += source_score;
                if (source_score > snippet_score) {
                    snippet_score = source_score;
                    snippet_text = value;
                }
            }

            const last_message_score = score_text(session.last_message, trimmed, 2.75, 0.6);
            score += last_message_score;
            if (last_message_score > snippet_score) {
                snippet_score = last_message_score;
                snippet_text = session.last_message;
            }

            for (self.runtime_state.session_messages.items) |message| {
                if (!std.mem.eql(u8, message.session_id, session_id)) continue;
                const message_score = score_text(message.text, trimmed, 1.75, 0.35);
                score += message_score;
                if (message_score > snippet_score) {
                    snippet_score = message_score;
                    snippet_text = message.text;
                }
            }

            for (self.runtime_state.session_events.items) |event| {
                if (!std.mem.eql(u8, event.session_id, session_id)) continue;
                if (event.preview) |preview| {
                    const preview_score = score_text(preview, trimmed, 1.0, 0.25);
                    score += preview_score;
                    if (preview_score > snippet_score) {
                        snippet_score = preview_score;
                        snippet_text = preview;
                    }
                }
                const kind_score = score_text(event.kind, trimmed, 0.4, 0.1);
                score += kind_score;
            }

            for (self.runtime_state.task_receipts.items) |task| {
                if (!std.mem.eql(u8, task.session_id, session_id)) continue;
                const goal_score = score_text(task.goal, trimmed, 1.5, 0.35);
                const summary_score = score_text(task.summary, trimmed, 2.0, 0.4);
                const context_score = score_text(task.context, trimmed, 1.0, 0.25);
                score += goal_score + summary_score + context_score;
                if (summary_score >= goal_score and summary_score >= context_score and summary_score > snippet_score) {
                    snippet_score = summary_score;
                    snippet_text = task.summary;
                } else if (goal_score >= context_score and goal_score > snippet_score) {
                    snippet_score = goal_score;
                    snippet_text = task.goal;
                } else if (context_score > snippet_score) {
                    snippet_score = context_score;
                    snippet_text = task.context;
                }
            }

            if (score <= 0) continue;

            try items.append(allocator, .{
                .sessionId = try allocator.dupe(u8, session_id),
                .title = try allocator.dupe(u8, if (session.title.len > 0) session.title else session_id),
                .cwd = try allocator.dupe(u8, session.cwd),
                .status = try allocator.dupe(u8, session.status),
                .sourceSessionId = if (session.source_session_id) |value| try allocator.dupe(u8, value) else null,
                .lastMessage = try allocator.dupe(u8, session.last_message),
                .snippet = try allocator.dupe(u8, previewSlice(snippet_text)),
                .score = score,
                .createdAtMs = session.created_unix_ms,
                .updatedAtMs = session.updated_unix_ms,
                .messageCount = self.runtime_state.sessionMessageCount(session_id),
                .eventCount = self.runtime_state.sessionEventCount(session_id),
                .taskCount = self.taskCountForSession(session_id),
            });
        }

        std.mem.sort(AcpSessionSearchItem, items.items, {}, struct {
            fn lessThan(_: void, lhs: AcpSessionSearchItem, rhs: AcpSessionSearchItem) bool {
                if (lhs.score == rhs.score) {
                    if (lhs.updatedAtMs == rhs.updatedAtMs) return std.mem.lessThan(u8, lhs.sessionId, rhs.sessionId);
                    return lhs.updatedAtMs > rhs.updatedAtMs;
                }
                return lhs.score > rhs.score;
            }
        }.lessThan);

        const capped_limit = if (limit == 0) 10 else limit;
        if (items.items.len > capped_limit) {
            for (items.items[capped_limit..]) |*item| item.deinit(allocator);
            items.items.len = capped_limit;
        }

        return .{
            .query = try allocator.dupe(u8, trimmed),
            .sessionId = try allocator.dupe(u8, session_scope),
            .status = try allocator.dupe(u8, status_filter),
            .count = items.items.len,
            .items = try items.toOwnedSlice(allocator),
        };
    }

    fn acpSessionSearchFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpSessionSearchResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const query = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "query", "text" }, ""), " \t\r\n");
        if (query.len == 0) return error.MissingQuery;
        const session_scope = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "scope" }, ""), " \t\r\n");
        const status_filter = std.mem.trim(u8, getOptionalString(params, "status", ""), " \t\r\n");
        const limit = @as(usize, @intCast(getOptionalU32(params, "limit", 10)));
        return self.acpSessionSearch(allocator, query, session_scope, status_filter, limit);
    }

    fn acpSessionForkFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpSessionForkResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const source_session_id = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sourceSessionId", "sessionId", "session" }, ""), " \t\r\n");
        if (source_session_id.len == 0) return error.MissingSessionId;
        const source = self.runtime_state.getSession(source_session_id) orelse return error.SessionNotFound;
        const now_ms = nowUnixMilliseconds(self.io);
        const dest_session_id_raw = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "newSessionId", "targetSessionId", "targetSession" }, ""), " \t\r\n");
        const dest_session_id = if (dest_session_id_raw.len > 0)
            try allocator.dupe(u8, dest_session_id_raw)
        else
            try generateAcpSessionIdAlloc(allocator, now_ms, self.runtime_state.next_session_message_id);
        defer allocator.free(dest_session_id);

        const cwd_override = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "cwd", "workdir", "workingDirectory" }, ""), " \t\r\n");
        const title_override = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "title", "sessionTitle" }, ""), " \t\r\n");
        const dest_cwd = if (cwd_override.len > 0) cwd_override else source.cwd;
        var generated_title: ?[]u8 = null;
        defer if (generated_title) |value| allocator.free(value);
        const dest_title = if (title_override.len > 0) title_override else blk: {
            generated_title = try std.fmt.allocPrint(allocator, "Fork of {s}", .{if (source.title.len > 0) source.title else source.id});
            break :blk generated_title.?;
        };

        try self.runtime_state.ensureSessionMeta(dest_session_id, dest_cwd, dest_title, source_session_id, now_ms);

        var source_messages: std.ArrayList(state.SessionMessageSnapshot) = .empty;
        defer source_messages.deinit(allocator);
        for (self.runtime_state.session_messages.items) |entry| {
            if (!std.mem.eql(u8, entry.session_id, source_session_id)) continue;
            try source_messages.append(allocator, .{
                .message_id = entry.message_id,
                .session_id = entry.session_id,
                .role = entry.role,
                .kind = entry.kind,
                .text = entry.text,
                .task_id = entry.task_id,
                .created_unix_ms = entry.created_unix_ms,
            });
        }

        var cloned_messages: usize = 0;
        for (source_messages.items) |entry| {
            _ = try self.runtime_state.appendSessionMessage(dest_session_id, entry.role, entry.kind, entry.text, entry.task_id, now_ms);
            cloned_messages += 1;
        }

        _ = try self.runtime_state.recordSessionEvent(dest_session_id, null, null, now_ms, "session.fork", null, null, null, null, "forked", source_session_id);

        return .{
            .sourceSessionId = try allocator.dupe(u8, source_session_id),
            .clonedMessages = cloned_messages,
            .session = try self.buildAcpSessionItem(allocator, dest_session_id),
        };
    }

    fn acpSessionCancelFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpSessionCancelResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const session_id = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "session" }, ""), " \t\r\n");
        if (session_id.len == 0) return error.MissingSessionId;
        if (self.runtime_state.getSession(session_id) == null) return error.SessionNotFound;

        const now_ms = nowUnixMilliseconds(self.io);
        try self.runtime_state.setSessionStatus(session_id, "cancel_requested", true, now_ms);
        _ = try self.runtime_state.recordSessionEvent(session_id, null, null, now_ms, "session.cancel", null, null, null, null, "cancel_requested", session_id);
        return .{ .cancelRequested = true, .session = try self.buildAcpSessionItem(allocator, session_id) };
    }

    fn acpPromptFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !AcpPromptResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        var prompt_text = try extractAcpPromptTextAlloc(allocator, params);
        defer prompt_text.deinit(allocator);
        const has_delegated_work = paramsHasDelegatedWork(params);
        const goal = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "goal", "title" }, ""), " \t\r\n");
        if (prompt_text.text.len == 0) {
            if (goal.len > 0) {
                allocator.free(prompt_text.text);
                prompt_text.text = try allocator.dupe(u8, goal);
                if (prompt_text.blockCount == 0) prompt_text.blockCount = 1;
            } else if (has_delegated_work) {
                allocator.free(prompt_text.text);
                prompt_text.text = try allocator.dupe(u8, "ACP delegated task");
                prompt_text.blockCount = 1;
            } else {
                return error.MissingContent;
            }
        }

        const now_ms = nowUnixMilliseconds(self.io);
        const cwd = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "cwd", "workdir", "workingDirectory" }, ""), " \t\r\n");
        const title = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "title", "sessionTitle" }, ""), " \t\r\n");
        const session_id_raw = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "session" }, ""), " \t\r\n");
        const session_id = if (session_id_raw.len > 0)
            try allocator.dupe(u8, session_id_raw)
        else
            try generateAcpSessionIdAlloc(allocator, now_ms, self.runtime_state.next_session_message_id);
        defer allocator.free(session_id);

        try self.runtime_state.ensureSessionMeta(session_id, cwd, title, null, now_ms);
        if (self.runtime_state.sessionCancelRequested(session_id)) return error.SessionCancelled;
        try self.runtime_state.setSessionStatus(session_id, if (has_delegated_work) "running" else "active", false, now_ms);
        const user_message_id = try self.runtime_state.appendSessionMessage(session_id, "user", "prompt", prompt_text.text, null, now_ms);
        _ = try self.runtime_state.recordSessionEvent(session_id, null, user_message_id, now_ms, "message.user", "user", null, null, null, if (has_delegated_work) "running" else "recorded", prompt_text.text);

        var ok_result = true;
        var task_items = try allocator.alloc(TaskListItem, 0);
        var task_count: usize = 0;
        var assistant_text = try allocator.dupe(u8, "Prompt recorded in the ACP session. Add steps/actions/toolsets to execute a Hermes-style tool flow in Zig.");
        errdefer allocator.free(assistant_text);
        var assistant_kind: []const u8 = "message";
        var assistant_task_id: ?[]const u8 = null;
        var session_status: []const u8 = "idle";

        if (has_delegated_work) {
            allocator.free(assistant_text);
            const delegate_invoke = struct {
                fn call(runtime: *ToolRuntime, allocator_inner: std.mem.Allocator, frame_inner: []const u8) anyerror![]u8 {
                    return runtime.handleRpcFrameAlloc(allocator_inner, frame_inner);
                }
            }.call;
            var delegate_result = try delegate_task.runWithDefaults(allocator, params.object, .{
                .goal = if (goal.len > 0) goal else prompt_text.text,
                .session_id = session_id,
                .cwd = cwd,
            }, self, delegate_invoke);
            defer delegate_result.deinit(allocator);
            try task_receipts.recordBatch(&self.runtime_state, &delegate_result);
            ok_result = delegate_result.ok;
            task_count = delegate_result.results.len;
            if (delegate_result.blocked > 0) {
                session_status = "awaiting_approval";
            } else if (delegate_result.failed > 0 and delegate_result.succeeded == 0) {
                session_status = "error";
            }
            if (task_count > 0) {
                task_items = try allocator.alloc(TaskListItem, task_count);
                for (delegate_result.results, 0..) |task, idx| {
                    const receipt = self.runtime_state.getTaskReceipt(task.taskId) orelse unreachable;
                    task_items[idx] = self.buildTaskListItemFromSnapshot(receipt);
                }
                assistant_kind = "task_summary";
                assistant_task_id = delegate_result.results[0].taskId;
                if (task_count == 1) {
                    assistant_text = try std.fmt.allocPrint(allocator, "Delegated task {s}: {s}", .{ delegate_result.results[0].taskId, delegate_result.results[0].summary });
                } else {
                    assistant_text = try std.fmt.allocPrint(allocator, "Delegated {d} tasks in session {s} ({d} succeeded, {d} failed, {d} blocked).", .{ task_count, session_id, delegate_result.succeeded, delegate_result.failed, delegate_result.blocked });
                }
            } else {
                assistant_text = try allocator.dupe(u8, "Delegated ACP prompt completed without recorded task receipts.");
            }
        }

        const assistant_now_ms = nowUnixMilliseconds(self.io);
        try self.runtime_state.setSessionStatus(session_id, session_status, false, assistant_now_ms);
        const assistant_message_id = try self.runtime_state.appendSessionMessage(session_id, "assistant", assistant_kind, assistant_text, assistant_task_id, assistant_now_ms);
        _ = try self.runtime_state.recordSessionEvent(
            session_id,
            assistant_task_id,
            assistant_message_id,
            assistant_now_ms,
            if (std.mem.eql(u8, assistant_kind, "task_summary")) "message.task_summary" else "message.assistant",
            "assistant",
            null,
            null,
            null,
            session_status,
            assistant_text,
        );
        const assistant_message = AcpMessageItem{
            .messageId = assistant_message_id,
            .sessionId = try allocator.dupe(u8, session_id),
            .role = try allocator.dupe(u8, "assistant"),
            .kind = try allocator.dupe(u8, assistant_kind),
            .text = try allocator.dupe(u8, assistant_text),
            .taskId = if (assistant_task_id) |value| try allocator.dupe(u8, value) else null,
            .createdAtMs = assistant_now_ms,
        };
        allocator.free(assistant_text);

        var response_blocks = try allocator.alloc(AcpContentBlock, 1);
        response_blocks[0] = .{ .type = "text", .text = assistant_message.text };

        return .{
            .ok = ok_result,
            .session = try self.buildAcpSessionItem(allocator, session_id),
            .promptText = try allocator.dupe(u8, prompt_text.text),
            .promptBlocks = prompt_text.blockCount,
            .taskCount = task_count,
            .latestEventId = self.runtime_state.latestSessionEventId(session_id),
            .tasks = task_items,
            .assistantMessage = assistant_message,
            .response = response_blocks,
        };
    }
    fn taskEventCountForTask(self: *const ToolRuntime, task_id: []const u8) usize {
        var count: usize = 0;
        for (self.runtime_state.task_events.items) |entry| {
            if (std.mem.eql(u8, entry.task_id, task_id)) count += 1;
        }
        return count;
    }

    fn latestTaskEventId(self: *const ToolRuntime, task_id: []const u8) u64 {
        var latest: u64 = 0;
        for (self.runtime_state.task_events.items) |entry| {
            if (!std.mem.eql(u8, entry.task_id, task_id)) continue;
            if (entry.event_id > latest) latest = entry.event_id;
        }
        return latest;
    }

    fn buildTaskListItem(self: *const ToolRuntime, receipt: *const state.TaskReceipt) TaskListItem {
        return .{
            .taskId = receipt.task_id,
            .sessionId = receipt.session_id,
            .status = receipt.status,
            .goal = receipt.goal,
            .summary = receipt.summary,
            .createdAtMs = receipt.created_unix_ms,
            .updatedAtMs = receipt.updated_unix_ms,
            .totalSteps = receipt.total_steps,
            .completedSteps = receipt.completed_steps,
            .successCount = receipt.success_count,
            .failureCount = receipt.failure_count,
            .approvalRequiredCount = receipt.approval_required_count,
            .eventCount = self.taskEventCountForTask(receipt.task_id),
        };
    }

    fn tasksList(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        session_scope: []const u8,
        status_filter: []const u8,
        limit: usize,
    ) !TaskListResult {
        var items: std.ArrayList(TaskListItem) = .empty;
        defer items.deinit(allocator);

        for (self.runtime_state.task_receipts.items) |*entry| {
            if (session_scope.len > 0 and !std.mem.eql(u8, entry.session_id, session_scope)) continue;
            if (status_filter.len > 0 and !std.ascii.eqlIgnoreCase(entry.status, status_filter)) continue;
            try items.append(allocator, self.buildTaskListItem(entry));
        }

        std.mem.sort(TaskListItem, items.items, {}, struct {
            fn lessThan(_: void, lhs: TaskListItem, rhs: TaskListItem) bool {
                if (lhs.updatedAtMs == rhs.updatedAtMs) return std.mem.lessThan(u8, lhs.taskId, rhs.taskId);
                return lhs.updatedAtMs > rhs.updatedAtMs;
            }
        }.lessThan);

        const capped_limit = if (limit == 0) 25 else limit;
        if (items.items.len > capped_limit) items.items.len = capped_limit;

        return .{
            .sessionId = try allocator.dupe(u8, session_scope),
            .status = try allocator.dupe(u8, status_filter),
            .count = items.items.len,
            .items = try items.toOwnedSlice(allocator),
        };
    }

    fn tasksListFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !TaskListResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const session_scope = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "scope" }, ""), " \t\r\n");
        const status_filter = std.mem.trim(u8, getOptionalString(params, "status", ""), " \t\r\n");
        const limit = @as(usize, @intCast(getOptionalU32(params, "limit", 25)));
        return self.tasksList(allocator, session_scope, status_filter, limit);
    }

    fn tasksGet(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        task_id: []const u8,
    ) !TaskGetResult {
        const receipt = self.runtime_state.getTaskReceipt(task_id) orelse return error.TaskNotFound;
        return .{
            .task = .{
                .taskId = receipt.task_id,
                .sessionId = receipt.session_id,
                .status = receipt.status,
                .goal = receipt.goal,
                .summary = receipt.summary,
                .createdAtMs = receipt.created_unix_ms,
                .updatedAtMs = receipt.updated_unix_ms,
                .totalSteps = receipt.total_steps,
                .completedSteps = receipt.completed_steps,
                .successCount = receipt.success_count,
                .failureCount = receipt.failure_count,
                .approvalRequiredCount = receipt.approval_required_count,
                .eventCount = self.taskEventCountForTask(receipt.task_id),
            },
            .context = try allocator.dupe(u8, receipt.context),
            .cwd = try allocator.dupe(u8, receipt.cwd),
            .latestEventId = self.latestTaskEventId(receipt.task_id),
        };
    }

    fn tasksGetFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !TaskGetResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const task_id = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "taskId", "id" }, ""), " \t\r\n");
        if (task_id.len == 0) return error.MissingTaskId;
        return self.tasksGet(allocator, task_id);
    }

    fn tasksEvents(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        task_id: []const u8,
        session_scope: []const u8,
        after_event_id: u64,
        limit: usize,
    ) !TaskEventsResult {
        if (task_id.len == 0 and session_scope.len == 0) return error.InvalidParamsFrame;

        var items: std.ArrayList(TaskEventItem) = .empty;
        defer items.deinit(allocator);

        const capped_limit = if (limit == 0) 100 else limit;
        var cursor = after_event_id;
        var has_more = false;

        for (self.runtime_state.task_events.items) |entry| {
            if (task_id.len > 0 and !std.mem.eql(u8, entry.task_id, task_id)) continue;
            if (session_scope.len > 0 and !std.mem.eql(u8, entry.session_id, session_scope)) continue;
            if (entry.event_id <= after_event_id) continue;

            if (items.items.len < capped_limit) {
                try items.append(allocator, .{
                    .eventId = entry.event_id,
                    .taskId = entry.task_id,
                    .sessionId = entry.session_id,
                    .atMs = entry.at_unix_ms,
                    .kind = entry.kind,
                    .stepIndex = entry.step_index,
                    .toolCallId = entry.tool_call_id,
                    .tool = entry.tool,
                    .status = entry.status,
                    .preview = entry.preview,
                });
                cursor = entry.event_id;
            } else {
                has_more = true;
                break;
            }
        }

        return .{
            .taskId = try allocator.dupe(u8, task_id),
            .sessionId = try allocator.dupe(u8, session_scope),
            .count = items.items.len,
            .cursor = cursor,
            .hasMore = has_more,
            .items = try items.toOwnedSlice(allocator),
        };
    }

    fn tasksEventsFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !TaskEventsResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const task_id = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "taskId", "id" }, ""), " \t\r\n");
        const session_scope = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "scope" }, ""), " \t\r\n");
        const after_event_id = getOptionalU64(params, "afterEventId", getOptionalU64(params, "cursor", 0));
        const limit = @as(usize, @intCast(getOptionalU32(params, "limit", 100)));
        return self.tasksEvents(allocator, task_id, session_scope, after_event_id, limit);
    }

    fn tasksSearchScore(receipt: *const state.TaskReceipt, query: []const u8) f64 {
        const trimmed = std.mem.trim(u8, query, " \t\r\n");
        if (trimmed.len == 0) return 0;

        var score: f64 = 0;
        if (std.ascii.indexOfIgnoreCase(receipt.goal, trimmed) != null) score += 3.0;
        if (std.ascii.indexOfIgnoreCase(receipt.summary, trimmed) != null) score += 2.5;
        if (std.ascii.indexOfIgnoreCase(receipt.context, trimmed) != null) score += 2.0;
        if (std.ascii.indexOfIgnoreCase(receipt.session_id, trimmed) != null) score += 1.0;
        if (std.ascii.indexOfIgnoreCase(receipt.status, trimmed) != null) score += 0.5;

        var token_it = std.mem.tokenizeAny(u8, trimmed, " \t\r\n");
        while (token_it.next()) |token| {
            if (token.len == 0 or std.mem.eql(u8, token, trimmed)) continue;
            if (std.ascii.indexOfIgnoreCase(receipt.goal, token) != null) score += 0.75;
            if (std.ascii.indexOfIgnoreCase(receipt.summary, token) != null) score += 0.5;
            if (std.ascii.indexOfIgnoreCase(receipt.context, token) != null) score += 0.25;
            if (std.ascii.indexOfIgnoreCase(receipt.session_id, token) != null) score += 0.25;
        }
        return score;
    }

    fn tasksSearch(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        query: []const u8,
        session_scope: []const u8,
        limit: usize,
    ) !TaskSearchResult {
        var items: std.ArrayList(TaskSearchItem) = .empty;
        defer items.deinit(allocator);

        for (self.runtime_state.task_receipts.items) |*entry| {
            if (session_scope.len > 0 and !std.mem.eql(u8, entry.session_id, session_scope)) continue;
            const score = tasksSearchScore(entry, query);
            if (score <= 0) continue;
            try items.append(allocator, .{
                .taskId = entry.task_id,
                .sessionId = entry.session_id,
                .status = entry.status,
                .goal = entry.goal,
                .summary = entry.summary,
                .score = score,
                .updatedAtMs = entry.updated_unix_ms,
            });
        }

        std.mem.sort(TaskSearchItem, items.items, {}, struct {
            fn lessThan(_: void, lhs: TaskSearchItem, rhs: TaskSearchItem) bool {
                if (lhs.score == rhs.score) {
                    if (lhs.updatedAtMs == rhs.updatedAtMs) return std.mem.lessThan(u8, lhs.taskId, rhs.taskId);
                    return lhs.updatedAtMs > rhs.updatedAtMs;
                }
                return lhs.score > rhs.score;
            }
        }.lessThan);

        const capped_limit = if (limit == 0) 10 else limit;
        if (items.items.len > capped_limit) items.items.len = capped_limit;

        return .{
            .query = try allocator.dupe(u8, query),
            .sessionId = try allocator.dupe(u8, session_scope),
            .count = items.items.len,
            .items = try items.toOwnedSlice(allocator),
        };
    }

    fn tasksSearchFromFrame(
        self: *ToolRuntime,
        allocator: std.mem.Allocator,
        frame_json: []const u8,
    ) !TaskSearchResult {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
        defer parsed.deinit();

        const params = try getParamsObject(parsed.value);
        const query = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "query", "text" }, ""), " \t\r\n");
        if (query.len == 0) return error.MissingQuery;
        const session_scope = std.mem.trim(u8, getOptionalStringAliases(params, &.{ "sessionId", "scope" }, ""), " \t\r\n");
        const limit = @as(usize, @intCast(getOptionalU32(params, "limit", 10)));
        return self.tasksSearch(allocator, query, session_scope, limit);
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

        if (std.mem.eql(u8, request.method, "acp.describe")) {
            const tools = tool_contract.runtimeCatalogEntries(builtin.os.tag);
            const distribution_args = [_][]const u8{"--serve"};
            return envelope.encodeResult(allocator, request.id, .{
                .schemaVersion = 1,
                .agent = .{
                    .name = "openclaw-zig",
                    .displayName = "ZAR / OpenClaw Zig Runtime",
                    .description = "Hermes-guided ACP handshake metadata, portable session/task receipts, and polling-based session and task update delivery for the Zig runtime.",
                    .distribution = .{
                        .type = "command",
                        .command = "openclaw-zig",
                        .args = distribution_args[0..],
                    },
                },
                .runtimeTarget = tool_contract.currentRuntimeTargetLabel(builtin.os.tag),
                .authentication = .{
                    .initializeMethod = "acp.initialize",
                    .authenticateMethod = "acp.authenticate",
                },
                .eventDelivery = .{
                    .mode = "poll",
                    .eventsMethod = "acp.sessions.events",
                    .updatesMethod = "acp.sessions.updates",
                    .taskEventsMethod = "tasks.events",
                    .receiptsMethod = "tasks.get",
                },
                .sessionLifecycle = .{
                    .newMethod = "acp.sessions.new",
                    .loadMethod = "acp.sessions.load",
                    .resumeMethod = "acp.sessions.resume",
                    .listMethod = "acp.sessions.list",
                    .getMethod = "acp.sessions.get",
                    .messagesMethod = "acp.sessions.messages",
                    .eventsMethod = "acp.sessions.events",
                    .updatesMethod = "acp.sessions.updates",
                    .searchMethod = "acp.sessions.search",
                    .forkMethod = "acp.sessions.fork",
                    .cancelMethod = "acp.sessions.cancel",
                    .promptMethod = "acp.prompt",
                },
                .contentBlocks = .{
                    .text = true,
                    .image = false,
                    .audio = false,
                    .resource = false,
                },
                .capabilities = .{
                    .toolsCatalog = true,
                    .initialize = true,
                    .authenticate = true,
                    .delegateTask = true,
                    .taskReceipts = true,
                    .taskEvents = true,
                    .sessionHistory = true,
                    .sessionSearch = true,
                    .sessionLifecycle = true,
                    .sessionLoad = true,
                    .sessionResume = true,
                    .sessionMessages = true,
                    .sessionEvents = true,
                    .sessionUpdates = true,
                    .acpSessionSearch = true,
                    .sessionFork = true,
                    .sessionCancel = true,
                    .prompt = true,
                    .promptBlocks = true,
                    .approvals = true,
                    .runtimeSupportMetadata = true,
                },
                .tools = tools,
                .count = tools.len,
            });
        }

        if (std.mem.eql(u8, request.method, "acp.initialize")) {
            var initialize_result = self.acpInitializeFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer initialize_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, initialize_result);
        }

        if (std.mem.eql(u8, request.method, "acp.authenticate")) {
            var authenticate_result = self.acpAuthenticateFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer authenticate_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, authenticate_result);
        }

        if (std.mem.eql(u8, request.method, "acp.sessions.list")) {
            var session_list_result = self.acpSessionsListFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer session_list_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, session_list_result);
        }

        if (std.mem.eql(u8, request.method, "acp.sessions.new")) {
            var session_new_result = self.acpSessionNewFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer session_new_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, session_new_result);
        }

        if (std.mem.eql(u8, request.method, "acp.sessions.load")) {
            var session_load_result = self.acpSessionLoadFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer session_load_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, session_load_result);
        }

        if (std.mem.eql(u8, request.method, "acp.sessions.resume")) {
            var session_resume_result = self.acpSessionResumeFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer session_resume_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, session_resume_result);
        }

        if (std.mem.eql(u8, request.method, "acp.sessions.get")) {
            var session_get_result = self.acpSessionGetFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer session_get_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, session_get_result);
        }

        if (std.mem.eql(u8, request.method, "acp.sessions.messages")) {
            var session_messages_result = self.acpSessionMessagesFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer session_messages_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, session_messages_result);
        }

        if (std.mem.eql(u8, request.method, "acp.sessions.events")) {
            var session_events_result = self.acpSessionEventsFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer session_events_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, session_events_result);
        }

        if (std.mem.eql(u8, request.method, "acp.sessions.updates")) {
            var session_updates_result = self.acpSessionUpdatesFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer session_updates_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, session_updates_result);
        }

        if (std.mem.eql(u8, request.method, "acp.sessions.search")) {
            var session_search_result = self.acpSessionSearchFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer session_search_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, session_search_result);
        }

        if (std.mem.eql(u8, request.method, "acp.sessions.fork")) {
            var session_fork_result = self.acpSessionForkFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer session_fork_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, session_fork_result);
        }

        if (std.mem.eql(u8, request.method, "acp.sessions.cancel")) {
            var session_cancel_result = self.acpSessionCancelFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer session_cancel_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, session_cancel_result);
        }

        if (std.mem.eql(u8, request.method, "acp.prompt")) {
            var prompt_result = self.acpPromptFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{ .code = rpcErrorCode(err), .message = @errorName(err) });
            };
            defer prompt_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, prompt_result);
        }

        if (std.mem.eql(u8, request.method, "tools.catalog")) {
            const tools = tool_contract.runtimeCatalogEntries(builtin.os.tag);
            return envelope.encodeResult(allocator, request.id, .{
                .runtimeTarget = tool_contract.currentRuntimeTargetLabel(builtin.os.tag),
                .tools = tools,
                .count = tools.len,
            });
        }

        if (std.mem.eql(u8, request.method, "delegate_task")) {
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, frame_json, .{});
            defer parsed.deinit();
            const params = getParamsObjectOrNull(parsed.value);
            const delegate_invoke = struct {
                fn call(runtime: *ToolRuntime, allocator_inner: std.mem.Allocator, frame_inner: []const u8) anyerror![]u8 {
                    return runtime.handleRpcFrameAlloc(allocator_inner, frame_inner);
                }
            }.call;
            var delegate_result = delegate_task.run(allocator, params, self, delegate_invoke) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer delegate_result.deinit(allocator);
            task_receipts.recordBatch(&self.runtime_state, &delegate_result) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            return envelope.encodeResult(allocator, request.id, delegate_result);
        }

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

        if (std.mem.eql(u8, request.method, "sessions.history")) {
            var history_result = self.sessionsHistoryFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer history_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, history_result);
        }

        if (std.mem.eql(u8, request.method, "sessions.search")) {
            var search_result = self.sessionsSearchFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer search_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, search_result);
        }

        if (std.mem.eql(u8, request.method, "tasks.list")) {
            var list_result = self.tasksListFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer list_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, list_result);
        }

        if (std.mem.eql(u8, request.method, "tasks.get")) {
            var get_result = self.tasksGetFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer get_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, get_result);
        }

        if (std.mem.eql(u8, request.method, "tasks.events")) {
            var events_result = self.tasksEventsFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer events_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, events_result);
        }

        if (std.mem.eql(u8, request.method, "tasks.search")) {
            var task_search_result = self.tasksSearchFromFrame(allocator, frame_json) catch |err| {
                return envelope.encodeError(allocator, request.id, .{
                    .code = rpcErrorCode(err),
                    .message = @errorName(err),
                });
            };
            defer task_search_result.deinit(allocator);
            return envelope.encodeResult(allocator, request.id, task_search_result);
        }

        if (std.mem.eql(u8, request.method, "runtime.snapshot")) {
            const runtime_snapshot = self.snapshot();
            return envelope.encodeResult(allocator, request.id, .{
                .statePath = runtime_snapshot.statePath,
                .persisted = runtime_snapshot.persisted,
                .sessions = runtime_snapshot.sessions,
                .sessionMessages = runtime_snapshot.sessionMessages,
                .sessionEvents = runtime_snapshot.sessionEvents,
                .tasks = runtime_snapshot.tasks,
                .taskEvents = runtime_snapshot.taskEvents,
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
                    .cwd = entry.value_ptr.cwd,
                    .title = entry.value_ptr.title,
                    .source_session_id = entry.value_ptr.source_session_id,
                    .status = entry.value_ptr.status,
                    .cancel_requested = entry.value_ptr.cancel_requested,
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
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
            return error.ProcessManagementUnsupported;
        }
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
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
            return error.ProcessManagementUnsupported;
        }
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
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
            return error.ProcessManagementUnsupported;
        }
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
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
            return error.ProcessManagementUnsupported;
        }
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
        if (builtin.os.tag == .windows or builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
            return error.ProcessManagementUnsupported;
        }
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

fn sessionSearchScore(session_id: []const u8, last_message: []const u8, query: []const u8) f64 {
    const trimmed = std.mem.trim(u8, query, " \t\r\n");
    if (trimmed.len == 0) return 0;

    var score: f64 = 0;
    if (std.ascii.indexOfIgnoreCase(last_message, trimmed) != null) score += 2.0;
    if (std.ascii.indexOfIgnoreCase(session_id, trimmed) != null) score += 1.0;

    var token_it = std.mem.tokenizeAny(u8, trimmed, " \t\r\n");
    while (token_it.next()) |token| {
        if (token.len == 0 or std.mem.eql(u8, token, trimmed)) continue;
        if (std.ascii.indexOfIgnoreCase(last_message, token) != null) score += 0.5;
        if (std.ascii.indexOfIgnoreCase(session_id, token) != null) score += 0.25;
    }
    return score;
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

fn getParamsObjectOrNull(frame: std.json.Value) ?std.json.ObjectMap {
    if (frame != .object) return null;
    const params_value = frame.object.get("params") orelse return null;
    if (params_value != .object) return null;
    return params_value.object;
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

fn getOptionalU64(
    params: std.json.Value,
    key: []const u8,
    default_value: u64,
) u64 {
    if (params.object.get(key)) |value| switch (value) {
        .integer => |raw| {
            if (raw > 0) return @as(u64, @intCast(raw));
        },
        .float => |raw| {
            if (raw > 0 and raw <= @as(f64, @floatFromInt(std.math.maxInt(u64)))) return @as(u64, @intFromFloat(raw));
        },
        .string => |raw| {
            const trimmed = std.mem.trim(u8, raw, " \t\r\n");
            if (trimmed.len > 0) {
                const parsed = std.fmt.parseInt(u64, trimmed, 10) catch return default_value;
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

fn generateAcpSessionIdAlloc(allocator: std.mem.Allocator, now_ms: i64, seed: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "acp-session-{d}-{d}", .{ now_ms, seed });
}

fn paramsHasDelegatedWork(params: std.json.Value) bool {
    return params.object.get("steps") != null or params.object.get("actions") != null or params.object.get("tasks") != null;
}

fn extractAcpPromptTextAlloc(
    allocator: std.mem.Allocator,
    params: std.json.Value,
) !AcpPromptText {
    var parts: std.ArrayList(u8) = .empty;
    errdefer parts.deinit(allocator);
    var block_count: usize = 0;

    if (params.object.get("prompt")) |value| {
        if (value == .string) {
            const trimmed = std.mem.trim(u8, value.string, " \t\r\n");
            if (trimmed.len > 0) {
                try parts.appendSlice(allocator, trimmed);
                block_count += 1;
            }
        }
    }
    if (parts.items.len == 0) {
        if (params.object.get("text")) |value| {
            if (value == .string) {
                const trimmed = std.mem.trim(u8, value.string, " \t\r\n");
                if (trimmed.len > 0) {
                    try parts.appendSlice(allocator, trimmed);
                    block_count += 1;
                }
            }
        }
    }
    if (params.object.get("content")) |value| {
        if (value == .array) {
            for (value.array.items) |entry| {
                if (entry != .object) continue;
                const type_value = if (entry.object.get("type")) |type_entry| switch (type_entry) {
                    .string => type_entry.string,
                    else => "",
                } else "text";
                if (!std.ascii.eqlIgnoreCase(type_value, "text")) continue;
                const text_value = entry.object.get("text") orelse continue;
                if (text_value != .string) continue;
                const trimmed = std.mem.trim(u8, text_value.string, " \t\r\n");
                if (trimmed.len == 0) continue;
                if (parts.items.len > 0) try parts.append(allocator, '\n');
                try parts.appendSlice(allocator, trimmed);
                block_count += 1;
            }
        }
    }

    return .{
        .text = try parts.toOwnedSlice(allocator),
        .blockCount = block_count,
    };
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
        error.MissingTaskId,
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
        error.SessionCancelled => -32047,
        error.TaskNotFound => -32046,
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
    try std.testing.expect(std.mem.indexOf(u8, snapshot_text, "session_messages=") != null);

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

    const catalog_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-catalog\",\"method\":\"tools.catalog\",\"params\":{}}",
    );
    defer allocator.free(catalog_response);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"runtimeTarget\":\"hosted\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"delegate_task\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"acp.initialize\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"acp.authenticate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"acp.sessions.new\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"acp.sessions.load\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"acp.sessions.resume\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"acp.sessions.events\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"acp.sessions.updates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"acp.sessions.search\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"acp.sessions.cancel\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"acp.prompt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"tool\":\"sessions.history\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"supportedOnBaremetal\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, catalog_response, "\"currentRuntimeSupported\":true") != null);

    const acp_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp\",\"method\":\"acp.describe\",\"params\":{}}",
    );
    defer allocator.free(acp_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "\"schemaVersion\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "\"mode\":\"poll\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "acp.initialize") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "acp.authenticate") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "acp.sessions.events") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "tasks.events") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "acp.sessions.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "acp.sessions.resume") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "acp.sessions.updates") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "acp.sessions.search") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "acp.sessions.cancel") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "acp.sessions.new") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "acp.prompt") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "\"sessionEvents\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "\"sessionUpdates\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_response, "\"acpSessionSearch\":true") != null);

    const acp_initialize_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-initialize\",\"method\":\"acp.initialize\",\"params\":{}}",
    );
    defer allocator.free(acp_initialize_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_initialize_response, "\"protocolVersion\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_initialize_response, "\"authMethodCount\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_initialize_response, "openai-api-key") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_initialize_response, "anthropic-api-key") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_initialize_response, "google-api-key") != null);

    const acp_authenticate_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-authenticate\",\"method\":\"acp.authenticate\",\"params\":{\"methodId\":\"openai-api-key\"}}",
    );
    defer allocator.free(acp_authenticate_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_authenticate_response, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_authenticate_response, "\"methodId\":\"openai-api-key\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_authenticate_response, "\"provider\":\"openai\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_authenticate_response, "\"runtimeTarget\":\"hosted\"") != null);

    const acp_session_new_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-acp-session-new\",\"method\":\"acp.sessions.new\",\"params\":{{\"sessionId\":\"acp-runtime\",\"cwd\":\"{s}\",\"title\":\"ACP Runtime Session\"}}}}",
        .{json_root},
    );
    defer allocator.free(acp_session_new_frame);
    const acp_session_new_response = try runtime.handleRpcFrameAlloc(allocator, acp_session_new_frame);
    defer allocator.free(acp_session_new_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_session_new_response, "\"created\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_session_new_response, "\"sessionId\":\"acp-runtime\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_session_new_response, "\"messageCount\":0") != null);

    const acp_session_load_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-acp-session-load\",\"method\":\"acp.sessions.load\",\"params\":{{\"sessionId\":\"acp-runtime\",\"cwd\":\"{s}\"}}}}",
        .{json_root},
    );
    defer allocator.free(acp_session_load_frame);
    const acp_session_load_response = try runtime.handleRpcFrameAlloc(allocator, acp_session_load_frame);
    defer allocator.free(acp_session_load_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_session_load_response, "\"loaded\":true") != null);

    const acp_cancel_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-cancel\",\"method\":\"acp.sessions.cancel\",\"params\":{\"sessionId\":\"acp-runtime\"}}",
    );
    defer allocator.free(acp_cancel_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_cancel_response, "\"cancelRequested\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_cancel_response, "cancel_requested") != null);

    const acp_prompt_blocked_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-prompt-blocked\",\"method\":\"acp.prompt\",\"params\":{\"sessionId\":\"acp-runtime\",\"content\":[{\"type\":\"text\",\"text\":\"Blocked while canceled\"}]}}",
    );
    defer allocator.free(acp_prompt_blocked_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_prompt_blocked_response, "\"code\":-32047") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_prompt_blocked_response, "SessionCancelled") != null);

    const acp_session_resume_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-session-resume\",\"method\":\"acp.sessions.resume\",\"params\":{\"sessionId\":\"acp-runtime\"}}",
    );
    defer allocator.free(acp_session_resume_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_session_resume_response, "\"created\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_session_resume_response, "\"cancelRequested\":false") != null);

    const acp_prompt_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-prompt\",\"method\":\"acp.prompt\",\"params\":{\"sessionId\":\"acp-runtime\",\"content\":[{\"type\":\"text\",\"text\":\"Plan a portable ACP session flow\"}]}}",
    );
    defer allocator.free(acp_prompt_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_prompt_response, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_prompt_response, "\"taskCount\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_prompt_response, "\"latestEventId\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_prompt_response, "Prompt recorded in the ACP session") != null);

    const acp_events_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-events\",\"method\":\"acp.sessions.events\",\"params\":{\"sessionId\":\"acp-runtime\",\"limit\":20}}",
    );
    defer allocator.free(acp_events_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_events_response, "\"count\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_events_response, "session.resume") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_events_response, "message.user") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_events_response, "message.assistant") != null);

    const acp_updates_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-updates\",\"method\":\"acp.sessions.updates\",\"params\":{\"sessionId\":\"acp-runtime\",\"limit\":20}}",
    );
    defer allocator.free(acp_updates_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_updates_response, "\"count\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_updates_response, "\"type\":\"message\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_updates_response, "message.assistant") != null);

    const acp_search_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-search\",\"method\":\"acp.sessions.search\",\"params\":{\"query\":\"portable ACP session flow\",\"limit\":10}}",
    );
    defer allocator.free(acp_search_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_search_response, "\"count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_search_response, "\"sessionId\":\"acp-runtime\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_search_response, "portable ACP session flow") != null);

    const acp_messages_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-messages\",\"method\":\"acp.sessions.messages\",\"params\":{\"sessionId\":\"acp-runtime\",\"limit\":10}}",
    );
    defer allocator.free(acp_messages_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_messages_response, "\"count\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_messages_response, "\"role\":\"user\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_messages_response, "\"role\":\"assistant\"") != null);
    const acp_fork_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-fork\",\"method\":\"acp.sessions.fork\",\"params\":{\"sourceSessionId\":\"acp-runtime\",\"newSessionId\":\"acp-runtime-fork\"}}",
    );
    defer allocator.free(acp_fork_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_fork_response, "\"clonedMessages\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_fork_response, "\"sourceSessionId\":\"acp-runtime\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_fork_response, "\"sessionId\":\"acp-runtime-fork\"") != null);

    const acp_get_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-get\",\"method\":\"acp.sessions.get\",\"params\":{\"sessionId\":\"acp-runtime-fork\"}}",
    );
    defer allocator.free(acp_get_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_get_response, "\"messageCount\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_get_response, "\"sourceSessionId\":\"acp-runtime\"") != null);

    const acp_list_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-list\",\"method\":\"acp.sessions.list\",\"params\":{\"limit\":10}}",
    );
    defer allocator.free(acp_list_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_list_response, "\"sessionId\":\"acp-runtime\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_list_response, "\"sessionId\":\"acp-runtime-fork\"") != null);

    const acp_delegate_test_path = try std.fs.path.join(allocator, &.{ root, "acp-prompt-delegate.txt" });
    defer allocator.free(acp_delegate_test_path);
    const json_acp_delegate_test_path = try std.mem.replaceOwned(u8, allocator, acp_delegate_test_path, "\\", "\\\\");
    defer allocator.free(json_acp_delegate_test_path);
    const acp_delegate_prompt_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-acp-prompt-delegate\",\"method\":\"acp.prompt\",\"params\":{{\"sessionId\":\"acp-runtime-exec\",\"goal\":\"ACP delegated file flow\",\"prompt\":\"Write then read a file in the ACP session\",\"toolsets\":[\"file\"],\"steps\":[{{\"tool\":\"file.write\",\"path\":\"{s}\",\"content\":\"acp-delegate-data\"}},{{\"tool\":\"file.read\",\"path\":\"{s}\"}}]}}}}",
        .{ json_acp_delegate_test_path, json_acp_delegate_test_path },
    );
    defer allocator.free(acp_delegate_prompt_frame);
    const acp_delegate_prompt_response = try runtime.handleRpcFrameAlloc(allocator, acp_delegate_prompt_frame);
    defer allocator.free(acp_delegate_prompt_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_delegate_prompt_response, "\"taskCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_delegate_prompt_response, "\"kind\":\"task_summary\"") != null);
    const acp_delegate_read_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-acp-prompt-read\",\"method\":\"file.read\",\"params\":{{\"sessionId\":\"acp-runtime-exec\",\"path\":\"{s}\"}}}}",
        .{json_acp_delegate_test_path},
    );
    defer allocator.free(acp_delegate_read_frame);
    const acp_delegate_read_response = try runtime.handleRpcFrameAlloc(allocator, acp_delegate_read_frame);
    defer allocator.free(acp_delegate_read_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_delegate_read_response, "acp-delegate-data") != null);

    const acp_delegate_messages_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-prompt-messages\",\"method\":\"acp.sessions.messages\",\"params\":{\"sessionId\":\"acp-runtime-exec\",\"limit\":10}}",
    );
    defer allocator.free(acp_delegate_messages_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_delegate_messages_response, "\"count\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_delegate_messages_response, "\"kind\":\"task_summary\"") != null);

    const acp_delegate_events_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-prompt-events\",\"method\":\"acp.sessions.events\",\"params\":{\"sessionId\":\"acp-runtime-exec\",\"limit\":20}}",
    );
    defer allocator.free(acp_delegate_events_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_delegate_events_response, "\"count\":8") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_delegate_events_response, "task.start") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_delegate_events_response, "message.task_summary") != null);
    const acp_delegate_updates_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-acp-prompt-updates\",\"method\":\"acp.sessions.updates\",\"params\":{\"sessionId\":\"acp-runtime-exec\",\"limit\":20}}",
    );
    defer allocator.free(acp_delegate_updates_response);
    try std.testing.expect(std.mem.indexOf(u8, acp_delegate_updates_response, "\"count\":8") != null);
    try std.testing.expect(std.mem.indexOf(u8, acp_delegate_updates_response, "message.task_summary") != null);

    const delegate_test_path = try std.fs.path.join(allocator, &.{ root, "runtime-delegate.txt" });
    defer allocator.free(delegate_test_path);
    const json_delegate_test_path = try std.mem.replaceOwned(u8, allocator, delegate_test_path, "\\", "\\\\");
    defer allocator.free(json_delegate_test_path);
    const delegate_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-delegate\",\"method\":\"delegate_task\",\"params\":{{\"goal\":\"runtime delegate file flow\",\"sessionId\":\"sess-rpc-delegate\",\"toolsets\":[\"file\"],\"steps\":[{{\"tool\":\"file.write\",\"path\":\"{s}\",\"content\":\"delegate-rpc-data\"}},{{\"tool\":\"file.read\",\"path\":\"{s}\"}}]}}}}",
        .{ json_delegate_test_path, json_delegate_test_path },
    );
    defer allocator.free(delegate_frame);
    const delegate_response = try runtime.handleRpcFrameAlloc(allocator, delegate_frame);
    defer allocator.free(delegate_response);
    try std.testing.expect(std.mem.indexOf(u8, delegate_response, "\"id\":\"rt-delegate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delegate_response, "\"status\":\"completed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, delegate_response, "delegate-rpc-data") != null);

    var delegate_parsed = try std.json.parseFromSlice(std.json.Value, allocator, delegate_response, .{});
    defer delegate_parsed.deinit();
    const delegate_result = delegate_parsed.value.object.get("result").?;
    const task_id = delegate_result.object.get("results").?.array.items[0].object.get("taskId").?.string;

    const tasks_list_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-tasks-list\",\"method\":\"tasks.list\",\"params\":{\"sessionId\":\"sess-rpc-delegate\",\"limit\":10}}",
    );
    defer allocator.free(tasks_list_response);
    try std.testing.expect(std.mem.indexOf(u8, tasks_list_response, task_id) != null);
    try std.testing.expect(std.mem.indexOf(u8, tasks_list_response, "\"count\":1") != null);

    const tasks_get_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-task-get\",\"method\":\"tasks.get\",\"params\":{{\"taskId\":\"{s}\"}}}}",
        .{task_id},
    );
    defer allocator.free(tasks_get_frame);
    const tasks_get_response = try runtime.handleRpcFrameAlloc(allocator, tasks_get_frame);
    defer allocator.free(tasks_get_response);
    try std.testing.expect(std.mem.indexOf(u8, tasks_get_response, "\"latestEventId\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, tasks_get_response, "runtime delegate file flow") != null);

    const tasks_events_frame = try std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"rt-task-events\",\"method\":\"tasks.events\",\"params\":{{\"taskId\":\"{s}\",\"limit\":10}}}}",
        .{task_id},
    );
    defer allocator.free(tasks_events_frame);
    const tasks_events_response = try runtime.handleRpcFrameAlloc(allocator, tasks_events_frame);
    defer allocator.free(tasks_events_response);
    try std.testing.expect(std.mem.indexOf(u8, tasks_events_response, "\"count\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, tasks_events_response, "task.start") != null);
    try std.testing.expect(std.mem.indexOf(u8, tasks_events_response, "task.complete") != null);

    const tasks_search_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-task-search\",\"method\":\"tasks.search\",\"params\":{\"query\":\"runtime delegate\",\"sessionId\":\"sess-rpc-delegate\",\"limit\":5}}",
    );
    defer allocator.free(tasks_search_response);
    try std.testing.expect(std.mem.indexOf(u8, tasks_search_response, task_id) != null);
    try std.testing.expect(std.mem.indexOf(u8, tasks_search_response, "\"count\":1") != null);

    const history_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-history\",\"method\":\"sessions.history\",\"params\":{\"sessionId\":\"sess-rpc-delegate\",\"limit\":10}}",
    );
    defer allocator.free(history_response);
    try std.testing.expect(std.mem.indexOf(u8, history_response, "\"count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, history_response, "\"sessionId\":\"sess-rpc-delegate\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, history_response, "delegate") != null);

    const session_search_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-session-search\",\"method\":\"sessions.search\",\"params\":{\"query\":\"sess-rpc-delegate\",\"limit\":5}}",
    );
    defer allocator.free(session_search_response);
    try std.testing.expect(std.mem.indexOf(u8, session_search_response, "\"sessionId\":\"sess-rpc-delegate\"") != null);

    const snapshot_response = try runtime.handleRpcFrameAlloc(
        allocator,
        "{\"id\":\"rt-snapshot\",\"method\":\"runtime.snapshot\",\"params\":{}}",
    );
    defer allocator.free(snapshot_response);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_response, "\"id\":\"rt-snapshot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_response, "\"sessions\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_response, "\"sessionMessages\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_response, "\"sessionEvents\":21") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_response, "\"tasks\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_response, "\"taskEvents\":12") != null);

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
