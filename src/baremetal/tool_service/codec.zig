// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const package_store = @import("../package_store.zig");

pub const Error = std.mem.Allocator.Error || error{
    EmptyRequest,
    InvalidFrame,
    ResponseTooLarge,
};

pub const FramedCommandRequest = struct {
    request_id: u32,
    command: []const u8,
};

pub const RequestOp = enum {
    command,
    execute,
    get,
    put,
    stat,
    list,
    shell_expand,
    shell_run,
    tty_list,
    tty_open,
    tty_info,
    tty_read,
    tty_stdout,
    tty_stderr,
    tty_send,
    tty_close,
    storage_backends,
    storage_filesystems,
    storage_backend_info,
    storage_backend_select,
    storage_partitions,
    storage_partition_select,
    mount_list,
    mount_info,
    mount_bind,
    mount_remove,
    install,
    manifest,
    package_install,
    package_list,
    package_info,
    package_app,
    package_display,
    package_run,
    package_asset_put,
    package_asset_list,
    package_asset_get,
    package_verify,
    package_delete,
    package_release_list,
    package_release_info,
    package_release_save,
    package_release_activate,
    package_release_delete,
    package_release_prune,
    package_channel_list,
    package_channel_info,
    package_channel_set,
    package_channel_activate,
    app_list,
    app_info,
    app_state,
    app_history,
    app_stdout,
    app_stderr,
    app_trust,
    app_connector,
    app_plan_list,
    app_plan_info,
    app_plan_active,
    app_plan_save,
    app_plan_apply,
    app_plan_delete,
    app_suite_list,
    app_suite_info,
    app_suite_save,
    app_suite_apply,
    app_suite_run,
    app_suite_delete,
    app_suite_release_list,
    app_suite_release_info,
    app_suite_release_save,
    app_suite_release_activate,
    app_suite_release_delete,
    app_suite_release_prune,
    app_suite_channel_list,
    app_suite_channel_info,
    app_suite_channel_set,
    app_suite_channel_activate,
    workspace_plan_list,
    workspace_plan_info,
    workspace_plan_active,
    workspace_plan_save,
    workspace_plan_apply,
    workspace_plan_delete,
    workspace_plan_release_list,
    workspace_plan_release_info,
    workspace_plan_release_save,
    workspace_plan_release_activate,
    workspace_plan_release_delete,
    workspace_plan_release_prune,
    workspace_suite_list,
    workspace_suite_info,
    workspace_suite_save,
    workspace_suite_apply,
    workspace_suite_run,
    workspace_suite_delete,
    workspace_suite_release_list,
    workspace_suite_release_info,
    workspace_suite_release_save,
    workspace_suite_release_activate,
    workspace_suite_release_delete,
    workspace_suite_release_prune,
    workspace_suite_channel_list,
    workspace_suite_channel_info,
    workspace_suite_channel_set,
    workspace_suite_channel_activate,
    workspace_list,
    workspace_info,
    workspace_save,
    workspace_apply,
    workspace_run,
    workspace_state,
    workspace_history,
    workspace_stdout,
    workspace_stderr,
    workspace_delete,
    workspace_release_list,
    workspace_release_info,
    workspace_release_save,
    workspace_release_activate,
    workspace_release_delete,
    workspace_release_prune,
    workspace_channel_list,
    workspace_channel_info,
    workspace_channel_set,
    workspace_channel_activate,
    workspace_autorun_list,
    workspace_autorun_add,
    workspace_autorun_remove,
    workspace_autorun_run,
    app_run,
    app_delete,
    app_autorun_list,
    app_autorun_add,
    app_autorun_remove,
    app_autorun_run,
    display_info,
    display_outputs,
    display_output,
    display_output_detail,
    display_output_capabilities,
    display_output_modes,
    display_modes,
    display_set,
    display_activate,
    display_activate_preferred,
    display_activate_interface,
    display_activate_interface_preferred,
    display_interface_detail,
    display_interface_capabilities,
    display_interface_modes,
    display_interface_set,
    display_interface_activate_mode,
    display_activate_output,
    display_activate_output_preferred,
    display_output_set,
    display_output_activate_mode,
    display_profile_list,
    display_profile_info,
    display_profile_active,
    display_profile_save,
    display_profile_apply,
    display_profile_delete,
    trust_install,
    trust_list,
    trust_info,
    trust_active,
    trust_select,
    trust_delete,
    runtime_snapshot,
    runtime_sessions,
    runtime_session,
    runtime_call,
};

pub const PutRequest = struct {
    path: []const u8,
    body: []const u8,
};

pub const PackagePathRequest = struct {
    package_name: []const u8,
    relative_path: []const u8,
};

pub const PackagePutRequest = struct {
    package_name: []const u8,
    relative_path: []const u8,
    body: []const u8,
};

pub const PackageDisplayRequest = struct {
    package_name: []const u8,
    width: u16,
    height: u16,
};

pub const NamedValueRequest = struct {
    package_name: []const u8,
    value: []const u8,
};

pub const DisplayModeRequest = struct {
    width: u16,
    height: u16,
};

pub const DisplayOutputModeRequest = struct {
    index: u16,
    width: u16,
    height: u16,
};

pub const DisplayOutputModeIndexRequest = struct {
    index: u16,
    mode_index: u16,
};

pub const DisplayInterfaceModeRequest = struct {
    interface_name: []const u8,
    width: u16,
    height: u16,
};

pub const DisplayInterfaceModeIndexRequest = struct {
    interface_name: []const u8,
    mode_index: u16,
};

pub const TtySendRequest = struct {
    session_name: []const u8,
    command: []const u8,
};

pub const PackageReleasePruneRequest = struct {
    package_name: []const u8,
    keep: u32,
};

pub const WorkspaceReleaseRequest = struct {
    workspace_name: []const u8,
    release_name: []const u8,
};

pub const WorkspaceReleasePruneRequest = struct {
    workspace_name: []const u8,
    keep: u32,
};

pub const WorkspaceChannelRequest = struct {
    workspace_name: []const u8,
    value: []const u8,
};

pub const WorkspacePlanRequest = struct {
    workspace_name: []const u8,
    plan_name: []const u8,
};

pub const WorkspacePlanSaveRequest = struct {
    workspace_name: []const u8,
    plan_name: []const u8,
    suite_name: []const u8,
    trust_bundle: []const u8,
    width: u16,
    height: u16,
    entries_spec: []const u8,
};

