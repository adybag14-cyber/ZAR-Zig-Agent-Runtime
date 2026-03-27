// SPDX-License-Identifier: GPL-2.0-only
const builtin = @import("builtin");
const std = @import("std");
const gateway_request = @import("request.zig");
const gateway_response = @import("response.zig");
const tool_contract = @import("../runtime/tool_contract.zig");
const time_util = @import("../util/time.zig");

pub const StepEvent = struct {
    atMs: i64,
    kind: []const u8,
    stepIndex: ?usize = null,
    toolCallId: ?[]const u8 = null,
    tool: ?[]const u8 = null,
    status: ?[]const u8 = null,
    preview: ?[]const u8 = null,
};

pub const StepResult = struct {
    stepIndex: usize,
    toolCallId: []u8,
    tool: []u8,
    title: []u8,
    status: []u8,
    state: ?[]u8 = null,
    approvalId: ?[]u8 = null,
    errorMessage: ?[]u8 = null,
    errorCode: ?i64 = null,
    ok: bool,
    durationMs: i64,
    preview: []u8,
    responseExcerpt: []u8,

    pub fn deinit(self: *StepResult, allocator: std.mem.Allocator) void {
        allocator.free(self.toolCallId);
        allocator.free(self.tool);
        allocator.free(self.title);
        allocator.free(self.status);
        if (self.state) |value| allocator.free(value);
        if (self.approvalId) |value| allocator.free(value);
        if (self.errorMessage) |value| allocator.free(value);
        allocator.free(self.preview);
        allocator.free(self.responseExcerpt);
    }
};

pub const TaskResult = struct {
    taskIndex: usize,
    taskId: []u8,
    goal: []u8,
    context: []u8,
    sessionId: []u8,
    cwd: []u8,
    status: []u8,
    completedSteps: usize,
    totalSteps: usize,
    successCount: usize,
    failureCount: usize,
    approvalRequiredCount: usize,
    steps: []StepResult,
    events: []StepEvent,
    summary: []u8,

    pub fn deinit(self: *TaskResult, allocator: std.mem.Allocator) void {
        allocator.free(self.taskId);
        allocator.free(self.goal);
        allocator.free(self.context);
        allocator.free(self.sessionId);
        allocator.free(self.cwd);
        allocator.free(self.status);
        for (self.steps) |*step| step.deinit(allocator);
        allocator.free(self.steps);
        allocator.free(self.events);
        allocator.free(self.summary);
    }
};

pub const BatchResult = struct {
    ok: bool,
    kind: []const u8,
    count: usize,
    succeeded: usize,
    failed: usize,
    blocked: usize,
    results: []TaskResult,

    pub fn deinit(self: *BatchResult, allocator: std.mem.Allocator) void {
        for (self.results) |*entry| entry.deinit(allocator);
        allocator.free(self.results);
    }
};

const ResponseSummary = struct {
    ok: bool,
    approval_required: bool,
    state: ?[]u8 = null,
    approval_id: ?[]u8 = null,
    error_message: ?[]u8 = null,
    error_code: ?i64 = null,
    preview: []u8,
    response_excerpt: []u8,

    fn deinit(self: *ResponseSummary, allocator: std.mem.Allocator) void {
        if (self.state) |value| allocator.free(value);
        if (self.approval_id) |value| allocator.free(value);
        if (self.error_message) |value| allocator.free(value);
        allocator.free(self.preview);
        allocator.free(self.response_excerpt);
    }
};

const default_session_prefix = "delegate-session";
const default_summary_preview_limit: usize = 160;
const default_response_excerpt_limit: usize = 2048;

pub const RunDefaults = struct {
    goal: []const u8 = "",
    session_id: []const u8 = "",
    cwd: []const u8 = "",
};

pub fn run(
    allocator: std.mem.Allocator,
    params: ?std.json.ObjectMap,
    invoke_ctx: anytype,
    comptime invoke_fn: anytype,
) anyerror!BatchResult {
    return runWithDefaults(allocator, params, .{}, invoke_ctx, invoke_fn);
}

