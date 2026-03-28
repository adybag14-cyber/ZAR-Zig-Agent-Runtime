const std = @import("std");

pub const CatalogEntry = struct {
    tool: []const u8,
    provider: []const u8,
    kind: []const u8,
    approvalSensitive: bool,
    description: []const u8,
    supportedOnHosted: bool = true,
    supportedOnBaremetal: bool = true,
};

pub const RuntimeCatalogEntry = struct {
    tool: []const u8,
    provider: []const u8,
    kind: []const u8,
    approvalSensitive: bool,
    description: []const u8,
    supportedOnHosted: bool,
    supportedOnBaremetal: bool,
    currentRuntimeSupported: bool,
};

pub const portable_entries = [_]CatalogEntry{
    .{ .tool = "acp", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Hermes-guided ACP bridge family (initialize/authenticate/describe/sessions/prompt)" },
    .{ .tool = "acp.initialize", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Describe the Hermes-inspired ACP handshake, capabilities, and runtime-auth posture" },
    .{ .tool = "acp.authenticate", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Check whether the current runtime has Hermes-style provider credentials available for ACP use" },
    .{ .tool = "acp.describe", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Describe the Hermes-guided ACP bridge metadata, capabilities, and event-delivery posture" },
    .{ .tool = "acp.sessions", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "ACP session lifecycle family (new/load/resume/list/get/messages/events/updates/search/fork/cancel)" },
    .{ .tool = "acp.sessions.list", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "List persisted ACP session receipts and transcript counts" },
    .{ .tool = "acp.sessions.new", .provider = "builtin-runtime", .kind = "edit", .approvalSensitive = false, .description = "Create or update an ACP session with cwd/title metadata" },
    .{ .tool = "acp.sessions.load", .provider = "builtin-runtime", .kind = "edit", .approvalSensitive = false, .description = "Load an existing ACP session and refresh cwd/title metadata without resetting its cancel state" },
    .{ .tool = "acp.sessions.resume", .provider = "builtin-runtime", .kind = "edit", .approvalSensitive = false, .description = "Resume an ACP session, creating it if missing and clearing any outstanding cancel request" },
    .{ .tool = "acp.sessions.get", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Load one ACP session receipt and current transcript counters" },
    .{ .tool = "acp.sessions.messages", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Read persisted ACP session transcript messages with cursor support" },
    .{ .tool = "acp.sessions.events", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Poll persisted ACP session update events with cursor support" },
    .{ .tool = "acp.sessions.updates", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Poll Hermes-style ACP session updates mapped onto a single portable event stream" },
    .{ .tool = "acp.sessions.search", .provider = "builtin-runtime", .kind = "search", .approvalSensitive = false, .description = "Search ACP session metadata, transcript rows, and delegated-task summaries" },
    .{ .tool = "acp.sessions.fork", .provider = "builtin-runtime", .kind = "edit", .approvalSensitive = false, .description = "Fork an ACP session into a new session with cloned transcript state" },
    .{ .tool = "acp.sessions.cancel", .provider = "builtin-runtime", .kind = "edit", .approvalSensitive = false, .description = "Mark an ACP session as canceled and block new prompts until it is resumed" },
    .{ .tool = "acp.prompt", .provider = "builtin-runtime", .kind = "execute", .approvalSensitive = true, .description = "Record an ACP prompt and optionally run Hermes-style delegated steps inside the ACP session" },
    .{ .tool = "tools.catalog", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Describe the portable runtime tool contract and support posture" },
    .{ .tool = "exec", .provider = "builtin-runtime", .kind = "execute", .approvalSensitive = true, .description = "Exec tool family alias for command execution" },
    .{ .tool = "exec.run", .provider = "builtin-runtime", .kind = "execute", .approvalSensitive = true, .description = "Execute local process or bare-metal tool command with timeout" },
    .{ .tool = "execute_code", .provider = "builtin-runtime", .kind = "execute", .approvalSensitive = true, .description = "Run short code snippets through local interpreters or compilers", .supportedOnHosted = true, .supportedOnBaremetal = false },
    .{ .tool = "delegate_task", .provider = "builtin-runtime", .kind = "execute", .approvalSensitive = true, .description = "Run Hermes-style delegated step batches with isolated session scopes, tool traces, and progress events" },
    .{ .tool = "tasks", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Portable delegated task receipt family (list/get/events/search)" },
    .{ .tool = "tasks.list", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "List persisted delegated task receipts across hosted and bare-metal runtime modes" },
    .{ .tool = "tasks.get", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Load a persisted delegated task receipt by task id" },
    .{ .tool = "tasks.events", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Poll persisted delegated task events by task or session with cursor support" },
    .{ .tool = "tasks.search", .provider = "builtin-runtime", .kind = "search", .approvalSensitive = false, .description = "Search delegated task receipts by goal, summary, status, or session" },
    .{ .tool = "file.read", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Read local or bare-metal logical file content" },
    .{ .tool = "file.write", .provider = "builtin-runtime", .kind = "edit", .approvalSensitive = false, .description = "Write local or bare-metal logical file content" },
    .{ .tool = "file.search", .provider = "builtin-runtime", .kind = "search", .approvalSensitive = false, .description = "Recursively search local or bare-metal logical files for matching text" },
    .{ .tool = "file.patch", .provider = "builtin-runtime", .kind = "edit", .approvalSensitive = false, .description = "Apply bounded text replacement patch to a local or bare-metal logical file" },
    .{ .tool = "web", .provider = "builtin-runtime", .kind = "fetch", .approvalSensitive = false, .description = "Web research tool family (search/extract)", .supportedOnHosted = true, .supportedOnBaremetal = false },
    .{ .tool = "web.search", .provider = "builtin-runtime", .kind = "fetch", .approvalSensitive = false, .description = "Search the web and return titles, URLs, and descriptions", .supportedOnHosted = true, .supportedOnBaremetal = false },
    .{ .tool = "web.extract", .provider = "builtin-runtime", .kind = "fetch", .approvalSensitive = false, .description = "Fetch web page URLs and extract readable content", .supportedOnHosted = true, .supportedOnBaremetal = false },
    .{ .tool = "process", .provider = "builtin-runtime", .kind = "execute", .approvalSensitive = true, .description = "Background process lifecycle tool family", .supportedOnHosted = true, .supportedOnBaremetal = false },
    .{ .tool = "process.start", .provider = "builtin-runtime", .kind = "execute", .approvalSensitive = true, .description = "Start a background process and capture stdout/stderr to logs", .supportedOnHosted = true, .supportedOnBaremetal = false },
    .{ .tool = "process.list", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "List tracked background processes", .supportedOnHosted = true, .supportedOnBaremetal = false },
    .{ .tool = "process.poll", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Poll tracked background process state and recent logs", .supportedOnHosted = true, .supportedOnBaremetal = false },
    .{ .tool = "process.read", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Read tracked background process logs and state", .supportedOnHosted = true, .supportedOnBaremetal = false },
    .{ .tool = "process.wait", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Wait for a tracked background process to finish", .supportedOnHosted = true, .supportedOnBaremetal = false },
    .{ .tool = "process.kill", .provider = "builtin-runtime", .kind = "execute", .approvalSensitive = false, .description = "Terminate a tracked background process", .supportedOnHosted = true, .supportedOnBaremetal = false },
    .{ .tool = "sessions", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Portable session memory tool family (history/search)" },
    .{ .tool = "sessions.history", .provider = "builtin-runtime", .kind = "read", .approvalSensitive = false, .description = "Read portable runtime session history receipts" },
    .{ .tool = "sessions.search", .provider = "builtin-runtime", .kind = "search", .approvalSensitive = false, .description = "Search portable runtime session history receipts" },
};

pub fn runtimeCatalogEntries(comptime os_tag: std.Target.Os.Tag) [portable_entries.len]RuntimeCatalogEntry {
    var out: [portable_entries.len]RuntimeCatalogEntry = undefined;
    inline for (portable_entries, 0..) |entry, idx| {
        out[idx] = .{
            .tool = entry.tool,
            .provider = entry.provider,
            .kind = entry.kind,
            .approvalSensitive = entry.approvalSensitive,
            .description = entry.description,
            .supportedOnHosted = entry.supportedOnHosted,
            .supportedOnBaremetal = entry.supportedOnBaremetal,
            .currentRuntimeSupported = isSupportedOnTarget(entry.tool, os_tag),
        };
    }
    return out;
}

pub fn currentRuntimeTargetLabel(comptime os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .freestanding => "baremetal",
        else => "hosted",
    };
}

pub fn isPortableTool(method: []const u8) bool {
    return lookupEntry(method) != null;
}

pub fn isSupportedOnTarget(method: []const u8, comptime os_tag: std.Target.Os.Tag) bool {
    if (lookupEntry(method)) |entry| {
        if (os_tag == .freestanding) return entry.supportedOnBaremetal;
        if (!entry.supportedOnHosted) return false;
        if (os_tag == .windows) {
            if (std.ascii.eqlIgnoreCase(method, "execute_code")) return false;
            if (std.ascii.eqlIgnoreCase(method, "process") or std.mem.startsWith(u8, method, "process.")) return false;
        }
        if (os_tag == .wasi) {
            if (std.ascii.eqlIgnoreCase(method, "execute_code") or
                std.ascii.eqlIgnoreCase(method, "exec") or
                std.ascii.eqlIgnoreCase(method, "exec.run") or
                std.ascii.eqlIgnoreCase(method, "web") or
                std.mem.startsWith(u8, method, "web.") or
                std.ascii.eqlIgnoreCase(method, "process") or
                std.mem.startsWith(u8, method, "process."))
            {
                return false;
            }
        }
        return true;
    }
    return false;
}

pub fn toolAllowedByToolsets(method: []const u8, toolsets_value: ?std.json.Value) bool {
    if (toolsets_value == null) return true;
    const value = toolsets_value.?;
    if (value != .array) return true;
    if (value.array.items.len == 0) return true;
    if (std.ascii.eqlIgnoreCase(method, "tools.catalog") or
        std.ascii.eqlIgnoreCase(method, "acp.initialize") or
        std.ascii.eqlIgnoreCase(method, "acp.authenticate") or
        std.ascii.eqlIgnoreCase(method, "acp.describe")) return true;

    for (value.array.items) |entry| {
        if (entry != .string) continue;
        if (toolsetAllows(entry.string, method)) return true;
    }
    return false;
}

pub fn toolsetAllows(toolset: []const u8, method: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(toolset, "terminal") or std.ascii.eqlIgnoreCase(toolset, "process") or std.ascii.eqlIgnoreCase(toolset, "code_execution")) {
        return std.ascii.eqlIgnoreCase(method, "exec.run") or
            std.ascii.eqlIgnoreCase(method, "execute_code") or
            std.ascii.eqlIgnoreCase(method, "process") or
            std.mem.startsWith(u8, method, "process.");
    }
    if (std.ascii.eqlIgnoreCase(toolset, "file")) {
        return std.mem.startsWith(u8, method, "file.");
    }
    if (std.ascii.eqlIgnoreCase(toolset, "web")) {
        return std.ascii.eqlIgnoreCase(method, "web") or std.mem.startsWith(u8, method, "web.");
    }
    if (std.ascii.eqlIgnoreCase(toolset, "memory") or std.ascii.eqlIgnoreCase(toolset, "sessions") or std.ascii.eqlIgnoreCase(toolset, "search")) {
        return std.ascii.eqlIgnoreCase(method, "sessions") or
            std.ascii.eqlIgnoreCase(method, "sessions.history") or
            std.ascii.eqlIgnoreCase(method, "sessions.search") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.list") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.get") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.messages") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.events") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.updates") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.search") or
            std.ascii.eqlIgnoreCase(method, "tasks") or
            std.ascii.eqlIgnoreCase(method, "tasks.list") or
            std.ascii.eqlIgnoreCase(method, "tasks.get") or
            std.ascii.eqlIgnoreCase(method, "tasks.events") or
            std.ascii.eqlIgnoreCase(method, "tasks.search") or
            std.ascii.eqlIgnoreCase(method, "file.search") or
            std.ascii.eqlIgnoreCase(method, "web.search");
    }
    if (std.ascii.eqlIgnoreCase(toolset, "inspect")) {
        return std.ascii.eqlIgnoreCase(method, "tools.catalog") or
            std.ascii.eqlIgnoreCase(method, "acp") or
            std.ascii.eqlIgnoreCase(method, "acp.initialize") or
            std.ascii.eqlIgnoreCase(method, "acp.authenticate") or
            std.ascii.eqlIgnoreCase(method, "acp.describe") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.list") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.get") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.messages") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.events") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.updates") or
            std.ascii.eqlIgnoreCase(method, "acp.sessions.search") or
            std.ascii.eqlIgnoreCase(method, "tasks") or
            std.ascii.eqlIgnoreCase(method, "tasks.list") or
            std.ascii.eqlIgnoreCase(method, "tasks.get") or
            std.ascii.eqlIgnoreCase(method, "tasks.events") or
            std.ascii.eqlIgnoreCase(method, "tasks.search");
    }
    return false;
}

pub fn toolKindForMethod(method: []const u8) []const u8 {
    return if (lookupEntry(method)) |entry| entry.kind else "other";
}

fn lookupEntry(method: []const u8) ?CatalogEntry {
    for (portable_entries) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.tool, method)) return entry;
    }
    return null;
}

test "tool contract marks hosted and baremetal support posture" {
    try std.testing.expect(isPortableTool("delegate_task"));
    try std.testing.expect(isPortableTool("acp.initialize"));
    try std.testing.expect(isPortableTool("acp.authenticate"));
    try std.testing.expect(isPortableTool("acp.sessions.new"));
    try std.testing.expect(isPortableTool("acp.sessions.events"));
    try std.testing.expect(isPortableTool("acp.sessions.updates"));
    try std.testing.expect(isPortableTool("acp.sessions.search"));
    try std.testing.expect(isPortableTool("acp.prompt"));
    try std.testing.expect(isSupportedOnTarget("delegate_task", .freestanding));
    try std.testing.expect(isSupportedOnTarget("exec.run", .freestanding));
    try std.testing.expect(!isSupportedOnTarget("execute_code", .freestanding));
    try std.testing.expect(!isSupportedOnTarget("web.search", .freestanding));
    try std.testing.expect(!isSupportedOnTarget("process.start", .freestanding));
    try std.testing.expect(!isSupportedOnTarget("process.start", .windows));
    try std.testing.expect(!isSupportedOnTarget("execute_code", .windows));
    try std.testing.expect(isSupportedOnTarget("sessions.search", .freestanding));
    try std.testing.expect(isSupportedOnTarget("acp.sessions.messages", .freestanding));
    try std.testing.expect(isSupportedOnTarget("acp.sessions.updates", .freestanding));
    try std.testing.expect(isSupportedOnTarget("acp.sessions.search", .freestanding));
    try std.testing.expect(isSupportedOnTarget("acp.sessions.cancel", .freestanding));
    try std.testing.expect(isSupportedOnTarget("acp.prompt", .freestanding));
}


test "toolset gating keeps acp prompt out of delegated memory slices" {
    try std.testing.expect(toolsetAllows("memory", "acp.sessions.list"));
    try std.testing.expect(toolsetAllows("inspect", "acp.sessions.messages"));
    try std.testing.expect(toolsetAllows("memory", "acp.sessions.events"));
    try std.testing.expect(toolsetAllows("memory", "acp.sessions.updates"));
    try std.testing.expect(toolsetAllows("memory", "acp.sessions.search"));
    try std.testing.expect(toolsetAllows("inspect", "acp.initialize"));
    try std.testing.expect(toolsetAllows("inspect", "acp.authenticate"));
    try std.testing.expect(!toolsetAllows("memory", "acp.prompt"));
    try std.testing.expect(!toolsetAllows("inspect", "acp.prompt"));
}

test "tool kind lookup maps runtime tools to acp kinds" {
    try std.testing.expectEqualStrings("edit", toolKindForMethod("file.patch"));
    try std.testing.expectEqualStrings("execute", toolKindForMethod("acp.prompt"));
    try std.testing.expectEqualStrings("other", toolKindForMethod("not-real"));
}