pub const WorkspacePlanReleaseRequest = struct {
    workspace_name: []const u8,
    plan_name: []const u8,
    release_name: []const u8,
};

pub const WorkspacePlanReleasePruneRequest = struct {
    workspace_name: []const u8,
    plan_name: []const u8,
    keep: u32,
};

pub const WorkspaceChannelSetRequest = struct {
    workspace_name: []const u8,
    channel: []const u8,
    release: []const u8,
};

pub const PackageChannelSetRequest = struct {
    package_name: []const u8,
    channel: []const u8,
    release: []const u8,
};

pub const AppPlanSaveRequest = struct {
    package_name: []const u8,
    plan_name: []const u8,
    release_name: []const u8,
    trust_bundle: []const u8,
    connector_type: u8,
    width: u16,
    height: u16,
    autorun: bool,
};

pub const AppSuiteSaveRequest = struct {
    suite_name: []const u8,
    entries_spec: []const u8,
};

pub const AppSuiteReleaseRequest = struct {
    suite_name: []const u8,
    release_name: []const u8,
};

pub const AppSuiteReleasePruneRequest = struct {
    suite_name: []const u8,
    keep: u32,
};

pub const AppSuiteChannelRequest = struct {
    suite_name: []const u8,
    value: []const u8,
};

pub const AppSuiteChannelSetRequest = struct {
    suite_name: []const u8,
    channel: []const u8,
    release: []const u8,
};

pub const WorkspaceSaveRequest = struct {
    name: []const u8,
    suite_name: []const u8,
    trust_bundle: []const u8,
    width: u16,
    height: u16,
    entries_spec: []const u8,
};

pub const WorkspaceSuiteSaveRequest = struct {
    suite_name: []const u8,
    entries_spec: []const u8,
};

pub const WorkspaceSuiteReleaseRequest = struct {
    suite_name: []const u8,
    release_name: []const u8,
};

pub const WorkspaceSuiteReleasePruneRequest = struct {
    suite_name: []const u8,
    keep: u32,
};

pub const WorkspaceSuiteChannelRequest = struct {
    suite_name: []const u8,
    value: []const u8,
};

pub const WorkspaceSuiteChannelSetRequest = struct {
    suite_name: []const u8,
    channel: []const u8,
    release: []const u8,
};

pub const FramedRequest = struct {
    request_id: u32,
    operation: union(RequestOp) {
        command: []const u8,
        execute: []const u8,
        get: []const u8,
        put: PutRequest,
        stat: []const u8,
        list: []const u8,
        shell_expand: []const u8,
        shell_run: []const u8,
        tty_list: void,
        tty_open: []const u8,
        tty_info: []const u8,
        tty_read: []const u8,
        tty_stdout: []const u8,
        tty_stderr: []const u8,
        tty_send: TtySendRequest,
        tty_close: []const u8,
        storage_backends: void,
        storage_filesystems: void,
        storage_backend_info: []const u8,
        storage_backend_select: []const u8,
        storage_partitions: void,
        storage_partition_select: []const u8,
        mount_list: void,
        mount_info: []const u8,
        mount_bind: NamedValueRequest,
        mount_remove: []const u8,
        install: void,
        manifest: void,
        package_install: PutRequest,
        package_list: void,
        package_info: []const u8,
        package_app: []const u8,
        package_display: PackageDisplayRequest,
        package_run: []const u8,
        package_asset_put: PackagePutRequest,
        package_asset_list: []const u8,
        package_asset_get: PackagePathRequest,
        package_verify: []const u8,
        package_delete: []const u8,
        package_release_list: []const u8,
        package_release_info: NamedValueRequest,
        package_release_save: NamedValueRequest,
        package_release_activate: NamedValueRequest,
        package_release_delete: NamedValueRequest,
        package_release_prune: PackageReleasePruneRequest,
        package_channel_list: []const u8,
        package_channel_info: NamedValueRequest,
        package_channel_set: PackageChannelSetRequest,
        package_channel_activate: NamedValueRequest,
        app_list: void,
        app_info: []const u8,
        app_state: []const u8,
        app_history: []const u8,
        app_stdout: []const u8,
        app_stderr: []const u8,
        app_trust: NamedValueRequest,
        app_connector: NamedValueRequest,
        app_plan_list: []const u8,
        app_plan_info: NamedValueRequest,
        app_plan_active: []const u8,
        app_plan_save: AppPlanSaveRequest,
        app_plan_apply: NamedValueRequest,
        app_plan_delete: NamedValueRequest,
        app_suite_list: void,
        app_suite_info: []const u8,
        app_suite_save: AppSuiteSaveRequest,
        app_suite_apply: []const u8,
        app_suite_run: []const u8,
        app_suite_delete: []const u8,
        app_suite_release_list: []const u8,
        app_suite_release_info: AppSuiteReleaseRequest,
        app_suite_release_save: AppSuiteReleaseRequest,
        app_suite_release_activate: AppSuiteReleaseRequest,
        app_suite_release_delete: AppSuiteReleaseRequest,
        app_suite_release_prune: AppSuiteReleasePruneRequest,
        app_suite_channel_list: []const u8,
        app_suite_channel_info: AppSuiteChannelRequest,
        app_suite_channel_set: AppSuiteChannelSetRequest,
        app_suite_channel_activate: AppSuiteChannelRequest,
        workspace_plan_list: []const u8,
        workspace_plan_info: WorkspacePlanRequest,
        workspace_plan_active: []const u8,
        workspace_plan_save: WorkspacePlanSaveRequest,
        workspace_plan_apply: WorkspacePlanRequest,
        workspace_plan_delete: WorkspacePlanRequest,
        workspace_plan_release_list: WorkspacePlanRequest,
        workspace_plan_release_info: WorkspacePlanReleaseRequest,
        workspace_plan_release_save: WorkspacePlanReleaseRequest,
        workspace_plan_release_activate: WorkspacePlanReleaseRequest,
        workspace_plan_release_delete: WorkspacePlanReleaseRequest,
        workspace_plan_release_prune: WorkspacePlanReleasePruneRequest,
        workspace_suite_list: void,
        workspace_suite_info: []const u8,
        workspace_suite_save: WorkspaceSuiteSaveRequest,
        workspace_suite_apply: []const u8,
        workspace_suite_run: []const u8,
        workspace_suite_delete: []const u8,
        workspace_suite_release_list: []const u8,
        workspace_suite_release_info: WorkspaceSuiteReleaseRequest,
        workspace_suite_release_save: WorkspaceSuiteReleaseRequest,
        workspace_suite_release_activate: WorkspaceSuiteReleaseRequest,
        workspace_suite_release_delete: WorkspaceSuiteReleaseRequest,
        workspace_suite_release_prune: WorkspaceSuiteReleasePruneRequest,
        workspace_suite_channel_list: []const u8,
        workspace_suite_channel_info: WorkspaceSuiteChannelRequest,
        workspace_suite_channel_set: WorkspaceSuiteChannelSetRequest,
        workspace_suite_channel_activate: WorkspaceSuiteChannelRequest,
        workspace_list: void,
        workspace_info: []const u8,
        workspace_save: WorkspaceSaveRequest,
        workspace_apply: []const u8,
        workspace_run: []const u8,
        workspace_state: []const u8,
        workspace_history: []const u8,
        workspace_stdout: []const u8,
        workspace_stderr: []const u8,
        workspace_delete: []const u8,
        workspace_release_list: []const u8,
        workspace_release_info: WorkspaceReleaseRequest,
        workspace_release_save: WorkspaceReleaseRequest,
        workspace_release_activate: WorkspaceReleaseRequest,
        workspace_release_delete: WorkspaceReleaseRequest,
        workspace_release_prune: WorkspaceReleasePruneRequest,
        workspace_channel_list: []const u8,
        workspace_channel_info: WorkspaceChannelRequest,
        workspace_channel_set: WorkspaceChannelSetRequest,
        workspace_channel_activate: WorkspaceChannelRequest,
        workspace_autorun_list: void,
        workspace_autorun_add: []const u8,
        workspace_autorun_remove: []const u8,
        workspace_autorun_run: void,
        app_run: []const u8,
        app_delete: []const u8,
        app_autorun_list: void,
        app_autorun_add: []const u8,
        app_autorun_remove: []const u8,
        app_autorun_run: void,
        display_info: void,
        display_outputs: void,
        display_output: []const u8,
        display_output_detail: []const u8,
        display_output_capabilities: []const u8,
        display_output_modes: []const u8,
        display_modes: void,
        display_set: DisplayModeRequest,
        display_activate: []const u8,
        display_activate_preferred: []const u8,
        display_activate_interface: []const u8,
        display_activate_interface_preferred: []const u8,
        display_interface_detail: []const u8,
        display_interface_capabilities: []const u8,
        display_interface_modes: []const u8,
        display_interface_set: DisplayInterfaceModeRequest,
        display_interface_activate_mode: DisplayInterfaceModeIndexRequest,
        display_activate_output: []const u8,
        display_activate_output_preferred: []const u8,
        display_output_set: DisplayOutputModeRequest,
        display_output_activate_mode: DisplayOutputModeIndexRequest,
        display_profile_list: void,
        display_profile_info: []const u8,
        display_profile_active: void,
        display_profile_save: []const u8,
        display_profile_apply: []const u8,
        display_profile_delete: []const u8,
        trust_install: PutRequest,
        trust_list: void,
        trust_info: []const u8,
        trust_active: void,
        trust_select: []const u8,
        trust_delete: []const u8,
        runtime_snapshot: void,
        runtime_sessions: void,
        runtime_session: []const u8,
        runtime_call: []const u8,
    },
};