pub fn runWithDefaults(
    allocator: std.mem.Allocator,
    params: ?std.json.ObjectMap,
    defaults: RunDefaults,
    invoke_ctx: anytype,
    comptime invoke_fn: anytype,
) anyerror!BatchResult {
    const now_ms = time_util.nowMs();
    const task_values = if (getValue(params, "tasks")) |value| switch (value) {
        .array => value.array.items,
        else => return error.InvalidParamsFrame,
    } else null;

    var results: std.ArrayList(TaskResult) = .empty;
    errdefer {
        for (results.items) |*entry| entry.deinit(allocator);
        results.deinit(allocator);
    }

    if (task_values) |items| {
        if (items.len == 0) return error.InvalidParamsFrame;
        for (items, 0..) |item, idx| {
            if (item != .object) return error.InvalidParamsFrame;
            try results.append(allocator, try executeTask(allocator, params, defaults, item.object, idx, now_ms, items.len > 1, invoke_ctx, invoke_fn));
        }
    } else {
        const root = params orelse return error.InvalidParamsFrame;
        if (getValue(root, "steps") == null and getValue(root, "actions") == null) return error.InvalidParamsFrame;
        try results.append(allocator, try executeTask(allocator, params, defaults, root, 0, now_ms, false, invoke_ctx, invoke_fn));
    }

    var output = BatchResult{
        .ok = true,
        .kind = "delegate_task",
        .count = results.items.len,
        .succeeded = 0,
        .failed = 0,
        .blocked = 0,
        .results = try results.toOwnedSlice(allocator),
    };

    for (output.results) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.status, "completed")) {
            output.succeeded += 1;
        } else if (std.ascii.eqlIgnoreCase(entry.status, "blocked")) {
            output.blocked += 1;
            output.ok = false;
        } else {
            output.failed += 1;
            output.ok = false;
        }
    }

    return output;
}

fn executeTask(
    allocator: std.mem.Allocator,
    root_params: ?std.json.ObjectMap,
    defaults: RunDefaults,
    task_obj: std.json.ObjectMap,
    task_index: usize,
    now_ms: i64,
    batch_mode: bool,
    invoke_ctx: anytype,
    comptime invoke_fn: anytype,
) anyerror!TaskResult {
    const default_goal = if (defaults.goal.len > 0) defaults.goal else "";
    const goal_raw = getString(task_obj, "goal", getString(task_obj, "title", getString(root_params, "goal", default_goal)));
    const context_raw = getString(task_obj, "context", "");
    const stop_on_error = getBool(task_obj, "stopOnError", getBool(root_params, "stopOnError", true));
    const cwd_raw = getString(task_obj, "cwd", getString(root_params, "cwd", defaults.cwd));
    const task_id = try std.fmt.allocPrint(allocator, "delegate-task-{d}-{d}", .{ now_ms, task_index + 1 });
    errdefer allocator.free(task_id);

    const session_id = try buildTaskSessionId(allocator, root_params, defaults, task_obj, task_index, batch_mode, now_ms);
    errdefer allocator.free(session_id);

    const goal = try allocator.dupe(u8, goal_raw);
    errdefer allocator.free(goal);
    const context = try allocator.dupe(u8, context_raw);
    errdefer allocator.free(context);
    const cwd = try allocator.dupe(u8, cwd_raw);
    errdefer allocator.free(cwd);

    const steps_value = getValue(task_obj, "steps") orelse getValue(task_obj, "actions") orelse blk: {
        if (!batch_mode) {
            if (root_params) |root| {
                if (getValue(root, "steps")) |value| break :blk value;
                if (getValue(root, "actions")) |value| break :blk value;
            }
        }
        break :blk std.json.Value{ .null = {} };
    };

    var step_items: []const std.json.Value = &.{};
    switch (steps_value) {
        .array => |array| step_items = array.items,
        .null => {},
        else => {},
    }

    var step_results: std.ArrayList(StepResult) = .empty;
    errdefer {
        for (step_results.items) |*step| step.deinit(allocator);
        step_results.deinit(allocator);
    }
    var events: std.ArrayList(StepEvent) = .empty;
    errdefer events.deinit(allocator);

    const start_preview: []const u8 = if (goal.len > 0) goal else "delegated task";
    try events.append(allocator, .{
        .atMs = time_util.nowMs(),
        .kind = "task.start",
        .preview = start_preview,
    });

    var success_count: usize = 0;
    var failure_count: usize = 0;
    var approval_required_count: usize = 0;
    var completed_steps: usize = 0;

    if (step_items.len == 0) {
        const invalid_step = try buildSyntheticStep(
            allocator,
            task_id,
            0,
            "delegate.invalid",
            "delegate.invalid",
            "failed",
            false,
            "missing steps array for delegated task",
            "delegate_invalid",
            null,
            null,
            0,
        );
        try events.append(allocator, .{
            .atMs = time_util.nowMs(),
            .kind = "tool.call.result",
            .stepIndex = 0,
            .toolCallId = invalid_step.toolCallId,
            .tool = invalid_step.tool,
            .status = invalid_step.status,
            .preview = invalid_step.preview,
        });
        try step_results.append(allocator, invalid_step);
        failure_count = 1;
    } else {
        for (step_items, 0..) |step_value, step_index| {
            const step_start_ms = time_util.nowMs();
            const step = executeStep(
                allocator,
                task_id,
                step_index,
                step_value,
                task_obj,
                root_params,
                session_id,
                cwd,
                invoke_ctx,
                invoke_fn,
            ) catch |err| blk: {
                const fallback = try buildSyntheticStep(
                    allocator,
                    task_id,
                    step_index,
                    "delegate.invalid",
                    "delegate.invalid",
                    "failed",
                    false,
                    @errorName(err),
                    "delegate_invalid",
                    null,
                    null,
                    time_util.nowMs() - step_start_ms,
                );
                break :blk fallback;
            };
            try events.append(allocator, .{
                .atMs = step_start_ms,
                .kind = "tool.call.start",
                .stepIndex = step_index,
                .toolCallId = step.toolCallId,
                .tool = step.tool,
                .status = "started",
                .preview = step.title,
            });
            try events.append(allocator, .{
                .atMs = time_util.nowMs(),
                .kind = "tool.call.result",
                .stepIndex = step_index,
                .toolCallId = step.toolCallId,
                .tool = step.tool,
                .status = step.status,
                .preview = step.preview,
            });

            if (step.ok) {
                success_count += 1;
                completed_steps += 1;
            } else if (step.state) |state| {
                if (std.ascii.eqlIgnoreCase(state, "approval_required")) {
                    approval_required_count += 1;
                } else {
                    failure_count += 1;
                }
            } else {
                failure_count += 1;
            }

            try step_results.append(allocator, step);
            if (!step.ok and stop_on_error) break;
        }
    }

    const status_literal = if (failure_count > 0)
        "failed"
    else if (approval_required_count > 0)
        "blocked"
    else
        "completed";
    const status = try allocator.dupe(u8, status_literal);
    errdefer allocator.free(status);

    const summary = try std.fmt.allocPrint(
        allocator,
        "{s}: {d}/{d} steps completed ({d} ok, {d} failed, {d} approval required)",
        .{ status, completed_steps, step_items.len, success_count, failure_count, approval_required_count },
    );
    errdefer allocator.free(summary);

    try events.append(allocator, .{
        .atMs = time_util.nowMs(),
        .kind = "task.complete",
        .status = status,
        .preview = summary,
    });

    return .{
        .taskIndex = task_index,
        .taskId = task_id,
        .goal = goal,
        .context = context,
        .sessionId = session_id,
        .cwd = cwd,
        .status = status,
        .completedSteps = completed_steps,
        .totalSteps = step_items.len,
        .successCount = success_count,
        .failureCount = failure_count,
        .approvalRequiredCount = approval_required_count,
        .steps = try step_results.toOwnedSlice(allocator),
        .events = try events.toOwnedSlice(allocator),
        .summary = summary,
    };
}