pub const ConsumedRequest = struct {
    framed: FramedRequest,
    consumed_len: usize,
};

pub fn parseFramedCommandRequest(request: []const u8) Error!FramedCommandRequest {
    const framed = try parseFramedRequest(request);
    return switch (framed.operation) {
        .command => |command| .{ .request_id = framed.request_id, .command = command },
        else => error.InvalidFrame,
    };
}

pub fn parseFramedRequest(request: []const u8) Error!FramedRequest {
    const consumed = try parseFramedRequestPrefix(request);
    if (trimLeftWhitespace(request[consumed.consumed_len..]).len != 0) return error.InvalidFrame;
    return consumed.framed;
}

pub const TokenSplit = struct {
    token: []const u8,
    rest: []const u8,
};

pub fn payloadLimitForResponse(response_limit: usize) usize {
    return if (response_limit > 32) response_limit - 32 else response_limit;
}

pub fn parseFramedRequestPrefix(request: []const u8) Error!ConsumedRequest {
    const trimmed = trimLeftWhitespace(request);
    if (trimmed.len == 0) return error.EmptyRequest;

    const prefix_len = request.len - trimmed.len;
    const newline_index = std.mem.indexOfScalar(u8, trimmed, '\n');
    const header_len = newline_index orelse trimmed.len;
    const header = std.mem.trim(u8, trimmed[0..header_len], " \t\r\n");
    if (header.len == 0) return error.EmptyRequest;
    if (!std.mem.startsWith(u8, header, "REQ ")) return error.InvalidFrame;

    const body = trimLeftWhitespace(header["REQ ".len..]);
    if (body.len == 0) return error.InvalidFrame;

    const request_id_part = try splitFirstToken(body);
    const request_id = std.fmt.parseUnsigned(u32, request_id_part.token, 10) catch return error.InvalidFrame;
    const remainder = request_id_part.rest;
    if (remainder.len == 0) return error.InvalidFrame;

    const op_part = splitFirstToken(remainder) catch {
        const consumed_len = if (newline_index) |idx| prefix_len + idx + 1 else request.len;
        return .{
            .framed = .{
                .request_id = request_id,
                .operation = .{ .command = remainder },
            },
            .consumed_len = consumed_len,
        };
    };

    if (std.ascii.eqlIgnoreCase(op_part.token, "CMD")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            const consumed_len = prefix_len + newline_index.? + 1;
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .command = op_part.rest } },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .command = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "EXEC")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            const consumed_len = prefix_len + newline_index.? + 1;
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .execute = op_part.rest } },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .execute = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "GET")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            const consumed_len = prefix_len + newline_index.? + 1;
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .get = op_part.rest } },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .get = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "STAT")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            const consumed_len = prefix_len + newline_index.? + 1;
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .stat = op_part.rest } },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .stat = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "LIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            const consumed_len = prefix_len + newline_index.? + 1;
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .list = op_part.rest } },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "SHELLEXPAND")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            const consumed_len = prefix_len + newline_index.? + 1;
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .shell_expand = op_part.rest } },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .shell_expand = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "SHELLRUN")) {
        const length_part = try splitFirstToken(op_part.rest);
        if (length_part.rest.len != 0) return error.InvalidFrame;
        const body_len = std.fmt.parseUnsigned(usize, length_part.token, 10) catch return error.InvalidFrame;
        const body_start = newline_index orelse return error.InvalidFrame;
        const payload_start = body_start + 1;
        if (trimmed.len < payload_start + body_len) return error.InvalidFrame;
        const body_payload = trimmed[payload_start .. payload_start + body_len];
        return .{
            .framed = .{
                .request_id = request_id,
                .operation = .{ .shell_run = body_payload },
            },
            .consumed_len = prefix_len + payload_start + body_len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TTYLIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .tty_list = {} } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TTYOPEN")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .tty_open = op_part.rest } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TTYINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .tty_info = op_part.rest } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TTYREAD")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .tty_read = op_part.rest } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TTYSTDOUT")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .tty_stdout = op_part.rest } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TTYSTDERR")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .tty_stderr = op_part.rest } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TTYSEND")) {
        const length_part = try splitFirstToken(op_part.rest);
        if (length_part.rest.len != 0) return error.InvalidFrame;
        const body_len = std.fmt.parseUnsigned(usize, length_part.token, 10) catch return error.InvalidFrame;
        const body_start = newline_index orelse return error.InvalidFrame;
        const payload_start = body_start + 1;
        if (trimmed.len < payload_start + body_len) return error.InvalidFrame;
        const body_payload = trimmed[payload_start .. payload_start + body_len];
        const session_part = try splitFirstToken(body_payload);
        if (session_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{
                .request_id = request_id,
                .operation = .{ .tty_send = .{
                    .session_name = session_part.token,
                    .command = session_part.rest,
                } },
            },
            .consumed_len = prefix_len + payload_start + body_len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TTYCLOSE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .tty_close = op_part.rest } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "STORAGEBACKENDS")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .storage_backends = {} } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "STORAGEFILESYSTEMS")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .storage_filesystems = {} } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "STORAGEBACKENDINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .storage_backend_info = op_part.rest } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "STORAGEBACKENDSELECT")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .storage_backend_select = op_part.rest } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "STORAGEPARTITIONS")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .storage_partitions = {} } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "STORAGEPARTITIONSELECT")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .storage_partition_select = op_part.rest } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "MOUNTLIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .mount_list = {} } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "MOUNTINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .mount_info = op_part.rest } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "MOUNTBIND")) {
        const name_part = try splitFirstToken(op_part.rest);
        const target_part = try splitFirstToken(name_part.rest);
        if (target_part.rest.len != 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .mount_bind = .{
                .package_name = name_part.token,
                .value = target_part.token,
            } } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "MOUNTREMOVE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .mount_remove = op_part.rest } },
            .consumed_len = if (newline_index != null) prefix_len + newline_index.? + 1 else request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "INSTALL")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .install = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .install = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "MANIFEST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .manifest = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .manifest = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGLIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGRUN")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_run = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_run = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_info = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_info = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGAPP")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_app = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_app = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGDISPLAY")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const width_part = try splitFirstToken(package_name_part.rest);
        const height_part = try splitFirstToken(width_part.rest);
        if (height_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .package_display = .{
                .package_name = package_name_part.token,
                .width = std.fmt.parseInt(u16, width_part.token, 10) catch return error.InvalidFrame,
                .height = std.fmt.parseInt(u16, height_part.token, 10) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGLS")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_asset_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_asset_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGGET")) {
        const name_part = try splitFirstToken(op_part.rest);
        if (name_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{
                    .request_id = request_id,
                    .operation = .{ .package_asset_get = .{
                        .package_name = name_part.token,
                        .relative_path = name_part.rest,
                    } },
                },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{
                .request_id = request_id,
                .operation = .{ .package_asset_get = .{
                    .package_name = name_part.token,
                    .relative_path = name_part.rest,
                } },
            },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGVERIFY")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_verify = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_verify = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGDELETE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_delete = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_delete = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGRELEASELIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_release_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_release_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGRELEASEINFO")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const release_name_part = try splitFirstToken(package_name_part.rest);
        if (release_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .package_release_info = .{
                .package_name = package_name_part.token,
                .value = release_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGRELEASESAVE")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const release_name_part = try splitFirstToken(package_name_part.rest);
        if (release_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .package_release_save = .{
                .package_name = package_name_part.token,
                .value = release_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGRELEASEACTIVATE")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const release_name_part = try splitFirstToken(package_name_part.rest);
        if (release_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .package_release_activate = .{
                .package_name = package_name_part.token,
                .value = release_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGRELEASEDELETE")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const release_name_part = try splitFirstToken(package_name_part.rest);
        if (release_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .package_release_delete = .{
                .package_name = package_name_part.token,
                .value = release_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGRELEASEPRUNE")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const keep_part = try splitFirstToken(package_name_part.rest);
        if (keep_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .package_release_prune = .{
                .package_name = package_name_part.token,
                .keep = std.fmt.parseInt(u32, keep_part.token, 10) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGCHANNELLIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_channel_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_channel_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGCHANNELINFO")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const channel_name_part = try splitFirstToken(package_name_part.rest);
        if (channel_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .package_channel_info = .{
                .package_name = package_name_part.token,
                .value = channel_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGCHANNELSET")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const channel_name_part = try splitFirstToken(package_name_part.rest);
        const release_name_part = try splitFirstToken(channel_name_part.rest);
        if (release_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .package_channel_set = .{
                .package_name = package_name_part.token,
                .channel = channel_name_part.token,
                .release = release_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGCHANNELACTIVATE")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const channel_name_part = try splitFirstToken(package_name_part.rest);
        if (channel_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .package_channel_activate = .{
                .package_name = package_name_part.token,
                .value = channel_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPLIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_info = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_info = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSTATE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_state = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_state = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPHISTORY")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_history = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_history = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSTDOUT")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_stdout = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_stdout = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSTDERR")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_stderr = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_stderr = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPTRUST")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const trust_name_part = try splitFirstToken(package_name_part.rest);
        if (trust_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_trust = .{
                .package_name = package_name_part.token,
                .value = trust_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPCONNECTOR")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const connector_part = try splitFirstToken(package_name_part.rest);
        if (connector_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_connector = .{
                .package_name = package_name_part.token,
                .value = connector_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPPLANLIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_plan_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_plan_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPPLANINFO")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const plan_name_part = try splitFirstToken(package_name_part.rest);
        if (plan_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_plan_info = .{
                .package_name = package_name_part.token,
                .value = plan_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPPLANACTIVE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_plan_active = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_plan_active = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPPLANSAVE")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const plan_name_part = try splitFirstToken(package_name_part.rest);
        const release_name_part = try splitFirstToken(plan_name_part.rest);
        const trust_name_part = try splitFirstToken(release_name_part.rest);
        const connector_part = try splitFirstToken(trust_name_part.rest);
        const width_part = try splitFirstToken(connector_part.rest);
        const height_part = try splitFirstToken(width_part.rest);
        const autorun_part = try splitFirstToken(height_part.rest);
        if (autorun_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_plan_save = .{
                .package_name = package_name_part.token,
                .plan_name = plan_name_part.token,
                .release_name = if (std.ascii.eqlIgnoreCase(release_name_part.token, "none")) "" else release_name_part.token,
                .trust_bundle = if (std.ascii.eqlIgnoreCase(trust_name_part.token, "none")) "" else trust_name_part.token,
                .connector_type = package_store.parseConnectorType(connector_part.token) catch return error.InvalidFrame,
                .width = std.fmt.parseInt(u16, width_part.token, 10) catch return error.InvalidFrame,
                .height = std.fmt.parseInt(u16, height_part.token, 10) catch return error.InvalidFrame,
                .autorun = parseBooleanToken(autorun_part.token) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPPLANAPPLY")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const plan_name_part = try splitFirstToken(package_name_part.rest);
        if (plan_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_plan_apply = .{
                .package_name = package_name_part.token,
                .value = plan_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPPLANDELETE")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const plan_name_part = try splitFirstToken(package_name_part.rest);
        if (plan_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_plan_delete = .{
                .package_name = package_name_part.token,
                .value = plan_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITELIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_suite_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_suite_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITEINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_suite_info = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_suite_info = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITESAVE")) {
        const suite_name_part = try splitFirstToken(op_part.rest);
        if (suite_name_part.rest.len == 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_suite_save = .{
                .suite_name = suite_name_part.token,
                .entries_spec = suite_name_part.rest,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITEAPPLY")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_suite_apply = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_suite_apply = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITERUN")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_suite_run = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_suite_run = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITEDELETE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_suite_delete = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_suite_delete = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITERELEASELIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_suite_release_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_suite_release_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITERELEASEINFO")) {
        const suite_name_part = try splitFirstToken(op_part.rest);
        const release_name_part = try splitFirstToken(suite_name_part.rest);
        if (release_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_suite_release_info = .{
                .suite_name = suite_name_part.token,
                .release_name = release_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITERELEASESAVE")) {
        const suite_name_part = try splitFirstToken(op_part.rest);
        const release_name_part = try splitFirstToken(suite_name_part.rest);
        if (release_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_suite_release_save = .{
                .suite_name = suite_name_part.token,
                .release_name = release_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITERELEASEACTIVATE")) {
        const suite_name_part = try splitFirstToken(op_part.rest);
        const release_name_part = try splitFirstToken(suite_name_part.rest);
        if (release_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_suite_release_activate = .{
                .suite_name = suite_name_part.token,
                .release_name = release_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITERELEASEDELETE")) {
        const suite_name_part = try splitFirstToken(op_part.rest);
        const release_name_part = try splitFirstToken(suite_name_part.rest);
        if (release_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_suite_release_delete = .{
                .suite_name = suite_name_part.token,
                .release_name = release_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITERELEASEPRUNE")) {
        const suite_name_part = try splitFirstToken(op_part.rest);
        const keep_part = try splitFirstToken(suite_name_part.rest);
        if (keep_part.rest.len != 0) return error.InvalidFrame;
        const keep = std.fmt.parseInt(u32, keep_part.token, 10) catch return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_suite_release_prune = .{
                .suite_name = suite_name_part.token,
                .keep = keep,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITECHANNELLIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_suite_channel_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_suite_channel_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITECHANNELINFO")) {
        const suite_name_part = try splitFirstToken(op_part.rest);
        const channel_name_part = try splitFirstToken(suite_name_part.rest);
        if (channel_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_suite_channel_info = .{
                .suite_name = suite_name_part.token,
                .value = channel_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITECHANNELSET")) {
        const suite_name_part = try splitFirstToken(op_part.rest);
        const channel_name_part = try splitFirstToken(suite_name_part.rest);
        const release_name_part = try splitFirstToken(channel_name_part.rest);
        if (release_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_suite_channel_set = .{
                .suite_name = suite_name_part.token,
                .channel = channel_name_part.token,
                .release = release_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSUITECHANNELACTIVATE")) {
        const suite_name_part = try splitFirstToken(op_part.rest);
        const channel_name_part = try splitFirstToken(suite_name_part.rest);
        if (channel_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_suite_channel_activate = .{
                .suite_name = suite_name_part.token,
                .value = channel_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITELIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITEINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_info = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_info = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITESAVE")) {
        const suite_name = try splitFirstToken(op_part.rest);
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_suite_save = .{
                .suite_name = suite_name.token,
                .entries_spec = suite_name.rest,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITEAPPLY")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_apply = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_apply = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITERUN")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_run = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_run = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITEDELETE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_delete = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_delete = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITERELEASELIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_release_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_release_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITERELEASEINFO")) {
        const suite_name = try splitFirstToken(op_part.rest);
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_suite_release_info = .{
                .suite_name = suite_name.token,
                .release_name = suite_name.rest,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITERELEASESAVE")) {
        const suite_name = try splitFirstToken(op_part.rest);
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_suite_release_save = .{
                .suite_name = suite_name.token,
                .release_name = suite_name.rest,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITERELEASEACTIVATE")) {
        const suite_name = try splitFirstToken(op_part.rest);
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_suite_release_activate = .{
                .suite_name = suite_name.token,
                .release_name = suite_name.rest,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITERELEASEDELETE")) {
        const suite_name = try splitFirstToken(op_part.rest);
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_suite_release_delete = .{
                .suite_name = suite_name.token,
                .release_name = suite_name.rest,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITERELEASEPRUNE")) {
        const suite_name = try splitFirstToken(op_part.rest);
        if (suite_name.rest.len == 0) return error.InvalidFrame;
        const keep = std.fmt.parseInt(u32, suite_name.rest, 10) catch return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_suite_release_prune = .{
                .suite_name = suite_name.token,
                .keep = keep,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITECHANNELLIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_channel_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_suite_channel_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITECHANNELINFO")) {
        const suite_name = try splitFirstToken(op_part.rest);
        if (suite_name.rest.len == 0) return error.InvalidFrame;
        const channel_name = try splitFirstToken(suite_name.rest);
        if (channel_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_suite_channel_info = .{
                .suite_name = suite_name.token,
                .value = channel_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITECHANNELSET")) {
        const suite_name = try splitFirstToken(op_part.rest);
        if (suite_name.rest.len == 0) return error.InvalidFrame;
        const channel_name = try splitFirstToken(suite_name.rest);
        if (channel_name.rest.len == 0) return error.InvalidFrame;
        const release_name = try splitFirstToken(channel_name.rest);
        if (release_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_suite_channel_set = .{
                .suite_name = suite_name.token,
                .channel = channel_name.token,
                .release = release_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESUITECHANNELACTIVATE")) {
        const suite_name = try splitFirstToken(op_part.rest);
        if (suite_name.rest.len == 0) return error.InvalidFrame;
        const channel_name = try splitFirstToken(suite_name.rest);
        if (channel_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_suite_channel_activate = .{
                .suite_name = suite_name.token,
                .value = channel_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANLIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_plan_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_plan_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANINFO")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        if (workspace_name.rest.len == 0) return error.InvalidFrame;
        const plan_name = try splitFirstToken(workspace_name.rest);
        if (plan_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_plan_info = .{
                .workspace_name = workspace_name.token,
                .plan_name = plan_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANACTIVE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_plan_active = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_plan_active = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANSAVE")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        const plan_name = try splitFirstToken(workspace_name.rest);
        const suite_name = try splitFirstToken(plan_name.rest);
        const trust_bundle = try splitFirstToken(suite_name.rest);
        const width_part = try splitFirstToken(trust_bundle.rest);
        const height_part = try splitFirstToken(width_part.rest);
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_plan_save = .{
                .workspace_name = workspace_name.token,
                .plan_name = plan_name.token,
                .suite_name = suite_name.token,
                .trust_bundle = trust_bundle.token,
                .width = std.fmt.parseInt(u16, width_part.token, 10) catch return error.InvalidFrame,
                .height = std.fmt.parseInt(u16, height_part.token, 10) catch return error.InvalidFrame,
                .entries_spec = height_part.rest,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANAPPLY")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        if (workspace_name.rest.len == 0) return error.InvalidFrame;
        const plan_name = try splitFirstToken(workspace_name.rest);
        if (plan_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_plan_apply = .{
                .workspace_name = workspace_name.token,
                .plan_name = plan_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANDELETE")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        if (workspace_name.rest.len == 0) return error.InvalidFrame;
        const plan_name = try splitFirstToken(workspace_name.rest);
        if (plan_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_plan_delete = .{
                .workspace_name = workspace_name.token,
                .plan_name = plan_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANRELEASELIST")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        if (workspace_name.rest.len == 0) return error.InvalidFrame;
        const plan_name = try splitFirstToken(workspace_name.rest);
        if (plan_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_plan_release_list = .{
                .workspace_name = workspace_name.token,
                .plan_name = plan_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANRELEASEINFO")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        if (workspace_name.rest.len == 0) return error.InvalidFrame;
        const plan_name = try splitFirstToken(workspace_name.rest);
        if (plan_name.rest.len == 0) return error.InvalidFrame;
        const release_name = try splitFirstToken(plan_name.rest);
        if (release_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_plan_release_info = .{
                .workspace_name = workspace_name.token,
                .plan_name = plan_name.token,
                .release_name = release_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANRELEASESAVE")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        if (workspace_name.rest.len == 0) return error.InvalidFrame;
        const plan_name = try splitFirstToken(workspace_name.rest);
        if (plan_name.rest.len == 0) return error.InvalidFrame;
        const release_name = try splitFirstToken(plan_name.rest);
        if (release_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_plan_release_save = .{
                .workspace_name = workspace_name.token,
                .plan_name = plan_name.token,
                .release_name = release_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANRELEASEACTIVATE")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        if (workspace_name.rest.len == 0) return error.InvalidFrame;
        const plan_name = try splitFirstToken(workspace_name.rest);
        if (plan_name.rest.len == 0) return error.InvalidFrame;
        const release_name = try splitFirstToken(plan_name.rest);
        if (release_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_plan_release_activate = .{
                .workspace_name = workspace_name.token,
                .plan_name = plan_name.token,
                .release_name = release_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANRELEASEDELETE")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        if (workspace_name.rest.len == 0) return error.InvalidFrame;
        const plan_name = try splitFirstToken(workspace_name.rest);
        if (plan_name.rest.len == 0) return error.InvalidFrame;
        const release_name = try splitFirstToken(plan_name.rest);
        if (release_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_plan_release_delete = .{
                .workspace_name = workspace_name.token,
                .plan_name = plan_name.token,
                .release_name = release_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEPLANRELEASEPRUNE")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        if (workspace_name.rest.len == 0) return error.InvalidFrame;
        const plan_name = try splitFirstToken(workspace_name.rest);
        if (plan_name.rest.len == 0) return error.InvalidFrame;
        const keep_part = try splitFirstToken(plan_name.rest);
        if (keep_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_plan_release_prune = .{
                .workspace_name = workspace_name.token,
                .plan_name = plan_name.token,
                .keep = std.fmt.parseInt(u32, keep_part.token, 10) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACELIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_info = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_info = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESAVE")) {
        const name_part = try splitFirstToken(op_part.rest);
        const suite_part = try splitFirstToken(name_part.rest);
        const trust_part = try splitFirstToken(suite_part.rest);
        const width_part = try splitFirstToken(trust_part.rest);
        const height_part = try splitFirstToken(width_part.rest);
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_save = .{
                .name = name_part.token,
                .suite_name = suite_part.token,
                .trust_bundle = trust_part.token,
                .width = std.fmt.parseInt(u16, width_part.token, 10) catch return error.InvalidFrame,
                .height = std.fmt.parseInt(u16, height_part.token, 10) catch return error.InvalidFrame,
                .entries_spec = height_part.rest,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEAPPLY")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_apply = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_apply = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACERUN")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_run = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_run = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESTATE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_state = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_state = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEHISTORY")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_history = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_history = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESTDOUT")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_stdout = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_stdout = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACESTDERR")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_stderr = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_stderr = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEDELETE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_delete = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_delete = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACERELEASELIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_release_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_release_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACERELEASEINFO")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        const release_name = try splitFirstToken(workspace_name.rest);
        if (release_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_release_info = .{
                .workspace_name = workspace_name.token,
                .release_name = release_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACERELEASESAVE")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        const release_name = try splitFirstToken(workspace_name.rest);
        if (release_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_release_save = .{
                .workspace_name = workspace_name.token,
                .release_name = release_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACERELEASEACTIVATE")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        const release_name = try splitFirstToken(workspace_name.rest);
        if (release_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_release_activate = .{
                .workspace_name = workspace_name.token,
                .release_name = release_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACERELEASEDELETE")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        const release_name = try splitFirstToken(workspace_name.rest);
        if (release_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_release_delete = .{
                .workspace_name = workspace_name.token,
                .release_name = release_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACERELEASEPRUNE")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        const keep = try splitFirstToken(workspace_name.rest);
        if (keep.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_release_prune = .{
                .workspace_name = workspace_name.token,
                .keep = std.fmt.parseInt(u32, keep.token, 10) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACECHANNELLIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_channel_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_channel_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACECHANNELINFO")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        const channel_name = try splitFirstToken(workspace_name.rest);
        if (channel_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_channel_info = .{
                .workspace_name = workspace_name.token,
                .value = channel_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACECHANNELSET")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        const channel_name = try splitFirstToken(workspace_name.rest);
        const release_name = try splitFirstToken(channel_name.rest);
        if (release_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_channel_set = .{
                .workspace_name = workspace_name.token,
                .channel = channel_name.token,
                .release = release_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACECHANNELACTIVATE")) {
        const workspace_name = try splitFirstToken(op_part.rest);
        const channel_name = try splitFirstToken(workspace_name.rest);
        if (channel_name.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .workspace_channel_activate = .{
                .workspace_name = workspace_name.token,
                .value = channel_name.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEAUTORUNLIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_autorun_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_autorun_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEAUTORUNADD")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_autorun_add = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_autorun_add = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEAUTORUNREMOVE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_autorun_remove = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_autorun_remove = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "WORKSPACEAUTORUNRUN")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .workspace_autorun_run = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .workspace_autorun_run = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPRUN")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_run = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_run = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPDELETE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_delete = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_delete = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPAUTORUNLIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_autorun_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_autorun_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPAUTORUNADD")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_autorun_add = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_autorun_add = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPAUTORUNREMOVE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_autorun_remove = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_autorun_remove = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPAUTORUNRUN")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_autorun_run = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_autorun_run = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYINFO")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_info = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_info = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYOUTPUTS")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_outputs = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_outputs = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYOUTPUT")) {
        const output_index_part = try splitFirstToken(op_part.rest);
        if (output_index_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_output = output_index_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_output = output_index_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYOUTPUTDETAIL")) {
        const output_index_part = try splitFirstToken(op_part.rest);
        if (output_index_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_output_detail = output_index_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_output_detail = output_index_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYOUTPUTCAPABILITIES")) {
        const output_index_part = try splitFirstToken(op_part.rest);
        if (output_index_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_output_capabilities = output_index_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_output_capabilities = output_index_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYOUTPUTMODES")) {
        const output_index_part = try splitFirstToken(op_part.rest);
        if (output_index_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_output_modes = output_index_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_output_modes = output_index_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYMODES")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_modes = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_modes = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYSET")) {
        const width_part = try splitFirstToken(op_part.rest);
        const height_part = try splitFirstToken(width_part.rest);
        if (height_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .display_set = .{
                .width = std.fmt.parseInt(u16, width_part.token, 10) catch return error.InvalidFrame,
                .height = std.fmt.parseInt(u16, height_part.token, 10) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYACTIVATE")) {
        const connector_part = try splitFirstToken(op_part.rest);
        if (connector_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_activate = connector_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_activate = connector_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYACTIVATEPREFERRED")) {
        const connector_part = try splitFirstToken(op_part.rest);
        if (connector_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_activate_preferred = connector_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_activate_preferred = connector_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYACTIVATEINTERFACE")) {
        const interface_part = try splitFirstToken(op_part.rest);
        if (interface_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_activate_interface = interface_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_activate_interface = interface_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYACTIVATEINTERFACEPREFERRED")) {
        const interface_part = try splitFirstToken(op_part.rest);
        if (interface_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_activate_interface_preferred = interface_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_activate_interface_preferred = interface_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYINTERFACEDETAIL")) {
        const interface_part = try splitFirstToken(op_part.rest);
        if (interface_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_interface_detail = interface_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_interface_detail = interface_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYINTERFACECAPABILITIES")) {
        const interface_part = try splitFirstToken(op_part.rest);
        if (interface_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_interface_capabilities = interface_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_interface_capabilities = interface_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYINTERFACEMODES")) {
        const interface_part = try splitFirstToken(op_part.rest);
        if (interface_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_interface_modes = interface_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_interface_modes = interface_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYINTERFACESET")) {
        const interface_part = try splitFirstToken(op_part.rest);
        const width_part = try splitFirstToken(interface_part.rest);
        const height_part = try splitFirstToken(width_part.rest);
        if (height_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .display_interface_set = .{
                .interface_name = interface_part.token,
                .width = std.fmt.parseInt(u16, width_part.token, 10) catch return error.InvalidFrame,
                .height = std.fmt.parseInt(u16, height_part.token, 10) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYINTERFACEACTIVATEMODE")) {
        const interface_part = try splitFirstToken(op_part.rest);
        const mode_part = try splitFirstToken(interface_part.rest);
        if (mode_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .display_interface_activate_mode = .{
                .interface_name = interface_part.token,
                .mode_index = std.fmt.parseInt(u16, mode_part.token, 10) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYACTIVATEOUTPUT")) {
        const output_part = try splitFirstToken(op_part.rest);
        if (output_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_activate_output = output_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_activate_output = output_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYACTIVATEOUTPUTPREFERRED")) {
        const output_part = try splitFirstToken(op_part.rest);
        if (output_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_activate_output_preferred = output_part.token } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_activate_output_preferred = output_part.token } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYOUTPUTSET")) {
        const output_part = try splitFirstToken(op_part.rest);
        const width_part = try splitFirstToken(output_part.rest);
        const height_part = try splitFirstToken(width_part.rest);
        if (height_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .display_output_set = .{
                .index = std.fmt.parseInt(u16, output_part.token, 10) catch return error.InvalidFrame,
                .width = std.fmt.parseInt(u16, width_part.token, 10) catch return error.InvalidFrame,
                .height = std.fmt.parseInt(u16, height_part.token, 10) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYOUTPUTACTIVATEMODE")) {
        const output_part = try splitFirstToken(op_part.rest);
        const mode_part = try splitFirstToken(output_part.rest);
        if (mode_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .display_output_activate_mode = .{
                .index = std.fmt.parseInt(u16, output_part.token, 10) catch return error.InvalidFrame,
                .mode_index = std.fmt.parseInt(u16, mode_part.token, 10) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYPROFILELIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_profile_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_profile_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYPROFILEINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_profile_info = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_profile_info = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYPROFILEACTIVE")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_profile_active = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_profile_active = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYPROFILESAVE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_profile_save = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_profile_save = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYPROFILEAPPLY")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_profile_apply = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_profile_apply = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYPROFILEDELETE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_profile_delete = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_profile_delete = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTLIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .trust_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .trust_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .trust_info = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .trust_info = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTACTIVE")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .trust_active = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .trust_active = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTSELECT")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .trust_select = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .trust_select = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTDELETE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .trust_delete = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .trust_delete = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "RUNTIMESNAPSHOT")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .runtime_snapshot = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .runtime_snapshot = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "RUNTIMESESSIONS")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .runtime_sessions = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .runtime_sessions = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "RUNTIMESESSION")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .runtime_session = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .runtime_session = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "RUNTIMECALL")) {
        const length_part = try splitFirstToken(op_part.rest);
        if (length_part.rest.len != 0) return error.InvalidFrame;
        const body_len = std.fmt.parseUnsigned(usize, length_part.token, 10) catch return error.InvalidFrame;
        const body_start = newline_index orelse return error.InvalidFrame;
        const payload_start = body_start + 1;
        if (trimmed.len < payload_start + body_len) return error.InvalidFrame;
        const body_payload = trimmed[payload_start .. payload_start + body_len];
        return .{
            .framed = .{
                .request_id = request_id,
                .operation = .{ .runtime_call = body_payload },
            },
            .consumed_len = prefix_len + payload_start + body_len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGPUT")) {
        const name_part = try splitFirstToken(op_part.rest);
        const path_part = try splitFirstToken(name_part.rest);
        const length_part = try splitFirstToken(path_part.rest);
        if (length_part.rest.len != 0) return error.InvalidFrame;
        const body_len = std.fmt.parseUnsigned(usize, length_part.token, 10) catch return error.InvalidFrame;
        const body_start = newline_index orelse return error.InvalidFrame;
        const payload_start = body_start + 1;
        if (trimmed.len < payload_start + body_len) return error.InvalidFrame;
        const body_payload = trimmed[payload_start .. payload_start + body_len];
        return .{
            .framed = .{
                .request_id = request_id,
                .operation = .{ .package_asset_put = .{
                    .package_name = name_part.token,
                    .relative_path = path_part.token,
                    .body = body_payload,
                } },
            },
            .consumed_len = prefix_len + payload_start + body_len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PUT") or
        std.ascii.eqlIgnoreCase(op_part.token, "PKG") or
        std.ascii.eqlIgnoreCase(op_part.token, "TRUSTPUT"))
    {
        const path_part = try splitFirstToken(op_part.rest);
        const length_part = try splitFirstToken(path_part.rest);
        if (length_part.rest.len != 0) return error.InvalidFrame;
        const body_len = std.fmt.parseUnsigned(usize, length_part.token, 10) catch return error.InvalidFrame;
        const body_start = newline_index orelse return error.InvalidFrame;
        const payload_start = body_start + 1;
        if (trimmed.len < payload_start + body_len) return error.InvalidFrame;
        const body_payload = trimmed[payload_start .. payload_start + body_len];
        const consumed_len = prefix_len + payload_start + body_len;
        if (std.ascii.eqlIgnoreCase(op_part.token, "PUT")) {
            return .{
                .framed = .{
                    .request_id = request_id,
                    .operation = .{ .put = .{ .path = path_part.token, .body = body_payload } },
                },
                .consumed_len = consumed_len,
            };
        }
        if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTPUT")) {
            return .{
                .framed = .{
                    .request_id = request_id,
                    .operation = .{ .trust_install = .{ .path = path_part.token, .body = body_payload } },
                },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{
                .request_id = request_id,
                .operation = .{ .package_install = .{ .path = path_part.token, .body = body_payload } },
            },
            .consumed_len = consumed_len,
        };
    }

    if (newline_index != null) {
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .command = remainder } },
            .consumed_len = prefix_len + newline_index.? + 1,
        };
    }
    return .{
        .framed = .{ .request_id = request_id, .operation = .{ .command = remainder } },
        .consumed_len = request.len,
    };
}

pub fn splitFirstToken(text: []const u8) Error!TokenSplit {
    const trimmed = trimLeftWhitespace(text);
    if (trimmed.len == 0) return error.InvalidFrame;

    var idx: usize = 0;
    while (idx < trimmed.len and !std.ascii.isWhitespace(trimmed[idx])) : (idx += 1) {}
    return .{
        .token = trimmed[0..idx],
        .rest = trimLeftWhitespace(trimmed[idx..]),
    };
}

pub fn parseBooleanToken(text: []const u8) Error!bool {
    if (std.mem.eql(u8, text, "1") or std.ascii.eqlIgnoreCase(text, "true") or std.ascii.eqlIgnoreCase(text, "yes")) {
        return true;
    }
    if (std.mem.eql(u8, text, "0") or std.ascii.eqlIgnoreCase(text, "false") or std.ascii.eqlIgnoreCase(text, "no")) {
        return false;
    }
    return error.InvalidFrame;
}

pub fn formatFramedResponse(
    allocator: std.mem.Allocator,
    request_id: u32,
    payload: []const u8,
    response_limit: usize,
) Error![]u8 {
    const response = try std.fmt.allocPrint(allocator, "RESP {d} {d}\n{s}", .{ request_id, payload.len, payload });
    errdefer allocator.free(response);
    if (response.len > response_limit) return error.ResponseTooLarge;
    return response;
}

pub fn trimLeftWhitespace(text: []const u8) []const u8 {
    var index: usize = 0;
    while (index < text.len and std.ascii.isWhitespace(text[index])) : (index += 1) {}
    return text[index..];
}