fn executeStep(
    allocator: std.mem.Allocator,
    task_id: []const u8,
    step_index: usize,
    step_value: std.json.Value,
    task_obj: std.json.ObjectMap,
    root_params: ?std.json.ObjectMap,
    session_id: []const u8,
    cwd: []const u8,
    invoke_ctx: anytype,
    comptime invoke_fn: anytype,
) anyerror!StepResult {
    if (step_value != .object) {
        return buildSyntheticStep(
            allocator,
            task_id,
            step_index,
            "delegate.invalid",
            "delegate.invalid",
            "failed",
            false,
            "delegated step must be an object",
            "delegate_invalid",
            null,
            null,
            0,
        );
    }

    const step_obj = step_value.object;
    const tool_raw = getString(step_obj, "tool", getString(step_obj, "method", ""));
    if (tool_raw.len == 0) {
        return buildSyntheticStep(
            allocator,
            task_id,
            step_index,
            "delegate.invalid",
            "delegate.invalid",
            "failed",
            false,
            "delegated step is missing tool/method",
            "delegate_invalid",
            null,
            null,
            0,
        );
    }
    const title_raw = getString(step_obj, "title", tool_raw);

    if (!isDelegatableTool(tool_raw)) {
        return buildSyntheticStep(
            allocator,
            task_id,
            step_index,
            tool_raw,
            title_raw,
            "not_allowed",
            false,
            "tool is not available to Zig delegate_task",
            "tool_not_allowed",
            null,
            null,
            0,
        );
    }

    const toolsets_value = getValue(step_obj, "toolsets") orelse getValue(task_obj, "toolsets") orelse getValue(root_params, "toolsets");
    if (!toolAllowedByToolsets(tool_raw, toolsets_value)) {
        return buildSyntheticStep(
            allocator,
            task_id,
            step_index,
            tool_raw,
            title_raw,
            "not_allowed",
            false,
            "tool is outside the delegated task toolset",
            "toolset_blocked",
            null,
            null,
            0,
        );
    }

    if (!toolSupportedOnCurrentRuntime(tool_raw)) {
        return buildSyntheticStep(
            allocator,
            task_id,
            step_index,
            tool_raw,
            title_raw,
            "not_supported",
            false,
            "tool is not supported on the current runtime target",
            "unsupported_runtime",
            null,
            null,
            0,
        );
    }

    var params_value = try buildStepParamsValue(allocator, step_obj, tool_raw, session_id, cwd);
    defer if (params_value == .object) params_value.object.deinit();

    const tool_call_id = try std.fmt.allocPrint(allocator, "{s}-step-{d}", .{ task_id, step_index + 1 });
    errdefer allocator.free(tool_call_id);

    const frame = try encodeFrame(allocator, tool_call_id, tool_raw, params_value);
    defer allocator.free(frame);

    const start_ms = time_util.nowMs();
    const response_frame = try invoke_fn(invoke_ctx, allocator, frame);
    defer allocator.free(response_frame);
    var summary = try summarizeResponse(allocator, response_frame);
    defer summary.deinit(allocator);

    const duration_ms = time_util.nowMs() - start_ms;
    return .{
        .stepIndex = step_index,
        .toolCallId = tool_call_id,
        .tool = try allocator.dupe(u8, tool_raw),
        .title = try allocator.dupe(u8, title_raw),
        .status = try allocator.dupe(u8, if (summary.ok) "completed" else if (summary.approval_required) "blocked" else "failed"),
        .state = if (summary.state) |value| try allocator.dupe(u8, value) else null,
        .approvalId = if (summary.approval_id) |value| try allocator.dupe(u8, value) else null,
        .errorMessage = if (summary.error_message) |value| try allocator.dupe(u8, value) else null,
        .errorCode = summary.error_code,
        .ok = summary.ok,
        .durationMs = duration_ms,
        .preview = try allocator.dupe(u8, summary.preview),
        .responseExcerpt = try allocator.dupe(u8, summary.response_excerpt),
    };
}

fn buildSyntheticStep(
    allocator: std.mem.Allocator,
    task_id: []const u8,
    step_index: usize,
    tool_raw: []const u8,
    title_raw: []const u8,
    status_raw: []const u8,
    ok: bool,
    message_raw: []const u8,
    state_raw: []const u8,
    approval_id_raw: ?[]const u8,
    error_code: ?i64,
    duration_ms: i64,
) anyerror!StepResult {
    return .{
        .stepIndex = step_index,
        .toolCallId = try std.fmt.allocPrint(allocator, "{s}-step-{d}", .{ task_id, step_index + 1 }),
        .tool = try allocator.dupe(u8, tool_raw),
        .title = try allocator.dupe(u8, title_raw),
        .status = try allocator.dupe(u8, status_raw),
        .state = try allocator.dupe(u8, state_raw),
        .approvalId = if (approval_id_raw) |value| try allocator.dupe(u8, value) else null,
        .errorMessage = try allocator.dupe(u8, message_raw),
        .errorCode = error_code,
        .ok = ok,
        .durationMs = duration_ms,
        .preview = try previewAlloc(allocator, message_raw, default_summary_preview_limit),
        .responseExcerpt = try allocator.dupe(u8, message_raw),
    };
}

fn buildTaskSessionId(
    allocator: std.mem.Allocator,
    root_params: ?std.json.ObjectMap,
    defaults: RunDefaults,
    task_obj: std.json.ObjectMap,
    task_index: usize,
    batch_mode: bool,
    now_ms: i64,
) anyerror![]u8 {
    const explicit = getString(task_obj, "sessionId", getString(root_params, "sessionId", defaults.session_id));
    if (explicit.len > 0 and (!batch_mode or getString(task_obj, "sessionId", "").len > 0)) {
        return allocator.dupe(u8, explicit);
    }
    if (explicit.len > 0 and batch_mode) {
        return std.fmt.allocPrint(allocator, "{s}-task-{d}", .{ explicit, task_index + 1 });
    }
    return std.fmt.allocPrint(allocator, "{s}-{d}-task-{d}", .{ default_session_prefix, now_ms, task_index + 1 });
}

fn buildStepParamsValue(
    allocator: std.mem.Allocator,
    step_obj: std.json.ObjectMap,
    tool: []const u8,
    session_id: []const u8,
    cwd: []const u8,
) anyerror!std.json.Value {
    var out = std.json.ObjectMap.init(allocator);
    errdefer out.deinit();

    if (step_obj.get("params")) |params_value| {
        if (params_value != .object) return error.InvalidParamsFrame;
        var it = params_value.object.iterator();
        while (it.next()) |entry| {
            try out.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    } else {
        var it = step_obj.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            if (std.ascii.eqlIgnoreCase(key, "tool") or std.ascii.eqlIgnoreCase(key, "method") or std.ascii.eqlIgnoreCase(key, "title") or std.ascii.eqlIgnoreCase(key, "toolsets")) continue;
            try out.put(key, entry.value_ptr.*);
        }
    }

    if (methodUsesSession(tool) and out.get("sessionId") == null and out.get("session") == null) {
        try out.put("sessionId", .{ .string = session_id });
    }
    if (methodUsesCwd(tool) and cwd.len > 0 and out.get("cwd") == null and out.get("workdir") == null and out.get("workingDirectory") == null) {
        try out.put("cwd", .{ .string = cwd });
    }
    return .{ .object = out };
}

fn summarizeResponse(allocator: std.mem.Allocator, response_frame: []const u8) anyerror!ResponseSummary {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, response_frame, .{}) catch {
        return .{
            .ok = false,
            .approval_required = false,
            .state = try allocator.dupe(u8, "invalid_json"),
            .error_message = try allocator.dupe(u8, "delegated step returned non-JSON response"),
            .preview = try previewAlloc(allocator, response_frame, default_summary_preview_limit),
            .response_excerpt = try excerptAlloc(allocator, response_frame, default_response_excerpt_limit),
        };
    };
    defer parsed.deinit();

    if (parsed.value != .object) {
        return .{
            .ok = false,
            .approval_required = false,
            .state = try allocator.dupe(u8, "invalid_response"),
            .error_message = try allocator.dupe(u8, "delegated step returned a non-object envelope"),
            .preview = try previewAlloc(allocator, response_frame, default_summary_preview_limit),
            .response_excerpt = try excerptAlloc(allocator, response_frame, default_response_excerpt_limit),
        };
    }

    const envelope = parsed.value.object;
    if (envelope.get("error")) |error_value| {
        var error_message_raw: []const u8 = "rpc error";
        var error_code: ?i64 = null;
        if (error_value == .object) {
            if (error_value.object.get("message")) |message_value| {
                if (message_value == .string) error_message_raw = message_value.string;
            }
            if (error_value.object.get("code")) |code_value| {
                error_code = intFromValue(code_value);
            }
        }
        return .{
            .ok = false,
            .approval_required = false,
            .state = try allocator.dupe(u8, "rpc_error"),
            .error_message = try allocator.dupe(u8, error_message_raw),
            .error_code = error_code,
            .preview = try previewAlloc(allocator, error_message_raw, default_summary_preview_limit),
            .response_excerpt = try excerptAlloc(allocator, response_frame, default_response_excerpt_limit),
        };
    }

    const result_value = envelope.get("result") orelse {
        return .{
            .ok = true,
            .approval_required = false,
            .preview = try allocator.dupe(u8, "delegated step completed"),
            .response_excerpt = try excerptAlloc(allocator, response_frame, default_response_excerpt_limit),
        };
    };

    if (result_value != .object) {
        const result_string = try gateway_response.stringifyJsonValue(allocator, result_value);
        defer allocator.free(result_string);
        return .{
            .ok = true,
            .approval_required = false,
            .preview = try previewAlloc(allocator, result_string, default_summary_preview_limit),
            .response_excerpt = try excerptAlloc(allocator, response_frame, default_response_excerpt_limit),
        };
    }

    const result_obj = result_value.object;
    const ok_flag = if (result_obj.get("ok")) |value| boolFromValue(value, true) else true;
    const state_raw = if (result_obj.get("state")) |value| switch (value) {
        .string => value.string,
        else => "",
    } else "";
    const approval_required = (result_obj.get("approvalRequired") != null and boolFromValue(result_obj.get("approvalRequired").?, false)) or std.ascii.eqlIgnoreCase(state_raw, "approval_required");
    const approval_id_raw = if (result_obj.get("approval")) |value| switch (value) {
        .object => if (value.object.get("approvalId")) |approval_value| switch (approval_value) {
            .string => approval_value.string,
            else => null,
        } else null,
        else => null,
    } else null;
    const preferred_error = extractPreferredText(result_obj, &.{ "message", "summary", "stderr", "state" });
    const error_message_raw: ?[]const u8 = if (preferred_error) |value| value else if (!ok_flag) "delegated step failed" else null;
    var preview_owned: []u8 = undefined;
    if (extractPreferredText(result_obj, &.{ "message", "summary", "stdout", "content", "state", "status", "processId", "jobId" })) |value| {
        preview_owned = try previewAlloc(allocator, value, default_summary_preview_limit);
    } else if (result_obj.get("count")) |count_value| {
        if (intFromValue(count_value)) |count| {
            const count_preview = try std.fmt.allocPrint(allocator, "count={d}", .{count});
            defer allocator.free(count_preview);
            preview_owned = try previewAlloc(allocator, count_preview, default_summary_preview_limit);
        } else {
            preview_owned = try previewAlloc(allocator, if (approval_required) "approval required" else if (ok_flag) "delegated step completed" else "delegated step failed", default_summary_preview_limit);
        }
    } else {
        preview_owned = try previewAlloc(allocator, if (approval_required) "approval required" else if (ok_flag) "delegated step completed" else "delegated step failed", default_summary_preview_limit);
    }

    return .{
        .ok = ok_flag and !approval_required,
        .approval_required = approval_required,
        .state = if (state_raw.len > 0) try allocator.dupe(u8, state_raw) else null,
        .approval_id = if (approval_id_raw) |value| try allocator.dupe(u8, value) else null,
        .error_message = if (error_message_raw) |value| try allocator.dupe(u8, value) else null,
        .preview = preview_owned,
        .response_excerpt = try excerptAlloc(allocator, response_frame, default_response_excerpt_limit),
    };
}

fn encodeFrame(
    allocator: std.mem.Allocator,
    id: []const u8,
    method: []const u8,
    params_value: std.json.Value,
) anyerror![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try std.json.Stringify.value(.{
        .id = id,
        .method = method,
        .params = params_value,
    }, .{}, &out.writer);
    return out.toOwnedSlice();
}

fn isDelegatableTool(method: []const u8) bool {
    return tool_contract.isPortableTool(method);
}

fn toolAllowedByToolsets(method: []const u8, toolsets_value: ?std.json.Value) bool {
    return tool_contract.toolAllowedByToolsets(method, toolsets_value);
}

fn toolsetAllows(toolset: []const u8, method: []const u8) bool {
    return tool_contract.toolsetAllows(toolset, method);
}

fn toolSupportedOnCurrentRuntime(method: []const u8) bool {
    return tool_contract.isSupportedOnTarget(method, builtin.os.tag);
}

fn methodUsesSession(method: []const u8) bool {
    return std.ascii.eqlIgnoreCase(method, "exec.run") or
        std.ascii.eqlIgnoreCase(method, "execute_code") or
        std.mem.startsWith(u8, method, "file.") or
        std.mem.startsWith(u8, method, "web.") or
        std.mem.startsWith(u8, method, "process.") or
        std.mem.startsWith(u8, method, "sessions.");
}

fn methodUsesCwd(method: []const u8) bool {
    return std.ascii.eqlIgnoreCase(method, "execute_code") or std.ascii.eqlIgnoreCase(method, "process.start");
}

fn getValue(params: ?std.json.ObjectMap, key: []const u8) ?std.json.Value {
    const object = params orelse return null;
    return object.get(key);
}

fn getString(params: ?std.json.ObjectMap, key: []const u8, fallback: []const u8) []const u8 {
    return gateway_request.firstParamString(params, key, fallback);
}

fn getBool(params: ?std.json.ObjectMap, key: []const u8, fallback: bool) bool {
    const object = params orelse return fallback;
    if (object.get(key)) |value| return boolFromValue(value, fallback);
    return fallback;
}

fn boolFromValue(value: std.json.Value, fallback: bool) bool {
    return switch (value) {
        .bool => value.bool,
        .string => |raw| blk: {
            const trimmed = std.mem.trim(u8, raw, " \t\r\n");
            if (trimmed.len == 0) break :blk fallback;
            if (std.ascii.eqlIgnoreCase(trimmed, "true") or std.ascii.eqlIgnoreCase(trimmed, "1") or std.ascii.eqlIgnoreCase(trimmed, "yes") or std.ascii.eqlIgnoreCase(trimmed, "on")) break :blk true;
            if (std.ascii.eqlIgnoreCase(trimmed, "false") or std.ascii.eqlIgnoreCase(trimmed, "0") or std.ascii.eqlIgnoreCase(trimmed, "no") or std.ascii.eqlIgnoreCase(trimmed, "off")) break :blk false;
            break :blk fallback;
        },
        .integer => |raw| raw != 0,
        .float => |raw| raw != 0,
        else => fallback,
    };
}

fn intFromValue(value: std.json.Value) ?i64 {
    return switch (value) {
        .integer => value.integer,
        .float => |raw| @intFromFloat(raw),
        .string => |raw| std.fmt.parseInt(i64, std.mem.trim(u8, raw, " \t\r\n"), 10) catch null,
        else => null,
    };
}

fn extractPreferredText(object: std.json.ObjectMap, keys: []const []const u8) ?[]const u8 {
    for (keys) |key| {
        if (object.get(key)) |value| {
            switch (value) {
                .string => |raw| {
                    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
                    if (trimmed.len > 0) return trimmed;
                },
                else => {},
            }
        }
    }
    return null;
}

fn previewAlloc(allocator: std.mem.Allocator, raw: []const u8, limit: usize) anyerror![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    var pending_space = false;
    var consumed: usize = 0;
    for (trimmed) |ch| {
        if (consumed >= limit) break;
        if (std.ascii.isWhitespace(ch)) {
            pending_space = out.items.len > 0;
            continue;
        }
        if (pending_space and out.items.len > 0) {
            try out.append(allocator, ' ');
            consumed += 1;
            if (consumed >= limit) break;
        }
        pending_space = false;
        try out.append(allocator, ch);
        consumed += 1;
    }
    if (trimmed.len > 0 and out.items.len == 0) try out.append(allocator, '.');
    if (trimmed.len > limit and out.items.len < limit + 3) {
        try out.appendSlice(allocator, "...");
    }
    return out.toOwnedSlice(allocator);
}

fn excerptAlloc(allocator: std.mem.Allocator, raw: []const u8, limit: usize) anyerror![]u8 {
    const capped_len = @min(raw.len, limit);
    if (raw.len <= limit) return allocator.dupe(u8, raw);
    var out = try allocator.alloc(u8, capped_len + 3);
    @memcpy(out[0..capped_len], raw[0..capped_len]);
    @memcpy(out[capped_len .. capped_len + 3], "...");
    return out;
}

test "delegate_task toolset gating blocks execution tool when only file toolset is enabled" {
    const allocator = std.testing.allocator;

    const stub = struct {
        fn invoke(_: void, a: std.mem.Allocator, frame_json: []const u8) ![]u8 {
            _ = frame_json;
            return a.dupe(u8, "{\"result\":{\"ok\":true}}" );
        }
    }.invoke;

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{
        \\  "tasks": [
        \\    {
        \\      "goal": "file only",
        \\      "toolsets": ["file"],
        \\      "steps": [
        \\        {"tool":"exec.run","command":"printf hi"}
        \\      ]
        \\    }
        \\  ]
        \\}
    , .{});
    defer parsed.deinit();
    var result = try run(allocator, parsed.value.object, {}, stub);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.results.len);
    try std.testing.expect(std.mem.eql(u8, result.results[0].status, "failed"));
    try std.testing.expect(std.mem.eql(u8, result.results[0].steps[0].status, "not_allowed"));
}

test "delegate_task approval state is surfaced through blocked delegated steps" {
    const allocator = std.testing.allocator;

    const stub = struct {
        fn invoke(_: void, a: std.mem.Allocator, frame_json: []const u8) ![]u8 {
            _ = frame_json;
            return a.dupe(u8,
                "{\"jsonrpc\":\"2.0\",\"id\":\"stub-1\",\"result\":{\"ok\":false,\"status\":409,\"state\":\"approval_required\",\"approvalRequired\":true,\"message\":\"approval required before execution can continue\",\"approval\":{\"approvalId\":\"approval-123\",\"status\":\"pending\"}}}"
            );
        }
    }.invoke;

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{
        \\  "goal": "approval delegated task",
        \\  "toolsets": ["terminal"],
        \\  "steps": [
        \\    {"tool":"exec.run","command":"printf hi"}
        \\  ]
        \\}
    , .{});
    defer parsed.deinit();
    var result = try run(allocator, parsed.value.object, {}, stub);
    defer result.deinit(allocator);

    try std.testing.expectEqual(false, result.ok);
    try std.testing.expectEqual(@as(usize, 1), result.blocked);
    try std.testing.expect(std.mem.eql(u8, result.results[0].status, "blocked"));
    try std.testing.expectEqual(@as(usize, 1), result.results[0].approvalRequiredCount);
    try std.testing.expect(std.mem.eql(u8, result.results[0].events[0].preview.?, "approval delegated task"));
    try std.testing.expect(std.mem.eql(u8, result.results[0].steps[0].state.?, "approval_required"));
    try std.testing.expect(std.mem.eql(u8, result.results[0].steps[0].approvalId.?, "approval-123"));
}

