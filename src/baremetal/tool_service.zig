// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");
const app_runtime = @import("app_runtime.zig");
const disk_installer = @import("disk_installer.zig");
const display_output = @import("display_output.zig");
const display_profile_store = @import("display_profile_store.zig");
const filesystem = @import("filesystem.zig");
const framebuffer_console = @import("framebuffer_console.zig");
const pal_framebuffer = @import("../pal/framebuffer.zig");
const package_store = @import("package_store.zig");
const runtime_bridge = @import("runtime_bridge.zig");
const storage_backend = @import("storage_backend.zig");
const trust_store = @import("trust_store.zig");
const tool_exec = @import("tool_exec.zig");
const tool_layout = @import("tool_layout.zig");
const workspace_runtime = @import("workspace_runtime.zig");
const codec = @import("tool_service/codec.zig");

pub const Error = tool_exec.Error || package_store.Error || trust_store.Error || std.mem.Allocator.Error || error{
    EmptyRequest,
    InvalidFrame,
    ResponseTooLarge,
};

pub const FramedCommandRequest = codec.FramedCommandRequest;
pub const RequestOp = codec.RequestOp;
pub const PutRequest = codec.PutRequest;
pub const PackagePathRequest = codec.PackagePathRequest;
pub const PackagePutRequest = codec.PackagePutRequest;
pub const PackageDisplayRequest = codec.PackageDisplayRequest;
pub const NamedValueRequest = codec.NamedValueRequest;
pub const DisplayModeRequest = codec.DisplayModeRequest;
pub const PackageReleasePruneRequest = codec.PackageReleasePruneRequest;
pub const PackageChannelSetRequest = codec.PackageChannelSetRequest;
pub const AppPlanSaveRequest = codec.AppPlanSaveRequest;
pub const AppSuiteSaveRequest = codec.AppSuiteSaveRequest;
pub const AppSuiteChannelRequest = codec.AppSuiteChannelRequest;
pub const AppSuiteChannelSetRequest = codec.AppSuiteChannelSetRequest;
pub const WorkspacePlanRequest = codec.WorkspacePlanRequest;
pub const WorkspacePlanReleaseRequest = codec.WorkspacePlanReleaseRequest;
pub const WorkspacePlanReleasePruneRequest = codec.WorkspacePlanReleasePruneRequest;
pub const WorkspacePlanSaveRequest = codec.WorkspacePlanSaveRequest;
pub const WorkspaceSaveRequest = codec.WorkspaceSaveRequest;
pub const WorkspaceSuiteSaveRequest = codec.WorkspaceSuiteSaveRequest;
pub const WorkspaceSuiteReleaseRequest = codec.WorkspaceSuiteReleaseRequest;
pub const WorkspaceSuiteReleasePruneRequest = codec.WorkspaceSuiteReleasePruneRequest;
pub const WorkspaceSuiteChannelRequest = codec.WorkspaceSuiteChannelRequest;
pub const WorkspaceSuiteChannelSetRequest = codec.WorkspaceSuiteChannelSetRequest;
pub const WorkspaceReleaseRequest = codec.WorkspaceReleaseRequest;
pub const WorkspaceReleasePruneRequest = codec.WorkspaceReleasePruneRequest;
pub const WorkspaceChannelRequest = codec.WorkspaceChannelRequest;
pub const WorkspaceChannelSetRequest = codec.WorkspaceChannelSetRequest;
pub const FramedRequest = codec.FramedRequest;
const ConsumedRequest = codec.ConsumedRequest;

pub fn handleCommandRequest(
    allocator: std.mem.Allocator,
    request: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    const trimmed = std.mem.trim(u8, request, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyRequest;

    var result = try tool_exec.runCaptureSilent(allocator, trimmed, stdout_limit, stderr_limit);
    defer result.deinit(allocator);

    if (result.exit_code == 0 and result.stderr.len == 0) {
        if (result.stdout.len > response_limit) return error.ResponseTooLarge;
        return allocator.dupe(u8, result.stdout);
    }

    const detail = if (result.stderr.len != 0) result.stderr else result.stdout;
    const response = try std.fmt.allocPrint(allocator, "ERR exit={d}\n{s}", .{ result.exit_code, detail });
    errdefer allocator.free(response);
    if (response.len > response_limit) return error.ResponseTooLarge;
    return response;
}

pub fn parseFramedCommandRequest(request: []const u8) Error!FramedCommandRequest {
    return codec.parseFramedCommandRequest(request);
}

pub fn parseFramedRequest(request: []const u8) Error!FramedRequest {
    return codec.parseFramedRequest(request);
}

pub fn handleFramedCommandRequest(
    allocator: std.mem.Allocator,
    request: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    const framed = try parseFramedCommandRequest(request);
    const payload_limit = payloadLimitForResponse(response_limit);
    const payload = try handleCommandRequest(allocator, framed.command, stdout_limit, stderr_limit, payload_limit);
    defer allocator.free(payload);

    return formatFramedResponse(allocator, framed.request_id, payload, response_limit);
}

pub fn handleFramedRequest(
    allocator: std.mem.Allocator,
    request: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    const framed = try parseFramedRequest(request);
    return handleFramedResponse(allocator, framed, stdout_limit, stderr_limit, response_limit);
}

pub fn handleFramedRequestBatch(
    allocator: std.mem.Allocator,
    request: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    var response: std.ArrayList(u8) = .empty;
    errdefer response.deinit(allocator);

    var remaining = request;
    var saw_frame = false;
    while (true) {
        const trimmed = trimLeftWhitespace(remaining);
        if (trimmed.len == 0) break;

        const consumed = try parseFramedRequestPrefix(remaining);
        saw_frame = true;
        remaining = remaining[consumed.consumed_len..];

        const response_remaining = response_limit -| response.items.len;
        if (response_remaining == 0) return error.ResponseTooLarge;

        const frame_response = try handleFramedResponse(
            allocator,
            consumed.framed,
            stdout_limit,
            stderr_limit,
            response_remaining,
        );
        defer allocator.free(frame_response);

        if (response.items.len + frame_response.len > response_limit) return error.ResponseTooLarge;
        try response.appendSlice(allocator, frame_response);
    }

    if (!saw_frame) return error.EmptyRequest;
    return response.toOwnedSlice(allocator);
}

fn handleFramedResponse(
    allocator: std.mem.Allocator,
    framed: FramedRequest,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    const payload_limit = payloadLimitForResponse(response_limit);
    const payload = try handleFramedPayload(allocator, framed, stdout_limit, stderr_limit, payload_limit);
    defer allocator.free(payload);

    return formatFramedResponse(allocator, framed.request_id, payload, response_limit);
}

const TokenSplit = struct {
    token: []const u8,
    rest: []const u8,
};

fn payloadLimitForResponse(response_limit: usize) usize {
    return codec.payloadLimitForResponse(response_limit);
}

fn parseFramedRequestPrefix(request: []const u8) Error!ConsumedRequest {
    return codec.parseFramedRequestPrefix(request);
}

fn handleFramedPayload(
    allocator: std.mem.Allocator,
    framed: FramedRequest,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    return switch (framed.operation) {
        .command => |command| try handleCommandRequest(allocator, command, stdout_limit, stderr_limit, payload_limit),
        .execute => |command| try handleExecRequest(allocator, command, stdout_limit, stderr_limit, payload_limit),
        .get => |path| try handleGetRequest(allocator, path, payload_limit),
        .put => |put_request| try handlePutRequest(allocator, put_request.path, put_request.body, payload_limit),
        .stat => |path| try handleStatRequest(allocator, path, payload_limit),
        .list => |path| try handleListRequest(allocator, path, payload_limit),
        .install => try handleInstallRequest(allocator, payload_limit),
        .manifest => try handleManifestRequest(allocator, payload_limit),
        .package_install => |package_request| try handlePackageInstallRequest(allocator, package_request.path, package_request.body, payload_limit),
        .package_list => try handlePackageListRequest(allocator, payload_limit),
        .package_info => |package_name| try handlePackageInfoRequest(allocator, package_name, payload_limit),
        .package_app => |package_name| try handlePackageAppRequest(allocator, package_name, payload_limit),
        .package_display => |package_display| try handlePackageDisplayRequest(allocator, package_display.package_name, package_display.width, package_display.height, payload_limit),
        .package_run => |package_name| try handlePackageRunRequest(allocator, package_name, stdout_limit, stderr_limit, payload_limit),
        .package_asset_put => |asset_request| try handlePackageAssetPutRequest(allocator, asset_request.package_name, asset_request.relative_path, asset_request.body, payload_limit),
        .package_asset_list => |package_name| try handlePackageAssetListRequest(allocator, package_name, payload_limit),
        .package_asset_get => |asset_request| try handlePackageAssetGetRequest(allocator, asset_request.package_name, asset_request.relative_path, payload_limit),
        .package_verify => |package_name| try handlePackageVerifyRequest(allocator, package_name, payload_limit),
        .package_delete => |package_name| try handlePackageDeleteRequest(allocator, package_name, payload_limit),
        .package_release_list => |package_name| try handlePackageReleaseListRequest(allocator, package_name, payload_limit),
        .package_release_info => |release_request| try handlePackageReleaseInfoRequest(allocator, release_request.package_name, release_request.value, payload_limit),
        .package_release_save => |release_request| try handlePackageReleaseSaveRequest(allocator, release_request.package_name, release_request.value, payload_limit),
        .package_release_activate => |release_request| try handlePackageReleaseActivateRequest(allocator, release_request.package_name, release_request.value, payload_limit),
        .package_release_delete => |release_request| try handlePackageReleaseDeleteRequest(allocator, release_request.package_name, release_request.value, payload_limit),
        .package_release_prune => |release_request| try handlePackageReleasePruneRequest(allocator, release_request.package_name, release_request.keep, payload_limit),
        .package_channel_list => |package_name| try handlePackageChannelListRequest(allocator, package_name, payload_limit),
        .package_channel_info => |channel_request| try handlePackageChannelInfoRequest(allocator, channel_request.package_name, channel_request.value, payload_limit),
        .package_channel_set => |channel_request| try handlePackageChannelSetRequest(allocator, channel_request.package_name, channel_request.channel, channel_request.release, payload_limit),
        .package_channel_activate => |channel_request| try handlePackageChannelActivateRequest(allocator, channel_request.package_name, channel_request.value, payload_limit),
        .app_list => try handleAppListRequest(allocator, payload_limit),
        .app_info => |package_name| try handleAppInfoRequest(allocator, package_name, payload_limit),
        .app_state => |package_name| try handleAppStateRequest(allocator, package_name, payload_limit),
        .app_history => |package_name| try handleAppHistoryRequest(allocator, package_name, payload_limit),
        .app_stdout => |package_name| try handleAppStdoutRequest(allocator, package_name, payload_limit),
        .app_stderr => |package_name| try handleAppStderrRequest(allocator, package_name, payload_limit),
        .app_trust => |app_request| try handleAppTrustRequest(allocator, app_request.package_name, app_request.value, payload_limit),
        .app_connector => |app_request| try handleAppConnectorRequest(allocator, app_request.package_name, app_request.value, payload_limit),
        .app_plan_list => |package_name| try handleAppPlanListRequest(allocator, package_name, payload_limit),
        .app_plan_info => |plan_request| try handleAppPlanInfoRequest(allocator, plan_request.package_name, plan_request.value, payload_limit),
        .app_plan_active => |package_name| try handleAppPlanActiveRequest(allocator, package_name, payload_limit),
        .app_plan_save => |plan_request| try handleAppPlanSaveRequest(allocator, plan_request, payload_limit),
        .app_plan_apply => |plan_request| try handleAppPlanApplyRequest(allocator, plan_request.package_name, plan_request.value, payload_limit),
        .app_plan_delete => |plan_request| try handleAppPlanDeleteRequest(allocator, plan_request.package_name, plan_request.value, payload_limit),
        .app_suite_list => try handleAppSuiteListRequest(allocator, payload_limit),
        .app_suite_info => |suite_name| try handleAppSuiteInfoRequest(allocator, suite_name, payload_limit),
        .app_suite_save => |suite_request| try handleAppSuiteSaveRequest(allocator, suite_request, payload_limit),
        .app_suite_apply => |suite_name| try handleAppSuiteApplyRequest(allocator, suite_name, payload_limit),
        .app_suite_run => |suite_name| try handleAppSuiteRunRequest(allocator, suite_name, stdout_limit, stderr_limit, payload_limit),
        .app_suite_delete => |suite_name| try handleAppSuiteDeleteRequest(allocator, suite_name, payload_limit),
        .app_suite_release_list => |suite_name| try handleAppSuiteReleaseListRequest(allocator, suite_name, payload_limit),
        .app_suite_release_info => |request| try handleAppSuiteReleaseInfoRequest(allocator, request.suite_name, request.release_name, payload_limit),
        .app_suite_release_save => |request| try handleAppSuiteReleaseSaveRequest(allocator, request.suite_name, request.release_name, payload_limit),
        .app_suite_release_activate => |request| try handleAppSuiteReleaseActivateRequest(allocator, request.suite_name, request.release_name, payload_limit),
        .app_suite_release_delete => |request| try handleAppSuiteReleaseDeleteRequest(allocator, request.suite_name, request.release_name, payload_limit),
        .app_suite_release_prune => |request| try handleAppSuiteReleasePruneRequest(allocator, request.suite_name, request.keep, payload_limit),
        .app_suite_channel_list => |suite_name| try handleAppSuiteChannelListRequest(allocator, suite_name, payload_limit),
        .app_suite_channel_info => |request| try handleAppSuiteChannelInfoRequest(allocator, request.suite_name, request.value, payload_limit),
        .app_suite_channel_set => |request| try handleAppSuiteChannelSetRequest(allocator, request.suite_name, request.channel, request.release, payload_limit),
        .app_suite_channel_activate => |request| try handleAppSuiteChannelActivateRequest(allocator, request.suite_name, request.value, payload_limit),
        .workspace_plan_list => |workspace_name| try handleWorkspacePlanListRequest(allocator, workspace_name, payload_limit),
        .workspace_plan_info => |request| try handleWorkspacePlanInfoRequest(allocator, request.workspace_name, request.plan_name, payload_limit),
        .workspace_plan_active => |workspace_name| try handleWorkspacePlanActiveRequest(allocator, workspace_name, payload_limit),
        .workspace_plan_save => |request| try handleWorkspacePlanSaveRequest(allocator, request, payload_limit),
        .workspace_plan_apply => |request| try handleWorkspacePlanApplyRequest(allocator, request.workspace_name, request.plan_name, payload_limit),
        .workspace_plan_delete => |request| try handleWorkspacePlanDeleteRequest(allocator, request.workspace_name, request.plan_name, payload_limit),
        .workspace_plan_release_list => |request| try handleWorkspacePlanReleaseListRequest(allocator, request.workspace_name, request.plan_name, payload_limit),
        .workspace_plan_release_info => |request| try handleWorkspacePlanReleaseInfoRequest(allocator, request.workspace_name, request.plan_name, request.release_name, payload_limit),
        .workspace_plan_release_save => |request| try handleWorkspacePlanReleaseSaveRequest(allocator, request.workspace_name, request.plan_name, request.release_name, payload_limit),
        .workspace_plan_release_activate => |request| try handleWorkspacePlanReleaseActivateRequest(allocator, request.workspace_name, request.plan_name, request.release_name, payload_limit),
        .workspace_plan_release_delete => |request| try handleWorkspacePlanReleaseDeleteRequest(allocator, request.workspace_name, request.plan_name, request.release_name, payload_limit),
        .workspace_plan_release_prune => |request| try handleWorkspacePlanReleasePruneRequest(allocator, request.workspace_name, request.plan_name, request.keep, payload_limit),
        .workspace_suite_list => try handleWorkspaceSuiteListRequest(allocator, payload_limit),
        .workspace_suite_info => |suite_name| try handleWorkspaceSuiteInfoRequest(allocator, suite_name, payload_limit),
        .workspace_suite_save => |suite_request| try handleWorkspaceSuiteSaveRequest(allocator, suite_request, payload_limit),
        .workspace_suite_apply => |suite_name| try handleWorkspaceSuiteApplyRequest(allocator, suite_name, payload_limit),
        .workspace_suite_run => |suite_name| try handleWorkspaceSuiteRunRequest(allocator, suite_name, stdout_limit, stderr_limit, payload_limit),
        .workspace_suite_delete => |suite_name| try handleWorkspaceSuiteDeleteRequest(allocator, suite_name, payload_limit),
        .workspace_suite_release_list => |suite_name| try handleWorkspaceSuiteReleaseListRequest(allocator, suite_name, payload_limit),
        .workspace_suite_release_info => |request| try handleWorkspaceSuiteReleaseInfoRequest(allocator, request.suite_name, request.release_name, payload_limit),
        .workspace_suite_release_save => |request| try handleWorkspaceSuiteReleaseSaveRequest(allocator, request.suite_name, request.release_name, payload_limit),
        .workspace_suite_release_activate => |request| try handleWorkspaceSuiteReleaseActivateRequest(allocator, request.suite_name, request.release_name, payload_limit),
        .workspace_suite_release_delete => |request| try handleWorkspaceSuiteReleaseDeleteRequest(allocator, request.suite_name, request.release_name, payload_limit),
        .workspace_suite_release_prune => |request| try handleWorkspaceSuiteReleasePruneRequest(allocator, request.suite_name, request.keep, payload_limit),
        .workspace_suite_channel_list => |suite_name| try handleWorkspaceSuiteChannelListRequest(allocator, suite_name, payload_limit),
        .workspace_suite_channel_info => |request| try handleWorkspaceSuiteChannelInfoRequest(allocator, request.suite_name, request.value, payload_limit),
        .workspace_suite_channel_set => |request| try handleWorkspaceSuiteChannelSetRequest(allocator, request.suite_name, request.channel, request.release, payload_limit),
        .workspace_suite_channel_activate => |request| try handleWorkspaceSuiteChannelActivateRequest(allocator, request.suite_name, request.value, payload_limit),
        .workspace_list => try handleWorkspaceListRequest(allocator, payload_limit),
        .workspace_info => |workspace_name| try handleWorkspaceInfoRequest(allocator, workspace_name, payload_limit),
        .workspace_save => |workspace_request| try handleWorkspaceSaveRequest(allocator, workspace_request, payload_limit),
        .workspace_apply => |workspace_name| try handleWorkspaceApplyRequest(allocator, workspace_name, payload_limit),
        .workspace_run => |workspace_name| try handleWorkspaceRunRequest(allocator, workspace_name, stdout_limit, stderr_limit, payload_limit),
        .workspace_state => |workspace_name| try handleWorkspaceStateRequest(allocator, workspace_name, payload_limit),
        .workspace_history => |workspace_name| try handleWorkspaceHistoryRequest(allocator, workspace_name, payload_limit),
        .workspace_stdout => |workspace_name| try handleWorkspaceStdoutRequest(allocator, workspace_name, payload_limit),
        .workspace_stderr => |workspace_name| try handleWorkspaceStderrRequest(allocator, workspace_name, payload_limit),
        .workspace_delete => |workspace_name| try handleWorkspaceDeleteRequest(allocator, workspace_name, payload_limit),
        .workspace_release_list => |workspace_name| try handleWorkspaceReleaseListRequest(allocator, workspace_name, payload_limit),
        .workspace_release_info => |request| try handleWorkspaceReleaseInfoRequest(allocator, request.workspace_name, request.release_name, payload_limit),
        .workspace_release_save => |request| try handleWorkspaceReleaseSaveRequest(allocator, request.workspace_name, request.release_name, payload_limit),
        .workspace_release_activate => |request| try handleWorkspaceReleaseActivateRequest(allocator, request.workspace_name, request.release_name, payload_limit),
        .workspace_release_delete => |request| try handleWorkspaceReleaseDeleteRequest(allocator, request.workspace_name, request.release_name, payload_limit),
        .workspace_release_prune => |request| try handleWorkspaceReleasePruneRequest(allocator, request.workspace_name, request.keep, payload_limit),
        .workspace_channel_list => |workspace_name| try handleWorkspaceChannelListRequest(allocator, workspace_name, payload_limit),
        .workspace_channel_info => |request| try handleWorkspaceChannelInfoRequest(allocator, request.workspace_name, request.value, payload_limit),
        .workspace_channel_set => |request| try handleWorkspaceChannelSetRequest(allocator, request.workspace_name, request.channel, request.release, payload_limit),
        .workspace_channel_activate => |request| try handleWorkspaceChannelActivateRequest(allocator, request.workspace_name, request.value, payload_limit),
        .workspace_autorun_list => try handleWorkspaceAutorunListRequest(allocator, payload_limit),
        .workspace_autorun_add => |workspace_name| try handleWorkspaceAutorunAddRequest(allocator, workspace_name, payload_limit),
        .workspace_autorun_remove => |workspace_name| try handleWorkspaceAutorunRemoveRequest(allocator, workspace_name, payload_limit),
        .workspace_autorun_run => try handleWorkspaceAutorunRunRequest(allocator, stdout_limit, stderr_limit, payload_limit),
        .app_run => |package_name| try handleAppRunRequest(allocator, package_name, stdout_limit, stderr_limit, payload_limit),
        .app_delete => |package_name| try handleAppDeleteRequest(allocator, package_name, payload_limit),
        .app_autorun_list => try handleAppAutorunListRequest(allocator, payload_limit),
        .app_autorun_add => |package_name| try handleAppAutorunAddRequest(allocator, package_name, payload_limit),
        .app_autorun_remove => |package_name| try handleAppAutorunRemoveRequest(allocator, package_name, payload_limit),
        .app_autorun_run => try handleAppAutorunRunRequest(allocator, stdout_limit, stderr_limit, payload_limit),
        .display_info => try handleDisplayInfoRequest(allocator, payload_limit),
        .display_outputs => try handleDisplayOutputsRequest(allocator, payload_limit),
        .display_output => |output_index| try handleDisplayOutputRequest(allocator, output_index, payload_limit),
        .display_output_detail => |output_index| try handleDisplayOutputDetailRequest(allocator, output_index, payload_limit),
        .display_output_capabilities => |output_index| try handleDisplayOutputCapabilitiesRequest(allocator, output_index, payload_limit),
        .display_output_modes => |output_index| try handleDisplayOutputModesRequest(allocator, output_index, payload_limit),
        .display_modes => try handleDisplayModesRequest(allocator, payload_limit),
        .display_set => |display_mode| try handleDisplaySetRequest(allocator, display_mode.width, display_mode.height, payload_limit),
        .display_activate => |connector_name| try handleDisplayActivateRequest(allocator, connector_name, payload_limit),
        .display_activate_preferred => |connector_name| try handleDisplayActivatePreferredRequest(allocator, connector_name, payload_limit),
        .display_activate_interface => |interface_name| try handleDisplayActivateInterfaceRequest(allocator, interface_name, payload_limit),
        .display_activate_interface_preferred => |interface_name| try handleDisplayActivateInterfacePreferredRequest(allocator, interface_name, payload_limit),
        .display_interface_detail => |interface_name| try handleDisplayInterfaceDetailRequest(allocator, interface_name, payload_limit),
        .display_interface_capabilities => |interface_name| try handleDisplayInterfaceCapabilitiesRequest(allocator, interface_name, payload_limit),
        .display_interface_modes => |interface_name| try handleDisplayInterfaceModesRequest(allocator, interface_name, payload_limit),
        .display_interface_set => |request| try handleDisplayInterfaceSetRequest(allocator, request.interface_name, request.width, request.height, payload_limit),
        .display_interface_activate_mode => |request| try handleDisplayInterfaceActivateModeRequest(allocator, request.interface_name, request.mode_index, payload_limit),
        .display_activate_output => |output_index| try handleDisplayActivateOutputRequest(allocator, output_index, payload_limit),
        .display_activate_output_preferred => |output_index| try handleDisplayActivateOutputPreferredRequest(allocator, output_index, payload_limit),
        .display_output_set => |request| try handleDisplayOutputSetRequest(allocator, request.index, request.width, request.height, payload_limit),
        .display_output_activate_mode => |request| try handleDisplayOutputActivateModeRequest(allocator, request.index, request.mode_index, payload_limit),
        .display_profile_list => try handleDisplayProfileListRequest(allocator, payload_limit),
        .display_profile_info => |profile_name| try handleDisplayProfileInfoRequest(allocator, profile_name, payload_limit),
        .display_profile_active => try handleDisplayProfileActiveRequest(allocator, payload_limit),
        .display_profile_save => |profile_name| try handleDisplayProfileSaveRequest(allocator, profile_name, payload_limit),
        .display_profile_apply => |profile_name| try handleDisplayProfileApplyRequest(allocator, profile_name, payload_limit),
        .display_profile_delete => |profile_name| try handleDisplayProfileDeleteRequest(allocator, profile_name, payload_limit),
        .trust_install => |trust_request| try handleTrustInstallRequest(allocator, trust_request.path, trust_request.body, payload_limit),
        .trust_list => try handleTrustListRequest(allocator, payload_limit),
        .trust_info => |trust_name| try handleTrustInfoRequest(allocator, trust_name, payload_limit),
        .trust_active => try handleTrustActiveRequest(allocator, payload_limit),
        .trust_select => |trust_name| try handleTrustSelectRequest(allocator, trust_name, payload_limit),
        .trust_delete => |trust_name| try handleTrustDeleteRequest(allocator, trust_name, payload_limit),
        .runtime_snapshot => try handleRuntimeSnapshotRequest(allocator, payload_limit),
        .runtime_sessions => try handleRuntimeSessionsRequest(allocator, payload_limit),
        .runtime_session => |session_id| try handleRuntimeSessionRequest(allocator, session_id, payload_limit),
        .runtime_call => |frame_json| try handleRuntimeCallRequest(allocator, frame_json, payload_limit),
    };
}

fn splitFirstToken(text: []const u8) Error!TokenSplit {
    const trimmed = trimLeftWhitespace(text);
    if (trimmed.len == 0) return error.InvalidFrame;

    var idx: usize = 0;
    while (idx < trimmed.len and !std.ascii.isWhitespace(trimmed[idx])) : (idx += 1) {}
    return .{
        .token = trimmed[0..idx],
        .rest = trimLeftWhitespace(trimmed[idx..]),
    };
}

fn parseBooleanToken(text: []const u8) Error!bool {
    if (std.mem.eql(u8, text, "1") or std.ascii.eqlIgnoreCase(text, "true") or std.ascii.eqlIgnoreCase(text, "yes")) {
        return true;
    }
    if (std.mem.eql(u8, text, "0") or std.ascii.eqlIgnoreCase(text, "false") or std.ascii.eqlIgnoreCase(text, "no")) {
        return false;
    }
    return error.InvalidFrame;
}

fn formatFramedResponse(
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

fn handleGetRequest(allocator: std.mem.Allocator, path: []const u8, payload_limit: usize) Error![]u8 {
    return filesystem.readFileAlloc(allocator, path, payload_limit) catch |err| {
        return formatOperationError(allocator, "GET", err, payload_limit);
    };
}

fn handleExecRequest(
    allocator: std.mem.Allocator,
    command: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    var result = try tool_exec.runCapture(allocator, command, stdout_limit, stderr_limit);
    defer result.deinit(allocator);

    var response: std.ArrayList(u8) = .empty;
    errdefer response.deinit(allocator);

    const header = try std.fmt.allocPrint(
        allocator,
        "exit={d} stdout_len={d} stderr_len={d}\nstdout:\n",
        .{ result.exit_code, result.stdout.len, result.stderr.len },
    );
    defer allocator.free(header);
    try response.appendSlice(allocator, header);
    try response.appendSlice(allocator, result.stdout);
    if (result.stdout.len == 0 or result.stdout[result.stdout.len - 1] != '\n') {
        try response.append(allocator, '\n');
    }
    try response.appendSlice(allocator, "stderr:\n");
    try response.appendSlice(allocator, result.stderr);
    if (result.stderr.len == 0 or result.stderr[result.stderr.len - 1] != '\n') {
        try response.append(allocator, '\n');
    }

    if (response.items.len > payload_limit) return error.ResponseTooLarge;
    return response.toOwnedSlice(allocator);
}

fn handlePutRequest(allocator: std.mem.Allocator, path: []const u8, body: []const u8, payload_limit: usize) Error![]u8 {
    ensureParentDirectory(path) catch |err| {
        return formatOperationError(allocator, "PUT", err, payload_limit);
    };
    filesystem.writeFile(path, body, 0) catch |err| {
        return formatOperationError(allocator, "PUT", err, payload_limit);
    };

    const response = try std.fmt.allocPrint(allocator, "WROTE {d} bytes to {s}\n", .{ body.len, path });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleStatRequest(allocator: std.mem.Allocator, path: []const u8, payload_limit: usize) Error![]u8 {
    const stat = filesystem.statSummary(path) catch |err| {
        return formatOperationError(allocator, "STAT", err, payload_limit);
    };
    const kind = switch (stat.kind) {
        .directory => "directory",
        .file => "file",
        else => "unknown",
    };
    const response = try std.fmt.allocPrint(allocator, "path={s} kind={s} size={d}\n", .{ path, kind, stat.size });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleListRequest(allocator: std.mem.Allocator, path: []const u8, payload_limit: usize) Error![]u8 {
    return filesystem.listDirectoryAlloc(allocator, path, payload_limit) catch |err| {
        return formatOperationError(allocator, "LIST", err, payload_limit);
    };
}

fn handleInstallRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    disk_installer.installDefaultLayout(1) catch |err| {
        return formatOperationError(allocator, "INSTALL", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "INSTALLED {s}\n", .{disk_installer.install_manifest_path});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleManifestRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    var manifest_buf: [192]u8 = undefined;
    const manifest = disk_installer.installManifestForCurrentBackend(manifest_buf[0..]) catch |err| {
        return formatOperationError(allocator, "MANIFEST", err, payload_limit);
    };
    if (manifest.len > payload_limit) return error.ResponseTooLarge;
    return allocator.dupe(u8, manifest);
}

fn handlePackageInstallRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    body: []const u8,
    payload_limit: usize,
) Error![]u8 {
    package_store.installScriptPackage(package_name, body, 0) catch |err| {
        return formatOperationError(allocator, "PKG", err, payload_limit);
    };

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const entrypoint = package_store.entrypointPath(package_name, &entrypoint_buf) catch |err| {
        return formatOperationError(allocator, "PKG", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "INSTALLED {s} -> {s}\n", .{ package_name, entrypoint });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return package_store.listPackagesAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGLIST", err, payload_limit);
    };
}

fn handlePackageInfoRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return package_store.manifestAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGINFO", err, payload_limit);
    };
}

fn handlePackageAppRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return package_store.appManifestAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGAPP", err, payload_limit);
    };
}

fn handlePackageDisplayRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    width: u16,
    height: u16,
    payload_limit: usize,
) Error![]u8 {
    package_store.configureDisplayMode(package_name, width, height, 0) catch |err| {
        return formatOperationError(allocator, "PKGDISPLAY", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "DISPLAY {s} {d}x{d}\n", .{ package_name, width, height });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageAssetPutRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    relative_path: []const u8,
    body: []const u8,
    payload_limit: usize,
) Error![]u8 {
    package_store.installPackageAsset(package_name, relative_path, body, 0) catch |err| {
        return formatOperationError(allocator, "PKGPUT", err, payload_limit);
    };

    var asset_buf: [filesystem.max_path_len]u8 = undefined;
    const asset_path = package_store.assetPath(package_name, relative_path, &asset_buf) catch |err| {
        return formatOperationError(allocator, "PKGPUT", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "ASSET {s} -> {s}\n", .{ package_name, asset_path });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageAssetListRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return package_store.listPackageAssetsAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGLS", err, payload_limit);
    };
}

fn handlePackageAssetGetRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    relative_path: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return package_store.readPackageAssetAlloc(allocator, package_name, relative_path, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGGET", err, payload_limit);
    };
}

fn handlePackageVerifyRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    var result = package_store.verifyPackageAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGVERIFY", err, payload_limit);
    };
    defer result.deinit(allocator);

    if (result.payload.len > payload_limit) return error.ResponseTooLarge;
    return allocator.dupe(u8, result.payload);
}

fn handlePackageRunRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    var command_buf: [96]u8 = undefined;
    const command = std.fmt.bufPrint(&command_buf, "run-package {s}", .{package_name}) catch return error.InvalidFrame;
    return handleCommandRequest(allocator, command, stdout_limit, stderr_limit, payload_limit);
}

fn handlePackageDeleteRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    app_runtime.uninstallApp(package_name, 0) catch |err| {
        return formatOperationError(allocator, "PKGDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "PKGDELETED {s}\n", .{package_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageReleaseListRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return package_store.releaseListAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGRELEASELIST", err, payload_limit);
    };
}

fn handlePackageReleaseInfoRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return package_store.releaseInfoAlloc(allocator, package_name, release_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGRELEASEINFO", err, payload_limit);
    };
}

fn handlePackageReleaseSaveRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    package_store.snapshotPackageRelease(package_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "PKGRELEASESAVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "PKGRELEASESAVE {s} {s}\n", .{ package_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageReleaseActivateRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    package_store.activatePackageRelease(package_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "PKGRELEASEACTIVATE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "PKGRELEASEACTIVATE {s} {s}\n", .{ package_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageReleaseDeleteRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    package_store.deletePackageRelease(package_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "PKGRELEASEDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "PKGRELEASEDELETE {s} {s}\n", .{ package_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageReleasePruneRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    keep: u32,
    payload_limit: usize,
) Error![]u8 {
    const prune = package_store.prunePackageReleases(package_name, keep, 0) catch |err| {
        return formatOperationError(allocator, "PKGRELEASEPRUNE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(
        allocator,
        "PKGRELEASEPRUNE {s} keep={d} deleted={d} kept={d}\n",
        .{ package_name, keep, prune.deleted_count, prune.kept_count },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageChannelListRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return package_store.channelListAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGCHANNELLIST", err, payload_limit);
    };
}

fn handlePackageChannelInfoRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    channel_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return package_store.channelInfoAlloc(allocator, package_name, channel_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGCHANNELINFO", err, payload_limit);
    };
}

fn handlePackageChannelSetRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    channel_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    package_store.setPackageReleaseChannel(package_name, channel_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "PKGCHANNELSET", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "PKGCHANNELSET {s} {s} {s}\n", .{ package_name, channel_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageChannelActivateRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    channel_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    package_store.activatePackageReleaseChannel(package_name, channel_name, 0) catch |err| {
        return formatOperationError(allocator, "PKGCHANNELACTIVATE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "PKGCHANNELACTIVATE {s} {s}\n", .{ package_name, channel_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return app_runtime.listAppsAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPLIST", err, payload_limit);
    };
}

fn handleAppInfoRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return app_runtime.infoAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPINFO", err, payload_limit);
    };
}

fn handleAppStateRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return app_runtime.stateAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPSTATE", err, payload_limit);
    };
}

fn handleAppHistoryRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return app_runtime.historyAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPHISTORY", err, payload_limit);
    };
}

fn handleAppStdoutRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return app_runtime.stdoutAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPSTDOUT", err, payload_limit);
    };
}

fn handleAppStderrRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return app_runtime.stderrAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPSTDERR", err, payload_limit);
    };
}

fn handleAppTrustRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    trust_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    const selected_name = if (std.ascii.eqlIgnoreCase(trust_name, "none")) "" else trust_name;
    package_store.configureTrustBundle(package_name, selected_name, 0) catch |err| {
        return formatOperationError(allocator, "APPTRUST", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(
        allocator,
        "APPTRUST {s} {s}\n",
        .{ package_name, if (selected_name.len == 0) "none" else selected_name },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppConnectorRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    connector_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    const connector_type = package_store.parseConnectorType(connector_name) catch |err| {
        return formatOperationError(allocator, "APPCONNECTOR", err, payload_limit);
    };
    package_store.configureConnectorType(package_name, connector_type, 0) catch |err| {
        return formatOperationError(allocator, "APPCONNECTOR", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(
        allocator,
        "APPCONNECTOR {s} {s}\n",
        .{ package_name, package_store.connectorNameFromType(connector_type) },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppPlanListRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return app_runtime.planListAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPPLANLIST", err, payload_limit);
    };
}

fn handleAppPlanInfoRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    plan_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return app_runtime.planInfoAlloc(allocator, package_name, plan_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPPLANINFO", err, payload_limit);
    };
}

fn handleAppPlanActiveRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return app_runtime.activePlanInfoAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPPLANACTIVE", err, payload_limit);
    };
}

fn handleAppPlanSaveRequest(
    allocator: std.mem.Allocator,
    request: AppPlanSaveRequest,
    payload_limit: usize,
) Error![]u8 {
    app_runtime.savePlan(
        request.package_name,
        request.plan_name,
        request.release_name,
        request.trust_bundle,
        request.connector_type,
        request.width,
        request.height,
        request.autorun,
        0,
    ) catch |err| {
        return formatOperationError(allocator, "APPPLANSAVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPPLANSAVE {s} {s}\n", .{ request.package_name, request.plan_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppPlanApplyRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    plan_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    app_runtime.applyPlan(package_name, plan_name, 0) catch |err| {
        return formatOperationError(allocator, "APPPLANAPPLY", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPPLANAPPLY {s} {s}\n", .{ package_name, plan_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppPlanDeleteRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    plan_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    app_runtime.deletePlan(package_name, plan_name, 0) catch |err| {
        return formatOperationError(allocator, "APPPLANDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPPLANDELETE {s} {s}\n", .{ package_name, plan_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppSuiteListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return app_runtime.suiteListAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPSUITELIST", err, payload_limit);
    };
}

fn handleAppSuiteInfoRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return app_runtime.suiteInfoAlloc(allocator, suite_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPSUITEINFO", err, payload_limit);
    };
}

fn handleAppSuiteSaveRequest(
    allocator: std.mem.Allocator,
    request: AppSuiteSaveRequest,
    payload_limit: usize,
) Error![]u8 {
    app_runtime.saveSuite(request.suite_name, request.entries_spec, 0) catch |err| {
        return formatOperationError(allocator, "APPSUITESAVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPSUITESAVE {s}\n", .{request.suite_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppSuiteApplyRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    app_runtime.applySuite(suite_name, 0) catch |err| {
        return formatOperationError(allocator, "APPSUITEAPPLY", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPSUITEAPPLY {s}\n", .{suite_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppSuiteRunRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    var command_buf: [96]u8 = undefined;
    const command = std.fmt.bufPrint(&command_buf, "app-suite-run {s}", .{suite_name}) catch return error.InvalidFrame;
    return handleCommandRequest(allocator, command, stdout_limit, stderr_limit, payload_limit);
}

fn handleAppSuiteDeleteRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    app_runtime.deleteSuite(suite_name, 0) catch |err| {
        return formatOperationError(allocator, "APPSUITEDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPSUITEDELETE {s}\n", .{suite_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppSuiteReleaseListRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return app_runtime.suiteReleaseListAlloc(allocator, suite_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPSUITERELEASELIST", err, payload_limit);
    };
}

fn handleAppSuiteReleaseInfoRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return app_runtime.suiteReleaseInfoAlloc(allocator, suite_name, release_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPSUITERELEASEINFO", err, payload_limit);
    };
}

fn handleAppSuiteReleaseSaveRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    app_runtime.snapshotSuiteRelease(suite_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "APPSUITERELEASESAVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPSUITERELEASESAVE {s} {s}\n", .{ suite_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppSuiteReleaseActivateRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    app_runtime.activateSuiteRelease(suite_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "APPSUITERELEASEACTIVATE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPSUITERELEASEACTIVATE {s} {s}\n", .{ suite_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppSuiteReleaseDeleteRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    app_runtime.deleteSuiteRelease(suite_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "APPSUITERELEASEDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPSUITERELEASEDELETE {s} {s}\n", .{ suite_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppSuiteReleasePruneRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    keep: u32,
    payload_limit: usize,
) Error![]u8 {
    const keep_usize: usize = @intCast(keep);
    const prune = app_runtime.pruneSuiteReleases(suite_name, keep_usize, 0) catch |err| {
        return formatOperationError(allocator, "APPSUITERELEASEPRUNE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(
        allocator,
        "APPSUITERELEASEPRUNE {s} keep={d} deleted={d} kept={d}\n",
        .{ suite_name, keep, prune.deleted_count, prune.kept_count },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppSuiteChannelListRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return app_runtime.suiteChannelListAlloc(allocator, suite_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPSUITECHANNELLIST", err, payload_limit);
    };
}

fn handleAppSuiteChannelInfoRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    channel_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return app_runtime.suiteChannelInfoAlloc(allocator, suite_name, channel_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPSUITECHANNELINFO", err, payload_limit);
    };
}

fn handleAppSuiteChannelSetRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    channel_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    app_runtime.setSuiteReleaseChannel(suite_name, channel_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "APPSUITECHANNELSET", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPSUITECHANNELSET {s} {s} {s}\n", .{ suite_name, channel_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppSuiteChannelActivateRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    channel_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    app_runtime.activateSuiteReleaseChannel(suite_name, channel_name, 0) catch |err| {
        return formatOperationError(allocator, "APPSUITECHANNELACTIVATE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPSUITECHANNELACTIVATE {s} {s}\n", .{ suite_name, channel_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspacePlanListRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.planListAlloc(allocator, workspace_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANLIST", err, payload_limit);
    };
}

fn handleWorkspacePlanInfoRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    plan_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.planInfoAlloc(allocator, workspace_name, plan_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANINFO", err, payload_limit);
    };
}

fn handleWorkspacePlanActiveRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.activePlanInfoAlloc(allocator, workspace_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANACTIVE", err, payload_limit);
    };
}

fn handleWorkspacePlanSaveRequest(
    allocator: std.mem.Allocator,
    request: WorkspacePlanSaveRequest,
    payload_limit: usize,
) Error![]u8 {
    const suite_name = if (std.ascii.eqlIgnoreCase(request.suite_name, "none")) "" else request.suite_name;
    const trust_bundle = if (std.ascii.eqlIgnoreCase(request.trust_bundle, "none")) "" else request.trust_bundle;
    workspace_runtime.savePlan(request.workspace_name, request.plan_name, suite_name, trust_bundle, request.width, request.height, request.entries_spec, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANSAVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACEPLANSAVE {s} {s}\n", .{ request.workspace_name, request.plan_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspacePlanApplyRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    plan_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.applyPlan(workspace_name, plan_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANAPPLY", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACEPLANAPPLY {s} {s}\n", .{ workspace_name, plan_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspacePlanDeleteRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    plan_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.deletePlan(workspace_name, plan_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACEPLANDELETE {s} {s}\n", .{ workspace_name, plan_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspacePlanReleaseListRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    plan_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.planReleaseListAlloc(allocator, workspace_name, plan_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANRELEASELIST", err, payload_limit);
    };
}

fn handleWorkspacePlanReleaseInfoRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    plan_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.planReleaseInfoAlloc(allocator, workspace_name, plan_name, release_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANRELEASEINFO", err, payload_limit);
    };
}

fn handleWorkspacePlanReleaseSaveRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    plan_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.snapshotPlanRelease(workspace_name, plan_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANRELEASESAVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACEPLANRELEASESAVE {s} {s} {s}\n", .{ workspace_name, plan_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspacePlanReleaseActivateRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    plan_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.activatePlanRelease(workspace_name, plan_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANRELEASEACTIVATE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACEPLANRELEASEACTIVATE {s} {s} {s}\n", .{ workspace_name, plan_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspacePlanReleaseDeleteRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    plan_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.deletePlanRelease(workspace_name, plan_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANRELEASEDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACEPLANRELEASEDELETE {s} {s} {s}\n", .{ workspace_name, plan_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspacePlanReleasePruneRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    plan_name: []const u8,
    keep: u32,
    payload_limit: usize,
) Error![]u8 {
    const keep_usize: usize = @intCast(keep);
    const prune = workspace_runtime.prunePlanReleases(workspace_name, plan_name, keep_usize, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACEPLANRELEASEPRUNE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(
        allocator,
        "WORKSPACEPLANRELEASEPRUNE {s} {s} keep={d} deleted={d} kept={d}\n",
        .{ workspace_name, plan_name, keep, prune.deleted_count, prune.kept_count },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceSuiteListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return workspace_runtime.suiteListAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITELIST", err, payload_limit);
    };
}

fn handleWorkspaceSuiteInfoRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.suiteInfoAlloc(allocator, suite_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITEINFO", err, payload_limit);
    };
}

fn handleWorkspaceSuiteSaveRequest(
    allocator: std.mem.Allocator,
    request: WorkspaceSuiteSaveRequest,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.saveSuite(request.suite_name, request.entries_spec, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITESAVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACESUITESAVE {s}\n", .{request.suite_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceSuiteApplyRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.applySuite(suite_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITEAPPLY", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACESUITEAPPLY {s}\n", .{suite_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceSuiteRunRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    var command_buf: [96]u8 = undefined;
    const command = std.fmt.bufPrint(&command_buf, "workspace-suite-run {s}", .{suite_name}) catch return error.InvalidFrame;
    return handleCommandRequest(allocator, command, stdout_limit, stderr_limit, payload_limit);
}

fn handleWorkspaceSuiteDeleteRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.deleteSuite(suite_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITEDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACESUITEDELETE {s}\n", .{suite_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceSuiteReleaseListRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.suiteReleaseListAlloc(allocator, suite_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITERELEASELIST", err, payload_limit);
    };
}

fn handleWorkspaceSuiteReleaseInfoRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.suiteReleaseInfoAlloc(allocator, suite_name, release_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITERELEASEINFO", err, payload_limit);
    };
}

fn handleWorkspaceSuiteReleaseSaveRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.snapshotSuiteRelease(suite_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITERELEASESAVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACESUITERELEASESAVE {s} {s}\n", .{ suite_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceSuiteReleaseActivateRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.activateSuiteRelease(suite_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITERELEASEACTIVATE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACESUITERELEASEACTIVATE {s} {s}\n", .{ suite_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceSuiteReleaseDeleteRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.deleteSuiteRelease(suite_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITERELEASEDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACESUITERELEASEDELETE {s} {s}\n", .{ suite_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceSuiteReleasePruneRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    keep: u32,
    payload_limit: usize,
) Error![]u8 {
    const result = workspace_runtime.pruneSuiteReleases(suite_name, keep, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITERELEASEPRUNE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(
        allocator,
        "WORKSPACESUITERELEASEPRUNE {s} keep={d} deleted={d} kept={d}\n",
        .{ suite_name, keep, result.deleted_count, result.kept_count },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceSuiteChannelListRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.suiteChannelListAlloc(allocator, suite_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITECHANNELLIST", err, payload_limit);
    };
}

fn handleWorkspaceSuiteChannelInfoRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    channel_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.suiteChannelInfoAlloc(allocator, suite_name, channel_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITECHANNELINFO", err, payload_limit);
    };
}

fn handleWorkspaceSuiteChannelSetRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    channel_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.setSuiteReleaseChannel(suite_name, channel_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITECHANNELSET", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACESUITECHANNELSET {s} {s} {s}\n", .{ suite_name, channel_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceSuiteChannelActivateRequest(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    channel_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.activateSuiteReleaseChannel(suite_name, channel_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACESUITECHANNELACTIVATE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACESUITECHANNELACTIVATE {s} {s}\n", .{ suite_name, channel_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return workspace_runtime.listAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACELIST", err, payload_limit);
    };
}

fn handleWorkspaceInfoRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.infoAlloc(allocator, workspace_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACEINFO", err, payload_limit);
    };
}

fn handleWorkspaceSaveRequest(
    allocator: std.mem.Allocator,
    request: WorkspaceSaveRequest,
    payload_limit: usize,
) Error![]u8 {
    const suite_name = if (std.ascii.eqlIgnoreCase(request.suite_name, "none")) "" else request.suite_name;
    const trust_bundle = if (std.ascii.eqlIgnoreCase(request.trust_bundle, "none")) "" else request.trust_bundle;
    workspace_runtime.saveWorkspace(request.name, suite_name, trust_bundle, request.width, request.height, request.entries_spec, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACESAVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACESAVE {s}\n", .{request.name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceApplyRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.applyWorkspace(workspace_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACEAPPLY", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACEAPPLY {s}\n", .{workspace_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceRunRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    var command_buf: [96]u8 = undefined;
    const command = std.fmt.bufPrint(&command_buf, "workspace-run {s}", .{workspace_name}) catch return error.InvalidFrame;
    return handleCommandRequest(allocator, command, stdout_limit, stderr_limit, payload_limit);
}

fn handleWorkspaceStateRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.stateAlloc(allocator, workspace_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACESTATE", err, payload_limit);
    };
}

fn handleWorkspaceHistoryRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.historyAlloc(allocator, workspace_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACEHISTORY", err, payload_limit);
    };
}

fn handleWorkspaceStdoutRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.stdoutAlloc(allocator, workspace_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACESTDOUT", err, payload_limit);
    };
}

fn handleWorkspaceStderrRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.stderrAlloc(allocator, workspace_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACESTDERR", err, payload_limit);
    };
}

fn handleWorkspaceDeleteRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.deleteWorkspace(workspace_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACEDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACEDELETE {s}\n", .{workspace_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceReleaseListRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.releaseListAlloc(allocator, workspace_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACERELEASELIST", err, payload_limit);
    };
}

fn handleWorkspaceReleaseInfoRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.releaseInfoAlloc(allocator, workspace_name, release_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACERELEASEINFO", err, payload_limit);
    };
}

fn handleWorkspaceReleaseSaveRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.snapshotWorkspaceRelease(workspace_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACERELEASESAVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACERELEASESAVE {s} {s}\n", .{ workspace_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceReleaseActivateRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.activateWorkspaceRelease(workspace_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACERELEASEACTIVATE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACERELEASEACTIVATE {s} {s}\n", .{ workspace_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceReleaseDeleteRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.deleteWorkspaceRelease(workspace_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACERELEASEDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACERELEASEDELETE {s} {s}\n", .{ workspace_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceReleasePruneRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    keep: u32,
    payload_limit: usize,
) Error![]u8 {
    const keep_usize: usize = @intCast(keep);
    const prune = workspace_runtime.pruneWorkspaceReleases(workspace_name, keep_usize, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACERELEASEPRUNE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(
        allocator,
        "WORKSPACERELEASEPRUNE {s} keep={d} deleted={d} kept={d}\n",
        .{ workspace_name, keep, prune.deleted_count, prune.kept_count },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceChannelListRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.channelListAlloc(allocator, workspace_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACECHANNELLIST", err, payload_limit);
    };
}

fn handleWorkspaceChannelInfoRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    channel_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return workspace_runtime.channelInfoAlloc(allocator, workspace_name, channel_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACECHANNELINFO", err, payload_limit);
    };
}

fn handleWorkspaceChannelSetRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    channel_name: []const u8,
    release_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.setWorkspaceReleaseChannel(workspace_name, channel_name, release_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACECHANNELSET", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACECHANNELSET {s} {s} {s}\n", .{ workspace_name, channel_name, release_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceChannelActivateRequest(
    allocator: std.mem.Allocator,
    workspace_name: []const u8,
    channel_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    workspace_runtime.activateWorkspaceReleaseChannel(workspace_name, channel_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACECHANNELACTIVATE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACECHANNELACTIVATE {s} {s}\n", .{ workspace_name, channel_name });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceAutorunListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return workspace_runtime.autorunListAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "WORKSPACEAUTORUNLIST", err, payload_limit);
    };
}

fn handleWorkspaceAutorunAddRequest(allocator: std.mem.Allocator, workspace_name: []const u8, payload_limit: usize) Error![]u8 {
    workspace_runtime.addAutorun(workspace_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACEAUTORUNADD", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACEAUTORUNADD {s}\n", .{workspace_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceAutorunRemoveRequest(allocator: std.mem.Allocator, workspace_name: []const u8, payload_limit: usize) Error![]u8 {
    workspace_runtime.removeAutorun(workspace_name, 0) catch |err| {
        return formatOperationError(allocator, "WORKSPACEAUTORUNREMOVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "WORKSPACEAUTORUNREMOVE {s}\n", .{workspace_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleWorkspaceAutorunRunRequest(
    allocator: std.mem.Allocator,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    return handleCommandRequest(allocator, "workspace-autorun-run", stdout_limit, stderr_limit, payload_limit);
}

fn handleAppRunRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    var command_buf: [96]u8 = undefined;
    const command = std.fmt.bufPrint(&command_buf, "app-run {s}", .{package_name}) catch return error.InvalidFrame;
    return handleCommandRequest(allocator, command, stdout_limit, stderr_limit, payload_limit);
}

fn handleAppDeleteRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    app_runtime.uninstallApp(package_name, 0) catch |err| {
        return formatOperationError(allocator, "APPDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPDELETED {s}\n", .{package_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppAutorunListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return app_runtime.autorunListAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPAUTORUNLIST", err, payload_limit);
    };
}

fn handleAppAutorunAddRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    app_runtime.addAutorun(package_name, 0) catch |err| {
        return formatOperationError(allocator, "APPAUTORUNADD", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPAUTORUNADD {s}\n", .{package_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppAutorunRemoveRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    app_runtime.removeAutorun(package_name, 0) catch |err| {
        return formatOperationError(allocator, "APPAUTORUNREMOVE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "APPAUTORUNREMOVE {s}\n", .{package_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppAutorunRunRequest(
    allocator: std.mem.Allocator,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    return handleCommandRequest(allocator, "app-autorun-run", stdout_limit, stderr_limit, payload_limit);
}

fn handleTrustInstallRequest(
    allocator: std.mem.Allocator,
    trust_name: []const u8,
    body: []const u8,
    payload_limit: usize,
) Error![]u8 {
    trust_store.installBundle(trust_name, body, 0) catch |err| {
        return formatOperationError(allocator, "TRUSTPUT", err, payload_limit);
    };

    var bundle_path_buffer: [filesystem.max_path_len]u8 = undefined;
    const bundle_path = trust_store.bundlePath(trust_name, &bundle_path_buffer) catch |err| {
        return formatOperationError(allocator, "TRUSTPUT", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "TRUSTED {s} -> {s}\n", .{ trust_name, bundle_path });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayInfoRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
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
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayOutputsRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    var index: u16 = 0;
    while (index < display_output.outputCount()) : (index += 1) {
        const entry = display_output.outputEntry(index);
        const line = try std.fmt.allocPrint(
            allocator,
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
        defer allocator.free(line);
        if (out.items.len + line.len > payload_limit) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

fn handleDisplayOutputRequest(allocator: std.mem.Allocator, output_index_text: []const u8, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    const index = std.fmt.parseInt(u16, output_index_text, 10) catch {
        return formatOperationError(allocator, "DISPLAYOUTPUT", error.InvalidFrame, payload_limit);
    };
    if (index >= display_output.outputCount()) {
        return formatOperationError(allocator, "DISPLAYOUTPUT", error.NotFound, payload_limit);
    }
    const entry = display_output.outputEntry(index);
    const response = try std.fmt.allocPrint(
        allocator,
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
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn capabilityBit(value: u16, flag: u16) u8 {
    return if ((value & flag) != 0) 1 else 0;
}

fn formatDisplayOutputCapabilitiesResponse(allocator: std.mem.Allocator, index: u16, payload_limit: usize) Error![]u8 {
    const entry = display_output.outputEntry(index);
    const capability_flags = entry.capability_flags;
    const response = try std.fmt.allocPrint(
        allocator,
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
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn formatDisplayOutputDetailResponse(allocator: std.mem.Allocator, index: u16, payload_limit: usize) Error![]u8 {
    const entry = display_output.outputEntry(index);
    const capability_flags = entry.capability_flags;
    const response = try std.fmt.allocPrint(
        allocator,
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
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayOutputDetailRequest(allocator: std.mem.Allocator, output_index_text: []const u8, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    const index = std.fmt.parseInt(u16, output_index_text, 10) catch {
        return formatOperationError(allocator, "DISPLAYOUTPUTDETAIL", error.InvalidFrame, payload_limit);
    };
    if (index >= display_output.outputCount()) {
        return formatOperationError(allocator, "DISPLAYOUTPUTDETAIL", error.NotFound, payload_limit);
    }
    return formatDisplayOutputDetailResponse(allocator, index, payload_limit);
}

fn handleDisplayOutputCapabilitiesRequest(allocator: std.mem.Allocator, output_index_text: []const u8, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    const index = std.fmt.parseInt(u16, output_index_text, 10) catch {
        return formatOperationError(allocator, "DISPLAYOUTPUTCAPABILITIES", error.InvalidFrame, payload_limit);
    };
    if (index >= display_output.outputCount()) {
        return formatOperationError(allocator, "DISPLAYOUTPUTCAPABILITIES", error.NotFound, payload_limit);
    }
    return formatDisplayOutputCapabilitiesResponse(allocator, index, payload_limit);
}

fn appendDisplayModeLine(out: *std.ArrayList(u8), allocator: std.mem.Allocator, payload_limit: usize, mode_index: u16, mode: pal_framebuffer.DisplayOutputMode) Error!void {
    const line = try std.fmt.allocPrint(
        allocator,
        "mode {d} {d}x{d} refresh={d}\n",
        .{ mode_index, mode.width, mode.height, mode.refresh_hz },
    );
    defer allocator.free(line);
    if (out.items.len + line.len > payload_limit) return error.ResponseTooLarge;
    try out.appendSlice(allocator, line);
}

fn handleDisplayOutputModesRequest(allocator: std.mem.Allocator, output_index_text: []const u8, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    const index = std.fmt.parseInt(u16, output_index_text, 10) catch {
        return formatOperationError(allocator, "DISPLAYOUTPUTMODES", error.InvalidFrame, payload_limit);
    };
    if (index >= display_output.outputCount()) {
        return formatOperationError(allocator, "DISPLAYOUTPUTMODES", error.NotFound, payload_limit);
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    const mode_count = pal_framebuffer.displayOutputModeCount(index);
    var mode_index: u16 = 0;
    while (mode_index < mode_count) : (mode_index += 1) {
        const mode = pal_framebuffer.displayOutputMode(index, mode_index) orelse continue;
        try appendDisplayModeLine(&out, allocator, payload_limit, mode_index, mode);
    }

    return out.toOwnedSlice(allocator);
}

fn handleDisplayInterfaceModesRequest(allocator: std.mem.Allocator, interface_name: []const u8, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    const interface_type = display_output.interfaceTypeFromName(interface_name) orelse {
        return formatOperationError(allocator, "DISPLAYINTERFACEMODES", error.InvalidFrame, payload_limit);
    };
    const mode_count = pal_framebuffer.displayOutputModeCountForInterface(interface_type);
    if (mode_count == 0) {
        return formatOperationError(allocator, "DISPLAYINTERFACEMODES", error.NotFound, payload_limit);
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    var mode_index: u16 = 0;
    while (mode_index < mode_count) : (mode_index += 1) {
        const mode = pal_framebuffer.displayOutputModeForInterface(interface_type, mode_index) orelse continue;
        try appendDisplayModeLine(&out, allocator, payload_limit, mode_index, mode);
    }

    return out.toOwnedSlice(allocator);
}

fn handleDisplayInterfaceDetailRequest(allocator: std.mem.Allocator, interface_name: []const u8, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    const interface_type = display_output.interfaceTypeFromName(interface_name) orelse {
        return formatOperationError(allocator, "DISPLAYINTERFACEDETAIL", error.InvalidFrame, payload_limit);
    };
    const index = display_output.connectedOutputIndexForInterface(interface_type) orelse {
        return formatOperationError(allocator, "DISPLAYINTERFACEDETAIL", error.NotFound, payload_limit);
    };
    return formatDisplayOutputDetailResponse(allocator, index, payload_limit);
}

fn handleDisplayInterfaceCapabilitiesRequest(allocator: std.mem.Allocator, interface_name: []const u8, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    const interface_type = display_output.interfaceTypeFromName(interface_name) orelse {
        return formatOperationError(allocator, "DISPLAYINTERFACECAPABILITIES", error.InvalidFrame, payload_limit);
    };
    const index = display_output.connectedOutputIndexForInterface(interface_type) orelse {
        return formatOperationError(allocator, "DISPLAYINTERFACECAPABILITIES", error.NotFound, payload_limit);
    };
    return formatDisplayOutputCapabilitiesResponse(allocator, index, payload_limit);
}

fn handleDisplayModesRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    var index: u16 = 0;
    while (index < framebuffer_console.supportedModeCount()) : (index += 1) {
        const line = try std.fmt.allocPrint(allocator, "mode {d} {d}x{d}\n", .{ index, framebuffer_console.supportedModeWidth(index), framebuffer_console.supportedModeHeight(index) });
        defer allocator.free(line);
        if (out.items.len + line.len > payload_limit) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

fn handleDisplaySetRequest(allocator: std.mem.Allocator, width: u16, height: u16, payload_limit: usize) Error![]u8 {
    framebuffer_console.setMode(width, height) catch |err| {
        return formatOperationError(allocator, "DISPLAYSET", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "DISPLAY {d}x{d}\n", .{ width, height });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayActivateRequest(allocator: std.mem.Allocator, connector_name: []const u8, payload_limit: usize) Error![]u8 {
    const connector_type = package_store.parseConnectorType(connector_name) catch |err| {
        return formatOperationError(allocator, "DISPLAYACTIVATE", err, payload_limit);
    };
    tool_exec.activateDisplayConnector(connector_type) catch |err| {
        return formatOperationError(allocator, "DISPLAYACTIVATE", err, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYACTIVATE {s} scanout={d} current={d}x{d}\n",
        .{
            displayConnectorName(output.connector_type),
            output.active_scanout,
            output.current_width,
            output.current_height,
        },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayActivatePreferredRequest(allocator: std.mem.Allocator, connector_name: []const u8, payload_limit: usize) Error![]u8 {
    const connector_type = package_store.parseConnectorType(connector_name) catch |err| {
        return formatOperationError(allocator, "DISPLAYACTIVATEPREFERRED", err, payload_limit);
    };
    tool_exec.activateDisplayConnectorPreferred(connector_type) catch |err| {
        return formatOperationError(allocator, "DISPLAYACTIVATEPREFERRED", err, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYACTIVATEPREFERRED {s} scanout={d} current={d}x{d} preferred={d}x{d}\n",
        .{
            displayConnectorName(output.connector_type),
            output.active_scanout,
            output.current_width,
            output.current_height,
            if (output.preferred_width != 0) output.preferred_width else output.current_width,
            if (output.preferred_height != 0) output.preferred_height else output.current_height,
        },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayActivateInterfaceRequest(allocator: std.mem.Allocator, interface_name: []const u8, payload_limit: usize) Error![]u8 {
    const interface_type = display_output.interfaceTypeFromName(interface_name) orelse {
        return formatOperationError(allocator, "DISPLAYACTIVATEINTERFACE", error.InvalidFrame, payload_limit);
    };
    tool_exec.activateDisplayInterface(interface_type) catch |err| {
        return formatOperationError(allocator, "DISPLAYACTIVATEINTERFACE", err, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYACTIVATEINTERFACE {s} connector={s} scanout={d} current={d}x{d}\n",
        .{
            displayInterfaceName(output.reserved0),
            displayConnectorName(output.connector_type),
            output.active_scanout,
            output.current_width,
            output.current_height,
        },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayActivateInterfacePreferredRequest(allocator: std.mem.Allocator, interface_name: []const u8, payload_limit: usize) Error![]u8 {
    const interface_type = display_output.interfaceTypeFromName(interface_name) orelse {
        return formatOperationError(allocator, "DISPLAYACTIVATEINTERFACEPREFERRED", error.InvalidFrame, payload_limit);
    };
    tool_exec.activateDisplayInterfacePreferred(interface_type) catch |err| {
        return formatOperationError(allocator, "DISPLAYACTIVATEINTERFACEPREFERRED", err, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYACTIVATEINTERFACEPREFERRED {s} connector={s} scanout={d} current={d}x{d} preferred={d}x{d}\n",
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
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayInterfaceSetRequest(allocator: std.mem.Allocator, interface_name: []const u8, width: u16, height: u16, payload_limit: usize) Error![]u8 {
    const interface_type = display_output.interfaceTypeFromName(interface_name) orelse {
        return formatOperationError(allocator, "DISPLAYINTERFACESET", error.InvalidFrame, payload_limit);
    };
    tool_exec.setDisplayInterfaceMode(interface_type, width, height) catch |err| {
        return formatOperationError(allocator, "DISPLAYINTERFACESET", err, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYINTERFACESET {s} {d}x{d} connector={s} scanout={d}\n",
        .{
            displayInterfaceName(output.reserved0),
            output.current_width,
            output.current_height,
            displayConnectorName(output.connector_type),
            output.active_scanout,
        },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayInterfaceActivateModeRequest(allocator: std.mem.Allocator, interface_name: []const u8, mode_index: u16, payload_limit: usize) Error![]u8 {
    const interface_type = display_output.interfaceTypeFromName(interface_name) orelse {
        return formatOperationError(allocator, "DISPLAYINTERFACEACTIVATEMODE", error.InvalidFrame, payload_limit);
    };
    tool_exec.activateDisplayInterfaceMode(interface_type, mode_index) catch |err| {
        return formatOperationError(allocator, "DISPLAYINTERFACEACTIVATEMODE", err, payload_limit);
    };
    const mode = pal_framebuffer.displayOutputModeForInterface(interface_type, mode_index) orelse {
        return formatOperationError(allocator, "DISPLAYINTERFACEACTIVATEMODE", error.UnsupportedMode, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYINTERFACEACTIVATEMODE {s} {d} {d}x{d} connector={s} scanout={d}\n",
        .{
            displayInterfaceName(output.reserved0),
            mode_index,
            mode.width,
            mode.height,
            displayConnectorName(output.connector_type),
            output.active_scanout,
        },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayActivateOutputRequest(allocator: std.mem.Allocator, output_index_text: []const u8, payload_limit: usize) Error![]u8 {
    const output_index = std.fmt.parseInt(u16, output_index_text, 10) catch {
        return formatOperationError(allocator, "DISPLAYACTIVATEOUTPUT", error.InvalidFrame, payload_limit);
    };
    tool_exec.activateDisplayOutput(output_index) catch |err| {
        return formatOperationError(allocator, "DISPLAYACTIVATEOUTPUT", err, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYACTIVATEOUTPUT {d} connector={s} scanout={d} current={d}x{d}\n",
        .{
            output_index,
            displayConnectorName(output.connector_type),
            output.active_scanout,
            output.current_width,
            output.current_height,
        },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayActivateOutputPreferredRequest(allocator: std.mem.Allocator, output_index_text: []const u8, payload_limit: usize) Error![]u8 {
    const output_index = std.fmt.parseInt(u16, output_index_text, 10) catch {
        return formatOperationError(allocator, "DISPLAYACTIVATEOUTPUTPREFERRED", error.InvalidFrame, payload_limit);
    };
    tool_exec.activateDisplayOutputPreferred(output_index) catch |err| {
        return formatOperationError(allocator, "DISPLAYACTIVATEOUTPUTPREFERRED", err, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYACTIVATEOUTPUTPREFERRED {d} connector={s} scanout={d} current={d}x{d} preferred={d}x{d}\n",
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
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayOutputSetRequest(allocator: std.mem.Allocator, output_index: u16, width: u16, height: u16, payload_limit: usize) Error![]u8 {
    tool_exec.setDisplayOutputMode(output_index, width, height) catch |err| {
        return formatOperationError(allocator, "DISPLAYOUTPUTSET", err, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYOUTPUTSET {d} {d}x{d} connector={s} scanout={d}\n",
        .{
            output_index,
            output.current_width,
            output.current_height,
            displayConnectorName(output.connector_type),
            output.active_scanout,
        },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayOutputActivateModeRequest(allocator: std.mem.Allocator, output_index: u16, mode_index: u16, payload_limit: usize) Error![]u8 {
    tool_exec.activateDisplayOutputMode(output_index, mode_index) catch |err| {
        return formatOperationError(allocator, "DISPLAYOUTPUTACTIVATEMODE", err, payload_limit);
    };
    const mode = pal_framebuffer.displayOutputMode(output_index, mode_index) orelse {
        return formatOperationError(allocator, "DISPLAYOUTPUTACTIVATEMODE", error.UnsupportedMode, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYOUTPUTACTIVATEMODE {d} {d} {d}x{d} connector={s} scanout={d}\n",
        .{
            output_index,
            mode_index,
            mode.width,
            mode.height,
            displayConnectorName(output.connector_type),
            output.active_scanout,
        },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayProfileListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return display_profile_store.listProfilesAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "DISPLAYPROFILELIST", err, payload_limit);
    };
}

fn handleDisplayProfileInfoRequest(allocator: std.mem.Allocator, profile_name: []const u8, payload_limit: usize) Error![]u8 {
    return display_profile_store.infoAlloc(allocator, profile_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "DISPLAYPROFILEINFO", err, payload_limit);
    };
}

fn handleDisplayProfileActiveRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return display_profile_store.activeProfileInfoAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "DISPLAYPROFILEACTIVE", err, payload_limit);
    };
}

fn handleDisplayProfileSaveRequest(allocator: std.mem.Allocator, profile_name: []const u8, payload_limit: usize) Error![]u8 {
    display_profile_store.saveCurrentProfile(profile_name, 0) catch |err| {
        return formatOperationError(allocator, "DISPLAYPROFILESAVE", err, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYPROFILESAVE {s} output={d} current={d}x{d} connector={s}\n",
        .{
            profile_name,
            output.active_scanout,
            output.current_width,
            output.current_height,
            displayConnectorName(output.connector_type),
        },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayProfileApplyRequest(allocator: std.mem.Allocator, profile_name: []const u8, payload_limit: usize) Error![]u8 {
    display_profile_store.applyProfile(profile_name, 0) catch |err| {
        return formatOperationError(allocator, "DISPLAYPROFILEAPPLY", err, payload_limit);
    };
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "DISPLAYPROFILEAPPLY {s} output={d} current={d}x{d} connector={s}\n",
        .{
            profile_name,
            output.active_scanout,
            output.current_width,
            output.current_height,
            displayConnectorName(output.connector_type),
        },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayProfileDeleteRequest(allocator: std.mem.Allocator, profile_name: []const u8, payload_limit: usize) Error![]u8 {
    display_profile_store.deleteProfile(profile_name, 0) catch |err| {
        return formatOperationError(allocator, "DISPLAYPROFILEDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "DISPLAYPROFILEDELETE {s}\n", .{profile_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleTrustListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return trust_store.listBundlesAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "TRUSTLIST", err, payload_limit);
    };
}

fn handleTrustInfoRequest(allocator: std.mem.Allocator, trust_name: []const u8, payload_limit: usize) Error![]u8 {
    return trust_store.infoAlloc(allocator, trust_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "TRUSTINFO", err, payload_limit);
    };
}

fn handleTrustActiveRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return trust_store.activeBundleInfoAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "TRUSTACTIVE", err, payload_limit);
    };
}

fn handleTrustSelectRequest(allocator: std.mem.Allocator, trust_name: []const u8, payload_limit: usize) Error![]u8 {
    trust_store.selectBundle(trust_name, 0) catch |err| {
        return formatOperationError(allocator, "TRUSTSELECT", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "SELECTED {s}\n", .{trust_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleTrustDeleteRequest(allocator: std.mem.Allocator, trust_name: []const u8, payload_limit: usize) Error![]u8 {
    trust_store.deleteBundle(trust_name, 0) catch |err| {
        return formatOperationError(allocator, "TRUSTDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "DELETED {s}\n", .{trust_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleRuntimeSnapshotRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    const response = runtime_bridge.snapshotAlloc(allocator) catch |err| {
        return formatOperationError(allocator, "RUNTIMESNAPSHOT", err, payload_limit);
    };
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleRuntimeSessionsRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    const response = runtime_bridge.sessionListAlloc(allocator) catch |err| {
        return formatOperationError(allocator, "RUNTIMESESSIONS", err, payload_limit);
    };
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleRuntimeSessionRequest(
    allocator: std.mem.Allocator,
    session_id: []const u8,
    payload_limit: usize,
) Error![]u8 {
    const response = runtime_bridge.sessionInfoAlloc(allocator, session_id) catch |err| {
        return formatOperationError(allocator, "RUNTIMESESSION", err, payload_limit);
    };
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleRuntimeCallRequest(
    allocator: std.mem.Allocator,
    frame_json: []const u8,
    payload_limit: usize,
) Error![]u8 {
    const response = runtime_bridge.handleRpcFrameAlloc(allocator, frame_json) catch |err| {
        return formatOperationError(allocator, "RUNTIMECALL", err, payload_limit);
    };
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
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

fn displayInterfaceName(value: u8) []const u8 {
    return display_output.interfaceName(value);
}

fn resetPersistentStateForTest() void {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    tool_layout.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();
}

fn formatOperationError(
    allocator: std.mem.Allocator,
    operation: []const u8,
    err: anyerror,
    payload_limit: usize,
) Error![]u8 {
    const response = try std.fmt.allocPrint(allocator, "ERR {s}: {s}\n", .{ operation, @errorName(err) });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
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

fn ensureDisplayReady() void {
    if (display_output.statePtr().backend == abi.display_backend_none) {
        _ = framebuffer_console.init();
    }
}

test "baremetal tool service returns stdout for successful commands" {
    const response = try handleCommandRequest(std.testing.allocator, "echo tcp-service-ok", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings("tcp-service-ok\n", response);
}

test "baremetal tool service wraps failing command responses" {
    const response = try handleCommandRequest(std.testing.allocator, "missing-command", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.startsWith(u8, response, "ERR exit=127\n"));
    try std.testing.expect(std.mem.indexOf(u8, response, "unknown command") != null);
}

test "baremetal tool service parses framed command requests" {
    const framed = try parseFramedCommandRequest("REQ 7 echo tcp-service-ok");
    try std.testing.expectEqual(@as(u32, 7), framed.request_id);
    try std.testing.expectEqualStrings("echo tcp-service-ok", framed.command);

    const explicit = try parseFramedCommandRequest("REQ 8 CMD echo tcp-service-ok");
    try std.testing.expectEqual(@as(u32, 8), explicit.request_id);
    try std.testing.expectEqualStrings("echo tcp-service-ok", explicit.command);
}

test "baremetal tool service parses typed framed requests" {
    const put = try parseFramedRequest("REQ 11 PUT /tools/cache/tool.txt 4\nedge");
    try std.testing.expectEqual(@as(u32, 11), put.request_id);
    switch (put.operation) {
        .put => |payload| {
            try std.testing.expectEqualStrings("/tools/cache/tool.txt", payload.path);
            try std.testing.expectEqualStrings("edge", payload.body);
        },
        else => return error.InvalidFrame,
    }

    const get = try parseFramedRequest("REQ 12 GET /tools/cache/tool.txt");
    switch (get.operation) {
        .get => |path| try std.testing.expectEqualStrings("/tools/cache/tool.txt", path),
        else => return error.InvalidFrame,
    }

    const exec = try parseFramedRequest("REQ 12 EXEC echo tcp-service-ok");
    switch (exec.operation) {
        .execute => |command| try std.testing.expectEqualStrings("echo tcp-service-ok", command),
        else => return error.InvalidFrame,
    }

    const stat = try parseFramedRequest("REQ 13 STAT /tools/cache/tool.txt");
    switch (stat.operation) {
        .stat => |path| try std.testing.expectEqualStrings("/tools/cache/tool.txt", path),
        else => return error.InvalidFrame,
    }

    const list = try parseFramedRequest("REQ 14 LIST /tools/cache");
    switch (list.operation) {
        .list => |path| try std.testing.expectEqualStrings("/tools/cache", path),
        else => return error.InvalidFrame,
    }

    const pkg = try parseFramedRequest("REQ 15 PKG demo 4\nedge");
    switch (pkg.operation) {
        .package_install => |payload| {
            try std.testing.expectEqualStrings("demo", payload.path);
            try std.testing.expectEqualStrings("edge", payload.body);
        },
        else => return error.InvalidFrame,
    }

    const pkg_list = try parseFramedRequest("REQ 16 PKGLIST");
    switch (pkg_list.operation) {
        .package_list => {},
        else => return error.InvalidFrame,
    }

    const pkg_info = try parseFramedRequest("REQ 17 PKGINFO demo");
    switch (pkg_info.operation) {
        .package_info => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_app = try parseFramedRequest("REQ 18 PKGAPP demo");
    switch (pkg_app.operation) {
        .package_app => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_display = try parseFramedRequest("REQ 19 PKGDISPLAY demo 1280 720");
    switch (pkg_display.operation) {
        .package_display => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqual(@as(u16, 1280), payload.width);
            try std.testing.expectEqual(@as(u16, 720), payload.height);
        },
        else => return error.InvalidFrame,
    }

    const pkg_run = try parseFramedRequest("REQ 20 PKGRUN demo");
    switch (pkg_run.operation) {
        .package_run => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_put = try parseFramedRequest("REQ 21 PKGPUT demo config/app.json 4\nedge");
    switch (pkg_put.operation) {
        .package_asset_put => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("config/app.json", payload.relative_path);
            try std.testing.expectEqualStrings("edge", payload.body);
        },
        else => return error.InvalidFrame,
    }

    const pkg_ls = try parseFramedRequest("REQ 22 PKGLS demo");
    switch (pkg_ls.operation) {
        .package_asset_list => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_get = try parseFramedRequest("REQ 23 PKGGET demo config/app.json");
    switch (pkg_get.operation) {
        .package_asset_get => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("config/app.json", payload.relative_path);
        },
        else => return error.InvalidFrame,
    }

    const pkg_verify = try parseFramedRequest("REQ 24 PKGVERIFY demo");
    switch (pkg_verify.operation) {
        .package_verify => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_delete = try parseFramedRequest("REQ 25 PKGDELETE demo");
    switch (pkg_delete.operation) {
        .package_delete => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_release_list = try parseFramedRequest("REQ 126 PKGRELEASELIST demo");
    switch (pkg_release_list.operation) {
        .package_release_list => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_release_info = try parseFramedRequest("REQ 129 PKGRELEASEINFO demo r1");
    switch (pkg_release_info.operation) {
        .package_release_info => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("r1", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const pkg_release_save = try parseFramedRequest("REQ 127 PKGRELEASESAVE demo r1");
    switch (pkg_release_save.operation) {
        .package_release_save => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("r1", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const pkg_release_activate = try parseFramedRequest("REQ 128 PKGRELEASEACTIVATE demo r1");
    switch (pkg_release_activate.operation) {
        .package_release_activate => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("r1", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const pkg_release_delete = try parseFramedRequest("REQ 130 PKGRELEASEDELETE demo r1");
    switch (pkg_release_delete.operation) {
        .package_release_delete => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("r1", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const pkg_release_prune = try parseFramedRequest("REQ 131 PKGRELEASEPRUNE demo 1");
    switch (pkg_release_prune.operation) {
        .package_release_prune => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqual(@as(u32, 1), payload.keep);
        },
        else => return error.InvalidFrame,
    }

    const pkg_channel_list = try parseFramedRequest("REQ 132 PKGCHANNELLIST demo");
    switch (pkg_channel_list.operation) {
        .package_channel_list => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_channel_info = try parseFramedRequest("REQ 133 PKGCHANNELINFO demo stable");
    switch (pkg_channel_info.operation) {
        .package_channel_info => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("stable", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const pkg_channel_set = try parseFramedRequest("REQ 134 PKGCHANNELSET demo stable r1");
    switch (pkg_channel_set.operation) {
        .package_channel_set => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("stable", payload.channel);
            try std.testing.expectEqualStrings("r1", payload.release);
        },
        else => return error.InvalidFrame,
    }

    const pkg_channel_activate = try parseFramedRequest("REQ 135 PKGCHANNELACTIVATE demo stable");
    switch (pkg_channel_activate.operation) {
        .package_channel_activate => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("stable", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const display_info = try parseFramedRequest("REQ 26 DISPLAYINFO");
    switch (display_info.operation) {
        .display_info => {},
        else => return error.InvalidFrame,
    }

    const display_outputs = try parseFramedRequest("REQ 27 DISPLAYOUTPUTS");
    switch (display_outputs.operation) {
        .display_outputs => {},
        else => return error.InvalidFrame,
    }

    const display_output_request = try parseFramedRequest("REQ 28 DISPLAYOUTPUT 0");
    switch (display_output_request.operation) {
        .display_output => |payload| try std.testing.expectEqualStrings("0", payload),
        else => return error.InvalidFrame,
    }

    const display_output_detail = try parseFramedRequest("REQ 280 DISPLAYOUTPUTDETAIL 0");
    switch (display_output_detail.operation) {
        .display_output_detail => |payload| try std.testing.expectEqualStrings("0", payload),
        else => return error.InvalidFrame,
    }

    const display_output_capabilities = try parseFramedRequest("REQ 284 DISPLAYOUTPUTCAPABILITIES 0");
    switch (display_output_capabilities.operation) {
        .display_output_capabilities => |payload| try std.testing.expectEqualStrings("0", payload),
        else => return error.InvalidFrame,
    }

    const display_output_modes = try parseFramedRequest("REQ 281 DISPLAYOUTPUTMODES 1");
    switch (display_output_modes.operation) {
        .display_output_modes => |payload| try std.testing.expectEqualStrings("1", payload),
        else => return error.InvalidFrame,
    }

    const display_modes = try parseFramedRequest("REQ 29 DISPLAYMODES");
    switch (display_modes.operation) {
        .display_modes => {},
        else => return error.InvalidFrame,
    }

    const display_set = try parseFramedRequest("REQ 30 DISPLAYSET 800 600");
    switch (display_set.operation) {
        .display_set => |payload| {
            try std.testing.expectEqual(@as(u16, 800), payload.width);
            try std.testing.expectEqual(@as(u16, 600), payload.height);
        },
        else => return error.InvalidFrame,
    }

    const display_activate_preferred = try parseFramedRequest("REQ 38 DISPLAYACTIVATEPREFERRED displayport");
    switch (display_activate_preferred.operation) {
        .display_activate_preferred => |payload| try std.testing.expectEqualStrings("displayport", payload),
        else => return error.InvalidFrame,
    }

    const display_activate_interface = try parseFramedRequest("REQ 138 DISPLAYACTIVATEINTERFACE displayport");
    switch (display_activate_interface.operation) {
        .display_activate_interface => |payload| try std.testing.expectEqualStrings("displayport", payload),
        else => return error.InvalidFrame,
    }

    const display_activate_interface_preferred = try parseFramedRequest("REQ 139 DISPLAYACTIVATEINTERFACEPREFERRED displayport");
    switch (display_activate_interface_preferred.operation) {
        .display_activate_interface_preferred => |payload| try std.testing.expectEqualStrings("displayport", payload),
        else => return error.InvalidFrame,
    }

    const display_interface_detail = try parseFramedRequest("REQ 140 DISPLAYINTERFACEDETAIL displayport");
    switch (display_interface_detail.operation) {
        .display_interface_detail => |payload| try std.testing.expectEqualStrings("displayport", payload),
        else => return error.InvalidFrame,
    }

    const display_interface_capabilities = try parseFramedRequest("REQ 285 DISPLAYINTERFACECAPABILITIES displayport");
    switch (display_interface_capabilities.operation) {
        .display_interface_capabilities => |payload| try std.testing.expectEqualStrings("displayport", payload),
        else => return error.InvalidFrame,
    }

    const display_interface_modes = try parseFramedRequest("REQ 283 DISPLAYINTERFACEMODES displayport");
    switch (display_interface_modes.operation) {
        .display_interface_modes => |payload| try std.testing.expectEqualStrings("displayport", payload),
        else => return error.InvalidFrame,
    }

    const display_interface_set = try parseFramedRequest("REQ 284 DISPLAYINTERFACESET displayport 1024 768");
    switch (display_interface_set.operation) {
        .display_interface_set => |payload| {
            try std.testing.expectEqualStrings("displayport", payload.interface_name);
            try std.testing.expectEqual(@as(u16, 1024), payload.width);
            try std.testing.expectEqual(@as(u16, 768), payload.height);
        },
        else => return error.InvalidFrame,
    }

    const display_interface_activate_mode = try parseFramedRequest("REQ 285 DISPLAYINTERFACEACTIVATEMODE displayport 1");
    switch (display_interface_activate_mode.operation) {
        .display_interface_activate_mode => |payload| {
            try std.testing.expectEqualStrings("displayport", payload.interface_name);
            try std.testing.expectEqual(@as(u16, 1), payload.mode_index);
        },
        else => return error.InvalidFrame,
    }

    const display_activate_output_preferred = try parseFramedRequest("REQ 39 DISPLAYACTIVATEOUTPUTPREFERRED 1");
    switch (display_activate_output_preferred.operation) {
        .display_activate_output_preferred => |payload| try std.testing.expectEqualStrings("1", payload),
        else => return error.InvalidFrame,
    }

    const display_output_set = try parseFramedRequest("REQ 31 DISPLAYOUTPUTSET 1 1024 768");
    switch (display_output_set.operation) {
        .display_output_set => |payload| {
            try std.testing.expectEqual(@as(u16, 1), payload.index);
            try std.testing.expectEqual(@as(u16, 1024), payload.width);
            try std.testing.expectEqual(@as(u16, 768), payload.height);
        },
        else => return error.InvalidFrame,
    }

    const display_output_activate_mode = try parseFramedRequest("REQ 282 DISPLAYOUTPUTACTIVATEMODE 1 1");
    switch (display_output_activate_mode.operation) {
        .display_output_activate_mode => |payload| {
            try std.testing.expectEqual(@as(u16, 1), payload.index);
            try std.testing.expectEqual(@as(u16, 1), payload.mode_index);
        },
        else => return error.InvalidFrame,
    }

    const display_profile_list = try parseFramedRequest("REQ 32 DISPLAYPROFILELIST");
    switch (display_profile_list.operation) {
        .display_profile_list => {},
        else => return error.InvalidFrame,
    }

    const display_profile_info = try parseFramedRequest("REQ 33 DISPLAYPROFILEINFO golden");
    switch (display_profile_info.operation) {
        .display_profile_info => |payload| try std.testing.expectEqualStrings("golden", payload),
        else => return error.InvalidFrame,
    }

    const display_profile_active = try parseFramedRequest("REQ 34 DISPLAYPROFILEACTIVE");
    switch (display_profile_active.operation) {
        .display_profile_active => {},
        else => return error.InvalidFrame,
    }

    const display_profile_save = try parseFramedRequest("REQ 35 DISPLAYPROFILESAVE golden");
    switch (display_profile_save.operation) {
        .display_profile_save => |payload| try std.testing.expectEqualStrings("golden", payload),
        else => return error.InvalidFrame,
    }

    const display_profile_apply = try parseFramedRequest("REQ 36 DISPLAYPROFILEAPPLY golden");
    switch (display_profile_apply.operation) {
        .display_profile_apply => |payload| try std.testing.expectEqualStrings("golden", payload),
        else => return error.InvalidFrame,
    }

    const display_profile_delete = try parseFramedRequest("REQ 37 DISPLAYPROFILEDELETE golden");
    switch (display_profile_delete.operation) {
        .display_profile_delete => |payload| try std.testing.expectEqualStrings("golden", payload),
        else => return error.InvalidFrame,
    }

    const trust_put = try parseFramedRequest("REQ 28 TRUSTPUT fs55-root 4\nedge");
    switch (trust_put.operation) {
        .trust_install => |payload| {
            try std.testing.expectEqualStrings("fs55-root", payload.path);
            try std.testing.expectEqualStrings("edge", payload.body);
        },
        else => return error.InvalidFrame,
    }

    const trust_list = try parseFramedRequest("REQ 29 TRUSTLIST");
    switch (trust_list.operation) {
        .trust_list => {},
        else => return error.InvalidFrame,
    }

    const trust_info = try parseFramedRequest("REQ 30 TRUSTINFO fs55-root");
    switch (trust_info.operation) {
        .trust_info => |trust_name| try std.testing.expectEqualStrings("fs55-root", trust_name),
        else => return error.InvalidFrame,
    }

    const trust_active = try parseFramedRequest("REQ 31 TRUSTACTIVE");
    switch (trust_active.operation) {
        .trust_active => {},
        else => return error.InvalidFrame,
    }

    const trust_select = try parseFramedRequest("REQ 32 TRUSTSELECT fs55-root");
    switch (trust_select.operation) {
        .trust_select => |trust_name| try std.testing.expectEqualStrings("fs55-root", trust_name),
        else => return error.InvalidFrame,
    }

    const trust_delete = try parseFramedRequest("REQ 33 TRUSTDELETE fs55-root");
    switch (trust_delete.operation) {
        .trust_delete => |trust_name| try std.testing.expectEqualStrings("fs55-root", trust_name),
        else => return error.InvalidFrame,
    }

    const app_list = try parseFramedRequest("REQ 34 APPLIST");
    switch (app_list.operation) {
        .app_list => {},
        else => return error.InvalidFrame,
    }

    const app_info = try parseFramedRequest("REQ 35 APPINFO demo");
    switch (app_info.operation) {
        .app_info => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_state = try parseFramedRequest("REQ 36 APPSTATE demo");
    switch (app_state.operation) {
        .app_state => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_history = try parseFramedRequest("REQ 36 APPHISTORY demo");
    switch (app_history.operation) {
        .app_history => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_stdout = try parseFramedRequest("REQ 37 APPSTDOUT demo");
    switch (app_stdout.operation) {
        .app_stdout => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_stderr = try parseFramedRequest("REQ 38 APPSTDERR demo");
    switch (app_stderr.operation) {
        .app_stderr => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_trust = try parseFramedRequest("REQ 39 APPTRUST demo fs55-root");
    switch (app_trust.operation) {
        .app_trust => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("fs55-root", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const app_connector = try parseFramedRequest("REQ 40 APPCONNECTOR demo virtual");
    switch (app_connector.operation) {
        .app_connector => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("virtual", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const app_plan_list = try parseFramedRequest("REQ 140 APPPLANLIST demo");
    switch (app_plan_list.operation) {
        .app_plan_list => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_plan_info = try parseFramedRequest("REQ 141 APPPLANINFO demo golden");
    switch (app_plan_info.operation) {
        .app_plan_info => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("golden", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const app_plan_active = try parseFramedRequest("REQ 142 APPPLANACTIVE demo");
    switch (app_plan_active.operation) {
        .app_plan_active => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_plan_save = try parseFramedRequest("REQ 143 APPPLANSAVE demo golden r3 fs55-root virtual 1280 720 1");
    switch (app_plan_save.operation) {
        .app_plan_save => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("golden", payload.plan_name);
            try std.testing.expectEqualStrings("r3", payload.release_name);
            try std.testing.expectEqualStrings("fs55-root", payload.trust_bundle);
            try std.testing.expectEqual(@as(u8, abi.display_connector_virtual), payload.connector_type);
            try std.testing.expectEqual(@as(u16, 1280), payload.width);
            try std.testing.expectEqual(@as(u16, 720), payload.height);
            try std.testing.expect(payload.autorun);
        },
        else => return error.InvalidFrame,
    }

    const app_plan_apply = try parseFramedRequest("REQ 144 APPPLANAPPLY demo golden");
    switch (app_plan_apply.operation) {
        .app_plan_apply => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("golden", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const app_plan_delete = try parseFramedRequest("REQ 145 APPPLANDELETE demo golden");
    switch (app_plan_delete.operation) {
        .app_plan_delete => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("golden", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const app_suite_list = try parseFramedRequest("REQ 146 APPSUITELIST");
    switch (app_suite_list.operation) {
        .app_suite_list => {},
        else => return error.InvalidFrame,
    }

    const app_suite_info = try parseFramedRequest("REQ 147 APPSUITEINFO duo");
    switch (app_suite_info.operation) {
        .app_suite_info => |suite_name| try std.testing.expectEqualStrings("duo", suite_name),
        else => return error.InvalidFrame,
    }

    const app_suite_save = try parseFramedRequest("REQ 148 APPSUITESAVE duo demo:golden aux:sidecar");
    switch (app_suite_save.operation) {
        .app_suite_save => |payload| {
            try std.testing.expectEqualStrings("duo", payload.suite_name);
            try std.testing.expectEqualStrings("demo:golden aux:sidecar", payload.entries_spec);
        },
        else => return error.InvalidFrame,
    }

    const app_suite_apply = try parseFramedRequest("REQ 149 APPSUITEAPPLY duo");
    switch (app_suite_apply.operation) {
        .app_suite_apply => |suite_name| try std.testing.expectEqualStrings("duo", suite_name),
        else => return error.InvalidFrame,
    }

    const app_suite_run = try parseFramedRequest("REQ 150 APPSUITERUN duo");
    switch (app_suite_run.operation) {
        .app_suite_run => |suite_name| try std.testing.expectEqualStrings("duo", suite_name),
        else => return error.InvalidFrame,
    }

    const app_suite_delete = try parseFramedRequest("REQ 151 APPSUITEDELETE duo");
    switch (app_suite_delete.operation) {
        .app_suite_delete => |suite_name| try std.testing.expectEqualStrings("duo", suite_name),
        else => return error.InvalidFrame,
    }

    const app_suite_release_list = try parseFramedRequest("REQ 176 APPSUITERELEASELIST duo");
    switch (app_suite_release_list.operation) {
        .app_suite_release_list => |suite_name| try std.testing.expectEqualStrings("duo", suite_name),
        else => return error.InvalidFrame,
    }

    const app_suite_release_info = try parseFramedRequest("REQ 177 APPSUITERELEASEINFO duo golden");
    switch (app_suite_release_info.operation) {
        .app_suite_release_info => |payload| {
            try std.testing.expectEqualStrings("duo", payload.suite_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const app_suite_release_save = try parseFramedRequest("REQ 178 APPSUITERELEASESAVE duo golden");
    switch (app_suite_release_save.operation) {
        .app_suite_release_save => |payload| {
            try std.testing.expectEqualStrings("duo", payload.suite_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const app_suite_release_activate = try parseFramedRequest("REQ 179 APPSUITERELEASEACTIVATE duo golden");
    switch (app_suite_release_activate.operation) {
        .app_suite_release_activate => |payload| {
            try std.testing.expectEqualStrings("duo", payload.suite_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const app_suite_release_delete = try parseFramedRequest("REQ 180 APPSUITERELEASEDELETE duo golden");
    switch (app_suite_release_delete.operation) {
        .app_suite_release_delete => |payload| {
            try std.testing.expectEqualStrings("duo", payload.suite_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const app_suite_release_prune = try parseFramedRequest("REQ 181 APPSUITERELEASEPRUNE duo 1");
    switch (app_suite_release_prune.operation) {
        .app_suite_release_prune => |payload| {
            try std.testing.expectEqualStrings("duo", payload.suite_name);
            try std.testing.expectEqual(@as(u32, 1), payload.keep);
        },
        else => return error.InvalidFrame,
    }

    const app_suite_channel_list = try parseFramedRequest("REQ 182 APPSUITECHANNELLIST duo");
    switch (app_suite_channel_list.operation) {
        .app_suite_channel_list => |suite_name| try std.testing.expectEqualStrings("duo", suite_name),
        else => return error.InvalidFrame,
    }

    const app_suite_channel_info = try parseFramedRequest("REQ 183 APPSUITECHANNELINFO duo stable");
    switch (app_suite_channel_info.operation) {
        .app_suite_channel_info => |payload| {
            try std.testing.expectEqualStrings("duo", payload.suite_name);
            try std.testing.expectEqualStrings("stable", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const app_suite_channel_set = try parseFramedRequest("REQ 184 APPSUITECHANNELSET duo stable golden");
    switch (app_suite_channel_set.operation) {
        .app_suite_channel_set => |payload| {
            try std.testing.expectEqualStrings("duo", payload.suite_name);
            try std.testing.expectEqualStrings("stable", payload.channel);
            try std.testing.expectEqualStrings("golden", payload.release);
        },
        else => return error.InvalidFrame,
    }

    const app_suite_channel_activate = try parseFramedRequest("REQ 185 APPSUITECHANNELACTIVATE duo stable");
    switch (app_suite_channel_activate.operation) {
        .app_suite_channel_activate => |payload| {
            try std.testing.expectEqualStrings("duo", payload.suite_name);
            try std.testing.expectEqualStrings("stable", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const workspace_suite_list = try parseFramedRequest("REQ 186 WORKSPACESUITELIST");
    switch (workspace_suite_list.operation) {
        .workspace_suite_list => {},
        else => return error.InvalidFrame,
    }

    const workspace_suite_info = try parseFramedRequest("REQ 187 WORKSPACESUITEINFO crew");
    switch (workspace_suite_info.operation) {
        .workspace_suite_info => |suite_name| try std.testing.expectEqualStrings("crew", suite_name),
        else => return error.InvalidFrame,
    }

    const workspace_suite_save = try parseFramedRequest("REQ 188 WORKSPACESUITESAVE crew ops sidecar");
    switch (workspace_suite_save.operation) {
        .workspace_suite_save => |payload| {
            try std.testing.expectEqualStrings("crew", payload.suite_name);
            try std.testing.expectEqualStrings("ops sidecar", payload.entries_spec);
        },
        else => return error.InvalidFrame,
    }

    const workspace_suite_apply = try parseFramedRequest("REQ 189 WORKSPACESUITEAPPLY crew");
    switch (workspace_suite_apply.operation) {
        .workspace_suite_apply => |suite_name| try std.testing.expectEqualStrings("crew", suite_name),
        else => return error.InvalidFrame,
    }

    const workspace_suite_run = try parseFramedRequest("REQ 190 WORKSPACESUITERUN crew");
    switch (workspace_suite_run.operation) {
        .workspace_suite_run => |suite_name| try std.testing.expectEqualStrings("crew", suite_name),
        else => return error.InvalidFrame,
    }

    const workspace_suite_delete = try parseFramedRequest("REQ 191 WORKSPACESUITEDELETE crew");
    switch (workspace_suite_delete.operation) {
        .workspace_suite_delete => |suite_name| try std.testing.expectEqualStrings("crew", suite_name),
        else => return error.InvalidFrame,
    }

    const workspace_suite_release_list = try parseFramedRequest("REQ 192 WORKSPACESUITERELEASELIST crew");
    switch (workspace_suite_release_list.operation) {
        .workspace_suite_release_list => |suite_name| try std.testing.expectEqualStrings("crew", suite_name),
        else => return error.InvalidFrame,
    }

    const workspace_suite_release_info = try parseFramedRequest("REQ 193 WORKSPACESUITERELEASEINFO crew golden");
    switch (workspace_suite_release_info.operation) {
        .workspace_suite_release_info => |payload| {
            try std.testing.expectEqualStrings("crew", payload.suite_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const workspace_suite_release_save = try parseFramedRequest("REQ 194 WORKSPACESUITERELEASESAVE crew golden");
    switch (workspace_suite_release_save.operation) {
        .workspace_suite_release_save => |payload| {
            try std.testing.expectEqualStrings("crew", payload.suite_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const workspace_suite_release_activate = try parseFramedRequest("REQ 195 WORKSPACESUITERELEASEACTIVATE crew golden");
    switch (workspace_suite_release_activate.operation) {
        .workspace_suite_release_activate => |payload| {
            try std.testing.expectEqualStrings("crew", payload.suite_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const workspace_suite_release_delete = try parseFramedRequest("REQ 196 WORKSPACESUITERELEASEDELETE crew golden");
    switch (workspace_suite_release_delete.operation) {
        .workspace_suite_release_delete => |payload| {
            try std.testing.expectEqualStrings("crew", payload.suite_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const workspace_suite_release_prune = try parseFramedRequest("REQ 197 WORKSPACESUITERELEASEPRUNE crew 1");
    switch (workspace_suite_release_prune.operation) {
        .workspace_suite_release_prune => |payload| {
            try std.testing.expectEqualStrings("crew", payload.suite_name);
            try std.testing.expectEqual(@as(u32, 1), payload.keep);
        },
        else => return error.InvalidFrame,
    }

    const workspace_suite_channel_list = try parseFramedRequest("REQ 198 WORKSPACESUITECHANNELLIST crew");
    switch (workspace_suite_channel_list.operation) {
        .workspace_suite_channel_list => |suite_name| try std.testing.expectEqualStrings("crew", suite_name),
        else => return error.InvalidFrame,
    }

    const workspace_suite_channel_info = try parseFramedRequest("REQ 199 WORKSPACESUITECHANNELINFO crew stable");
    switch (workspace_suite_channel_info.operation) {
        .workspace_suite_channel_info => |payload| {
            try std.testing.expectEqualStrings("crew", payload.suite_name);
            try std.testing.expectEqualStrings("stable", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const workspace_suite_channel_set = try parseFramedRequest("REQ 200 WORKSPACESUITECHANNELSET crew stable golden");
    switch (workspace_suite_channel_set.operation) {
        .workspace_suite_channel_set => |payload| {
            try std.testing.expectEqualStrings("crew", payload.suite_name);
            try std.testing.expectEqualStrings("stable", payload.channel);
            try std.testing.expectEqualStrings("golden", payload.release);
        },
        else => return error.InvalidFrame,
    }

    const workspace_suite_channel_activate = try parseFramedRequest("REQ 201 WORKSPACESUITECHANNELACTIVATE crew stable");
    switch (workspace_suite_channel_activate.operation) {
        .workspace_suite_channel_activate => |payload| {
            try std.testing.expectEqualStrings("crew", payload.suite_name);
            try std.testing.expectEqualStrings("stable", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const workspace_list = try parseFramedRequest("REQ 152 WORKSPACELIST");
    switch (workspace_list.operation) {
        .workspace_list => {},
        else => return error.InvalidFrame,
    }

    const workspace_info = try parseFramedRequest("REQ 153 WORKSPACEINFO ops");
    switch (workspace_info.operation) {
        .workspace_info => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_save = try parseFramedRequest("REQ 154 WORKSPACESAVE ops duo fs55-backup 1024 768 demo:stable:r3");
    switch (workspace_save.operation) {
        .workspace_save => |payload| {
            try std.testing.expectEqualStrings("ops", payload.name);
            try std.testing.expectEqualStrings("duo", payload.suite_name);
            try std.testing.expectEqualStrings("fs55-backup", payload.trust_bundle);
            try std.testing.expectEqual(@as(u16, 1024), payload.width);
            try std.testing.expectEqual(@as(u16, 768), payload.height);
            try std.testing.expectEqualStrings("demo:stable:r3", payload.entries_spec);
        },
        else => return error.InvalidFrame,
    }

    const workspace_apply = try parseFramedRequest("REQ 155 WORKSPACEAPPLY ops");
    switch (workspace_apply.operation) {
        .workspace_apply => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_run = try parseFramedRequest("REQ 156 WORKSPACERUN ops");
    switch (workspace_run.operation) {
        .workspace_run => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_state = try parseFramedRequest("REQ 157 WORKSPACESTATE ops");
    switch (workspace_state.operation) {
        .workspace_state => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_history = try parseFramedRequest("REQ 158 WORKSPACEHISTORY ops");
    switch (workspace_history.operation) {
        .workspace_history => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_stdout = try parseFramedRequest("REQ 159 WORKSPACESTDOUT ops");
    switch (workspace_stdout.operation) {
        .workspace_stdout => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_stderr = try parseFramedRequest("REQ 160 WORKSPACESTDERR ops");
    switch (workspace_stderr.operation) {
        .workspace_stderr => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_delete = try parseFramedRequest("REQ 161 WORKSPACEDELETE ops");
    switch (workspace_delete.operation) {
        .workspace_delete => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_release_list = try parseFramedRequest("REQ 166 WORKSPACERELEASELIST ops");
    switch (workspace_release_list.operation) {
        .workspace_release_list => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_release_info = try parseFramedRequest("REQ 167 WORKSPACERELEASEINFO ops golden");
    switch (workspace_release_info.operation) {
        .workspace_release_info => |payload| {
            try std.testing.expectEqualStrings("ops", payload.workspace_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const workspace_release_save = try parseFramedRequest("REQ 168 WORKSPACERELEASESAVE ops golden");
    switch (workspace_release_save.operation) {
        .workspace_release_save => |payload| {
            try std.testing.expectEqualStrings("ops", payload.workspace_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const workspace_release_activate = try parseFramedRequest("REQ 169 WORKSPACERELEASEACTIVATE ops golden");
    switch (workspace_release_activate.operation) {
        .workspace_release_activate => |payload| {
            try std.testing.expectEqualStrings("ops", payload.workspace_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const workspace_release_delete = try parseFramedRequest("REQ 170 WORKSPACERELEASEDELETE ops golden");
    switch (workspace_release_delete.operation) {
        .workspace_release_delete => |payload| {
            try std.testing.expectEqualStrings("ops", payload.workspace_name);
            try std.testing.expectEqualStrings("golden", payload.release_name);
        },
        else => return error.InvalidFrame,
    }

    const workspace_release_prune = try parseFramedRequest("REQ 171 WORKSPACERELEASEPRUNE ops 1");
    switch (workspace_release_prune.operation) {
        .workspace_release_prune => |payload| {
            try std.testing.expectEqualStrings("ops", payload.workspace_name);
            try std.testing.expectEqual(@as(u32, 1), payload.keep);
        },
        else => return error.InvalidFrame,
    }

    const workspace_channel_list = try parseFramedRequest("REQ 172 WORKSPACECHANNELLIST ops");
    switch (workspace_channel_list.operation) {
        .workspace_channel_list => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_channel_info = try parseFramedRequest("REQ 173 WORKSPACECHANNELINFO ops stable");
    switch (workspace_channel_info.operation) {
        .workspace_channel_info => |payload| {
            try std.testing.expectEqualStrings("ops", payload.workspace_name);
            try std.testing.expectEqualStrings("stable", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const workspace_channel_set = try parseFramedRequest("REQ 174 WORKSPACECHANNELSET ops stable golden");
    switch (workspace_channel_set.operation) {
        .workspace_channel_set => |payload| {
            try std.testing.expectEqualStrings("ops", payload.workspace_name);
            try std.testing.expectEqualStrings("stable", payload.channel);
            try std.testing.expectEqualStrings("golden", payload.release);
        },
        else => return error.InvalidFrame,
    }

    const workspace_channel_activate = try parseFramedRequest("REQ 175 WORKSPACECHANNELACTIVATE ops stable");
    switch (workspace_channel_activate.operation) {
        .workspace_channel_activate => |payload| {
            try std.testing.expectEqualStrings("ops", payload.workspace_name);
            try std.testing.expectEqualStrings("stable", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const workspace_autorun_list = try parseFramedRequest("REQ 162 WORKSPACEAUTORUNLIST");
    switch (workspace_autorun_list.operation) {
        .workspace_autorun_list => {},
        else => return error.InvalidFrame,
    }

    const workspace_autorun_add = try parseFramedRequest("REQ 163 WORKSPACEAUTORUNADD ops");
    switch (workspace_autorun_add.operation) {
        .workspace_autorun_add => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_autorun_remove = try parseFramedRequest("REQ 164 WORKSPACEAUTORUNREMOVE ops");
    switch (workspace_autorun_remove.operation) {
        .workspace_autorun_remove => |workspace_name| try std.testing.expectEqualStrings("ops", workspace_name),
        else => return error.InvalidFrame,
    }

    const workspace_autorun_run = try parseFramedRequest("REQ 165 WORKSPACEAUTORUNRUN");
    switch (workspace_autorun_run.operation) {
        .workspace_autorun_run => {},
        else => return error.InvalidFrame,
    }

    const app_run = try parseFramedRequest("REQ 41 APPRUN demo");
    switch (app_run.operation) {
        .app_run => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_delete = try parseFramedRequest("REQ 42 APPDELETE demo");
    switch (app_delete.operation) {
        .app_delete => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_autorun_list = try parseFramedRequest("REQ 43 APPAUTORUNLIST");
    switch (app_autorun_list.operation) {
        .app_autorun_list => {},
        else => return error.InvalidFrame,
    }

    const app_autorun_add = try parseFramedRequest("REQ 44 APPAUTORUNADD demo");
    switch (app_autorun_add.operation) {
        .app_autorun_add => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_autorun_remove = try parseFramedRequest("REQ 45 APPAUTORUNREMOVE demo");
    switch (app_autorun_remove.operation) {
        .app_autorun_remove => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_autorun_run = try parseFramedRequest("REQ 46 APPAUTORUNRUN");
    switch (app_autorun_run.operation) {
        .app_autorun_run => {},
        else => return error.InvalidFrame,
    }

    const install = try parseFramedRequest("REQ 41 INSTALL");
    switch (install.operation) {
        .install => {},
        else => return error.InvalidFrame,
    }

    const manifest = try parseFramedRequest("REQ 42 MANIFEST");
    switch (manifest.operation) {
        .manifest => {},
        else => return error.InvalidFrame,
    }
}

test "baremetal tool service parses framed request prefixes for batches" {
    const batched = "REQ 11 GET /tools/cache/tool.txt\nREQ 12 STAT /tools/cache/tool.txt";
    const first = try parseFramedRequestPrefix(batched);
    try std.testing.expectEqual(@as(usize, "REQ 11 GET /tools/cache/tool.txt\n".len), first.consumed_len);
    switch (first.framed.operation) {
        .get => |path| try std.testing.expectEqualStrings("/tools/cache/tool.txt", path),
        else => return error.InvalidFrame,
    }

    const second = try parseFramedRequestPrefix(batched[first.consumed_len..]);
    switch (second.framed.operation) {
        .stat => |path| try std.testing.expectEqualStrings("/tools/cache/tool.txt", path),
        else => return error.InvalidFrame,
    }
}

test "baremetal tool service parses framed package asset prefixes for batches" {
    const batched = "REQ 21 PKGPUT demo config/app.json 4\nedge\nREQ 22 DISPLAYINFO";
    const first = try parseFramedRequestPrefix(batched);
    try std.testing.expectEqual(@as(usize, "REQ 21 PKGPUT demo config/app.json 4\nedge".len), first.consumed_len);
    switch (first.framed.operation) {
        .package_asset_put => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("config/app.json", payload.relative_path);
            try std.testing.expectEqualStrings("edge", payload.body);
        },
        else => return error.InvalidFrame,
    }

    const second = try parseFramedRequestPrefix(batched[first.consumed_len..]);
    switch (second.framed.operation) {
        .display_info => {},
        else => return error.InvalidFrame,
    }
}

test "baremetal tool service rejects invalid framed requests" {
    try std.testing.expectError(error.InvalidFrame, parseFramedCommandRequest("echo tcp-service-ok"));
    try std.testing.expectError(error.InvalidFrame, parseFramedCommandRequest("REQ nope echo tcp-service-ok"));
    try std.testing.expectError(error.InvalidFrame, parseFramedCommandRequest("REQ 7"));
    try std.testing.expectError(error.InvalidFrame, parseFramedRequest("REQ 11 PUT /tools/cache/tool.txt nope\nedge"));
    try std.testing.expectError(error.InvalidFrame, parseFramedRequest("REQ 11 PUT /tools/cache/tool.txt 5\nedge"));
}

test "baremetal tool service returns framed responses for successful commands" {
    const response = try handleFramedCommandRequest(std.testing.allocator, "REQ 7 echo tcp-service-ok", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings("RESP 7 15\ntcp-service-ok\n", response);
}

test "baremetal tool service returns framed responses for failing commands" {
    const response = try handleFramedCommandRequest(std.testing.allocator, "REQ 9 missing-command", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.startsWith(u8, response, "RESP 9 "));
    try std.testing.expect(std.mem.indexOf(u8, response, "ERR exit=127\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "unknown command") != null);
}

test "baremetal tool service returns structured exec responses" {
    const response = try handleFramedRequest(std.testing.allocator, "REQ 10 EXEC echo tcp-service-ok", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.startsWith(u8, response, "RESP 10 "));
    try std.testing.expect(std.mem.indexOf(u8, response, "exit=0 stdout_len=15 stderr_len=0\nstdout:\ntcp-service-ok\nstderr:\n") != null);
}

test "baremetal tool service returns structured exec stderr for failures" {
    const response = try handleFramedRequest(std.testing.allocator, "REQ 11 EXEC missing-command", 256, 256, 512);
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.startsWith(u8, response, "RESP 11 "));
    try std.testing.expect(std.mem.indexOf(u8, response, "exit=127") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "stderr:\nunknown command") != null);
}

test "baremetal tool service handles framed filesystem requests" {
    resetPersistentStateForTest();

    const put_response = try handleFramedRequest(std.testing.allocator, "REQ 11 PUT /tools/cache/tool.txt 4\nedge", 256, 256, 256);
    defer std.testing.allocator.free(put_response);
    try std.testing.expectEqualStrings("RESP 11 39\nWROTE 4 bytes to /tools/cache/tool.txt\n", put_response);

    const get_response = try handleFramedRequest(std.testing.allocator, "REQ 12 GET /tools/cache/tool.txt", 256, 256, 256);
    defer std.testing.allocator.free(get_response);
    try std.testing.expectEqualStrings("RESP 12 4\nedge", get_response);

    const stat_response = try handleFramedRequest(std.testing.allocator, "REQ 13 STAT /tools/cache/tool.txt", 256, 256, 256);
    defer std.testing.allocator.free(stat_response);
    try std.testing.expectEqualStrings("RESP 13 44\npath=/tools/cache/tool.txt kind=file size=4\n", stat_response);

    const list_response = try handleFramedRequest(std.testing.allocator, "REQ 14 LIST /tools/cache", 256, 256, 256);
    defer std.testing.allocator.free(list_response);
    try std.testing.expectEqualStrings("RESP 14 16\nfile tool.txt 4\n", list_response);
}

test "baremetal tool service exposes virtual proc sys and dev overlays" {
    resetPersistentStateForTest();

    var runtime = try runtime_bridge.initRuntime(std.heap.page_allocator);
    defer runtime.deinit();

    var exec_result = try runtime.execRunFromFrame(
        std.heap.page_allocator,
        "{\"id\":\"svc-proc\",\"method\":\"exec.run\",\"params\":{\"sessionId\":\"svc-proc\",\"command\":\"echo svc-proc\",\"timeoutMs\":1000}}",
    );
    defer exec_result.deinit(std.heap.page_allocator);
    try std.testing.expect(exec_result.ok);

    const list_root = try handleFramedRequest(std.testing.allocator, "REQ 15 LIST /", 256, 256, 256);
    defer std.testing.allocator.free(list_root);
    try std.testing.expect(std.mem.startsWith(u8, list_root, "RESP 15 "));
    try std.testing.expect(std.mem.indexOf(u8, list_root, "dir dev\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, list_root, "dir proc\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, list_root, "dir sys\n") != null);

    const get_snapshot = try handleFramedRequest(std.testing.allocator, "REQ 16 GET /proc/runtime/snapshot", 512, 256, 512);
    defer std.testing.allocator.free(get_snapshot);
    try std.testing.expect(std.mem.startsWith(u8, get_snapshot, "RESP 16 "));
    try std.testing.expect(std.mem.indexOf(u8, get_snapshot, "state_path=/runtime/state/runtime-state.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_snapshot, "sessions=1") != null);

    const get_session = try handleFramedRequest(std.testing.allocator, "REQ 17 GET /proc/runtime/sessions/svc-proc", 512, 256, 512);
    defer std.testing.allocator.free(get_session);
    try std.testing.expect(std.mem.startsWith(u8, get_session, "RESP 17 "));
    try std.testing.expect(std.mem.indexOf(u8, get_session, "id=svc-proc") != null);

    const get_storage = try handleFramedRequest(std.testing.allocator, "REQ 18 GET /sys/storage/state", 512, 256, 512);
    defer std.testing.allocator.free(get_storage);
    try std.testing.expect(std.mem.startsWith(u8, get_storage, "RESP 18 "));
    try std.testing.expect(std.mem.indexOf(u8, get_storage, "backend=ram_disk") != null);

    const get_dev_storage = try handleFramedRequest(std.testing.allocator, "REQ 20 GET /dev/storage/state", 512, 256, 512);
    defer std.testing.allocator.free(get_dev_storage);
    try std.testing.expect(std.mem.startsWith(u8, get_dev_storage, "RESP 20 "));
    try std.testing.expect(std.mem.indexOf(u8, get_dev_storage, "backend=ram_disk") != null);

    const stat_snapshot = try handleFramedRequest(std.testing.allocator, "REQ 19 STAT /proc/runtime/snapshot", 256, 256, 256);
    defer std.testing.allocator.free(stat_snapshot);
    try std.testing.expect(std.mem.startsWith(u8, stat_snapshot, "RESP 19 "));
    try std.testing.expect(std.mem.indexOf(u8, stat_snapshot, "path=/proc/runtime/snapshot kind=file size=") != null);
}

test "baremetal tool service uploads and runs persisted scripts" {
    resetPersistentStateForTest();

    const script = "write-file /tools/out/data.txt tcp-service-persisted";
    const put_script_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 21 PUT /tools/scripts/net.oc {d}\n{s}", .{ script.len, script });
    defer std.testing.allocator.free(put_script_request);
    const put_script_response = try handleFramedRequest(std.testing.allocator, put_script_request, 512, 256, 512);
    defer std.testing.allocator.free(put_script_response);
    try std.testing.expectEqualStrings("RESP 21 40\nWROTE 52 bytes to /tools/scripts/net.oc\n", put_script_response);

    const run_script_response = try handleFramedRequest(std.testing.allocator, "REQ 22 CMD run-script /tools/scripts/net.oc", 512, 256, 512);
    defer std.testing.allocator.free(run_script_response);
    try std.testing.expectEqualStrings("RESP 22 38\nwrote 21 bytes to /tools/out/data.txt\n", run_script_response);

    const read_output_response = try handleFramedRequest(std.testing.allocator, "REQ 23 GET /tools/out/data.txt", 512, 256, 512);
    defer std.testing.allocator.free(read_output_response);
    try std.testing.expectEqualStrings("RESP 23 21\ntcp-service-persisted", read_output_response);

    const readback = try filesystem.readFileAlloc(std.testing.allocator, "/tools/out/data.txt", 64);
    defer std.testing.allocator.free(readback);
    try std.testing.expectEqualStrings("tcp-service-persisted", readback);
}

test "baremetal tool service installs lists and runs persisted packages" {
    resetPersistentStateForTest();

    const script = "mkdir /pkg/out\nwrite-file /pkg/out/result.txt pkg-service-data\necho pkg-service-ok";
    const install_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 31 PKG demo {d}\n{s}", .{ script.len, script });
    defer std.testing.allocator.free(install_request);

    const install_response = try handleFramedRequest(std.testing.allocator, install_request, 512, 256, 512);
    defer std.testing.allocator.free(install_response);
    try std.testing.expect(std.mem.startsWith(u8, install_response, "RESP 31 "));
    try std.testing.expect(std.mem.indexOf(u8, install_response, "INSTALLED demo -> /packages/demo/bin/main.oc\n") != null);

    const list_response = try handleFramedRequest(std.testing.allocator, "REQ 32 PKGLIST", 512, 256, 512);
    defer std.testing.allocator.free(list_response);
    try std.testing.expectEqualStrings("RESP 32 5\ndemo\n", list_response);

    const info_response = try handleFramedRequest(std.testing.allocator, "REQ 33 PKGINFO demo", 512, 256, 512);
    defer std.testing.allocator.free(info_response);
    try std.testing.expect(std.mem.startsWith(u8, info_response, "RESP 33 "));
    try std.testing.expect(std.mem.indexOf(u8, info_response, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "root=/packages/demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "asset_root=/packages/demo/assets") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "asset_count=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "display_width=640") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "display_height=400") != null);

    const app_response = try handleFramedRequest(std.testing.allocator, "REQ 34 PKGAPP demo", 512, 256, 512);
    defer std.testing.allocator.free(app_response);
    try std.testing.expect(std.mem.startsWith(u8, app_response, "RESP 34 "));
    try std.testing.expect(std.mem.indexOf(u8, app_response, "entrypoint=/packages/demo/bin/main.oc") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_response, "display_width=640") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_response, "display_height=400") != null);

    const pkg_display_response = try handleFramedRequest(std.testing.allocator, "REQ 35 PKGDISPLAY demo 1280 720", 512, 256, 512);
    defer std.testing.allocator.free(pkg_display_response);
    try std.testing.expectEqualStrings("RESP 35 22\nDISPLAY demo 1280x720\n", pkg_display_response);

    const asset_body = "{\"mode\":\"tcp\"}";
    const asset_put_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 36 PKGPUT demo config/app.json {d}\n{s}", .{ asset_body.len, asset_body });
    defer std.testing.allocator.free(asset_put_request);
    const asset_put_response = try handleFramedRequest(std.testing.allocator, asset_put_request, 512, 256, 512);
    defer std.testing.allocator.free(asset_put_response);
    try std.testing.expectEqualStrings("RESP 36 52\nASSET demo -> /packages/demo/assets/config/app.json\n", asset_put_response);

    const asset_list_response = try handleFramedRequest(std.testing.allocator, "REQ 37 PKGLS demo", 512, 256, 512);
    defer std.testing.allocator.free(asset_list_response);
    try std.testing.expectEqualStrings("RESP 37 11\ndir config\n", asset_list_response);

    const asset_get_response = try handleFramedRequest(std.testing.allocator, "REQ 38 PKGGET demo config/app.json", 512, 256, 512);
    defer std.testing.allocator.free(asset_get_response);
    try std.testing.expectEqualStrings("RESP 38 14\n{\"mode\":\"tcp\"}", asset_get_response);

    const asset_readback = try filesystem.readFileAlloc(std.testing.allocator, "/packages/demo/assets/config/app.json", 64);
    defer std.testing.allocator.free(asset_readback);
    try std.testing.expectEqualStrings(asset_body, asset_readback);

    const run_response = try handleFramedRequest(std.testing.allocator, "REQ 39 PKGRUN demo", 512, 256, 512);
    defer std.testing.allocator.free(run_response);
    try std.testing.expect(std.mem.startsWith(u8, run_response, "RESP 39 "));
    try std.testing.expect(std.mem.indexOf(u8, run_response, "pkg-service-ok\n") != null);

    const display = display_output.statePtr();
    try std.testing.expectEqual(@as(u16, 1280), display.current_width);
    try std.testing.expectEqual(@as(u16, 720), display.current_height);

    const readback = try filesystem.readFileAlloc(std.testing.allocator, "/pkg/out/result.txt", 64);
    defer std.testing.allocator.free(readback);
    try std.testing.expectEqualStrings("pkg-service-data", readback);

    const package_dir_response = try handleFramedRequest(std.testing.allocator, "REQ 40 LIST /packages/demo", 512, 256, 512);
    defer std.testing.allocator.free(package_dir_response);
    const package_dir_listing = try filesystem.listDirectoryAlloc(std.testing.allocator, "/packages/demo", 128);
    defer std.testing.allocator.free(package_dir_listing);
    const expected_package_dir_response = try std.fmt.allocPrint(std.testing.allocator, "RESP 40 {d}\n{s}", .{ package_dir_listing.len, package_dir_listing });
    defer std.testing.allocator.free(expected_package_dir_response);
    try std.testing.expectEqualStrings(expected_package_dir_response, package_dir_response);
}

test "baremetal tool service verifies package integrity and reports tampering" {
    resetPersistentStateForTest();

    try package_store.installScriptPackage("demo", "echo verify-demo", 1);
    try package_store.installPackageAsset("demo", "config/app.json", "{\"mode\":\"verify\"}", 2);

    const verify_ok_response = try handleFramedRequest(std.testing.allocator, "REQ 80 PKGVERIFY demo", 512, 256, 512);
    defer std.testing.allocator.free(verify_ok_response);
    try std.testing.expect(std.mem.startsWith(u8, verify_ok_response, "RESP 80 "));
    try std.testing.expect(std.mem.indexOf(u8, verify_ok_response, "status=ok") != null);
    try std.testing.expect(std.mem.indexOf(u8, verify_ok_response, "asset_tree_checksum=") != null);

    try filesystem.writeFile("/packages/demo/bin/main.oc", "echo verify-dam0", 3);

    const verify_bad_response = try handleFramedRequest(std.testing.allocator, "REQ 81 PKGVERIFY demo", 512, 256, 512);
    defer std.testing.allocator.free(verify_bad_response);
    try std.testing.expect(std.mem.startsWith(u8, verify_bad_response, "RESP 81 "));
    try std.testing.expect(std.mem.indexOf(u8, verify_bad_response, "status=mismatch") != null);
    try std.testing.expect(std.mem.indexOf(u8, verify_bad_response, "field=script_checksum") != null);
}

test "baremetal tool service manages persisted package releases" {
    resetPersistentStateForTest();

    const script = "mkdir /pkg/out\nwrite-file /pkg/out/result.txt release-original\necho release-original";
    const install_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 90 PKG demo {d}\n{s}", .{ script.len, script });
    defer std.testing.allocator.free(install_request);
    const install_response = try handleFramedRequest(std.testing.allocator, install_request, 512, 256, 512);
    defer std.testing.allocator.free(install_response);
    try std.testing.expect(std.mem.indexOf(u8, install_response, "INSTALLED demo -> /packages/demo/bin/main.oc\n") != null);

    const asset_body = "{\"mode\":\"release-original\"}";
    const asset_put_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 91 PKGPUT demo config/app.json {d}\n{s}", .{ asset_body.len, asset_body });
    defer std.testing.allocator.free(asset_put_request);
    const asset_put_response = try handleFramedRequest(std.testing.allocator, asset_put_request, 512, 256, 512);
    defer std.testing.allocator.free(asset_put_response);
    try std.testing.expectEqualStrings("RESP 91 52\nASSET demo -> /packages/demo/assets/config/app.json\n", asset_put_response);

    const save_response = try handleFramedRequest(std.testing.allocator, "REQ 92 PKGRELEASESAVE demo r1", 512, 256, 512);
    defer std.testing.allocator.free(save_response);
    try std.testing.expectEqualStrings("RESP 92 23\nPKGRELEASESAVE demo r1\n", save_response);

    const mutated_script = "mkdir /pkg/out\nwrite-file /pkg/out/result.txt release-mutated\necho release-mutated";
    const mutate_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 93 PKG demo {d}\n{s}", .{ mutated_script.len, mutated_script });
    defer std.testing.allocator.free(mutate_request);
    const mutate_response = try handleFramedRequest(std.testing.allocator, mutate_request, 512, 256, 512);
    defer std.testing.allocator.free(mutate_response);
    try std.testing.expect(std.mem.indexOf(u8, mutate_response, "INSTALLED demo -> /packages/demo/bin/main.oc\n") != null);

    const mutated_asset_body = "{\"mode\":\"release-mutated\"}";
    const mutated_asset_put_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 94 PKGPUT demo config/app.json {d}\n{s}", .{ mutated_asset_body.len, mutated_asset_body });
    defer std.testing.allocator.free(mutated_asset_put_request);
    const mutated_asset_put_response = try handleFramedRequest(std.testing.allocator, mutated_asset_put_request, 512, 256, 512);
    defer std.testing.allocator.free(mutated_asset_put_response);
    try std.testing.expectEqualStrings("RESP 94 52\nASSET demo -> /packages/demo/assets/config/app.json\n", mutated_asset_put_response);

    const save_second_response = try handleFramedRequest(std.testing.allocator, "REQ 95 PKGRELEASESAVE demo r2", 512, 256, 512);
    defer std.testing.allocator.free(save_second_response);
    try std.testing.expectEqualStrings("RESP 95 23\nPKGRELEASESAVE demo r2\n", save_second_response);

    const release_info_response = try handleFramedRequest(std.testing.allocator, "REQ 96 PKGRELEASEINFO demo r2", 512, 256, 512);
    defer std.testing.allocator.free(release_info_response);
    try std.testing.expect(std.mem.startsWith(u8, release_info_response, "RESP 96 "));
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "release=r2") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "saved_seq=2") != null);

    const run_mutated_response = try handleFramedRequest(std.testing.allocator, "REQ 97 PKGRUN demo", 512, 256, 512);
    defer std.testing.allocator.free(run_mutated_response);
    try std.testing.expect(std.mem.startsWith(u8, run_mutated_response, "RESP 97 "));
    try std.testing.expect(std.mem.indexOf(u8, run_mutated_response, "release-mutated\n") != null);

    const release_list_response = try handleFramedRequest(std.testing.allocator, "REQ 98 PKGRELEASELIST demo", 512, 256, 512);
    defer std.testing.allocator.free(release_list_response);
    try std.testing.expectEqualStrings("RESP 98 6\nr1\nr2\n", release_list_response);

    const activate_response = try handleFramedRequest(std.testing.allocator, "REQ 99 PKGRELEASEACTIVATE demo r1", 512, 256, 512);
    defer std.testing.allocator.free(activate_response);
    try std.testing.expectEqualStrings("RESP 99 27\nPKGRELEASEACTIVATE demo r1\n", activate_response);

    const run_restored_response = try handleFramedRequest(std.testing.allocator, "REQ 100 PKGRUN demo", 512, 256, 512);
    defer std.testing.allocator.free(run_restored_response);
    try std.testing.expect(std.mem.startsWith(u8, run_restored_response, "RESP 100 "));
    try std.testing.expect(std.mem.indexOf(u8, run_restored_response, "release-original\n") != null);

    const asset_get_response = try handleFramedRequest(std.testing.allocator, "REQ 101 PKGGET demo config/app.json", 512, 256, 512);
    defer std.testing.allocator.free(asset_get_response);
    const expected_asset_get_response = try std.fmt.allocPrint(std.testing.allocator, "RESP 101 {d}\n{s}", .{ asset_body.len, asset_body });
    defer std.testing.allocator.free(expected_asset_get_response);
    try std.testing.expectEqualStrings(expected_asset_get_response, asset_get_response);

    const save_third_response = try handleFramedRequest(std.testing.allocator, "REQ 102 PKGRELEASESAVE demo r3", 512, 256, 512);
    defer std.testing.allocator.free(save_third_response);
    try std.testing.expectEqualStrings("RESP 102 23\nPKGRELEASESAVE demo r3\n", save_third_response);

    const delete_response = try handleFramedRequest(std.testing.allocator, "REQ 103 PKGRELEASEDELETE demo r2", 512, 256, 512);
    defer std.testing.allocator.free(delete_response);
    try std.testing.expectEqualStrings("RESP 103 25\nPKGRELEASEDELETE demo r2\n", delete_response);

    const list_after_delete = try handleFramedRequest(std.testing.allocator, "REQ 104 PKGRELEASELIST demo", 512, 256, 512);
    defer std.testing.allocator.free(list_after_delete);
    try std.testing.expectEqualStrings("RESP 104 6\nr1\nr3\n", list_after_delete);

    const prune_response = try handleFramedRequest(std.testing.allocator, "REQ 105 PKGRELEASEPRUNE demo 1", 512, 256, 512);
    defer std.testing.allocator.free(prune_response);
    try std.testing.expectEqualStrings("RESP 105 45\nPKGRELEASEPRUNE demo keep=1 deleted=1 kept=1\n", prune_response);

    const list_after_prune = try handleFramedRequest(std.testing.allocator, "REQ 106 PKGRELEASELIST demo", 512, 256, 512);
    defer std.testing.allocator.free(list_after_prune);
    try std.testing.expectEqualStrings("RESP 106 3\nr3\n", list_after_prune);

    const channel_set_response = try handleFramedRequest(std.testing.allocator, "REQ 107 PKGCHANNELSET demo stable r3", 512, 256, 512);
    defer std.testing.allocator.free(channel_set_response);
    try std.testing.expectEqualStrings("RESP 107 29\nPKGCHANNELSET demo stable r3\n", channel_set_response);

    const channel_info_response = try handleFramedRequest(std.testing.allocator, "REQ 108 PKGCHANNELINFO demo stable", 512, 256, 512);
    defer std.testing.allocator.free(channel_info_response);
    try std.testing.expect(std.mem.startsWith(u8, channel_info_response, "RESP 108 "));
    try std.testing.expect(std.mem.indexOf(u8, channel_info_response, "channel=stable") != null);
    try std.testing.expect(std.mem.indexOf(u8, channel_info_response, "release=r3") != null);

    const channel_list_response = try handleFramedRequest(std.testing.allocator, "REQ 109 PKGCHANNELLIST demo", 512, 256, 512);
    defer std.testing.allocator.free(channel_list_response);
    try std.testing.expectEqualStrings("RESP 109 7\nstable\n", channel_list_response);

    const channel_mutate_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 110 PKG demo {d}\n{s}", .{ mutated_script.len, mutated_script });
    defer std.testing.allocator.free(channel_mutate_request);
    const channel_mutate_response = try handleFramedRequest(std.testing.allocator, channel_mutate_request, 512, 256, 512);
    defer std.testing.allocator.free(channel_mutate_response);
    try std.testing.expect(std.mem.indexOf(u8, channel_mutate_response, "INSTALLED demo -> /packages/demo/bin/main.oc\n") != null);

    const channel_activate_response = try handleFramedRequest(std.testing.allocator, "REQ 111 PKGCHANNELACTIVATE demo stable", 512, 256, 512);
    defer std.testing.allocator.free(channel_activate_response);
    try std.testing.expectEqualStrings("RESP 111 31\nPKGCHANNELACTIVATE demo stable\n", channel_activate_response);

    const channel_restored_run_response = try handleFramedRequest(std.testing.allocator, "REQ 112 PKGRUN demo", 512, 256, 512);
    defer std.testing.allocator.free(channel_restored_run_response);
    try std.testing.expect(std.mem.startsWith(u8, channel_restored_run_response, "RESP 112 "));
    try std.testing.expect(std.mem.indexOf(u8, channel_restored_run_response, "release-original\n") != null);

    const script_readback = try filesystem.readFileAlloc(std.testing.allocator, "/packages/demo/bin/main.oc", 128);
    defer std.testing.allocator.free(script_readback);
    try std.testing.expectEqualStrings(script, script_readback);

    const asset_readback = try filesystem.readFileAlloc(std.testing.allocator, "/packages/demo/assets/config/app.json", 64);
    defer std.testing.allocator.free(asset_readback);
    try std.testing.expectEqualStrings(asset_body, asset_readback);
}

test "baremetal tool service reports display info and supported modes" {
    resetPersistentStateForTest();

    const info_response = try handleFramedRequest(std.testing.allocator, "REQ 61 DISPLAYINFO", 512, 256, 512);
    defer std.testing.allocator.free(info_response);
    try std.testing.expect(std.mem.startsWith(u8, info_response, "RESP 61 "));
    try std.testing.expect(std.mem.indexOf(u8, info_response, "backend=bga") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "controller=bochs-bga") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "current=640x400") != null);

    const outputs_response = try handleFramedRequest(std.testing.allocator, "REQ 62 DISPLAYOUTPUTS", 512, 256, 512);
    defer std.testing.allocator.free(outputs_response);
    try std.testing.expect(std.mem.startsWith(u8, outputs_response, "RESP 62 "));
    try std.testing.expect(std.mem.indexOf(u8, outputs_response, "output 0 scanout=0 connector=virtual interface=none connected=0 current=640x400 preferred=640x400") != null);

    const output_response = try handleFramedRequest(std.testing.allocator, "REQ 63 DISPLAYOUTPUT 0", 512, 256, 512);
    defer std.testing.allocator.free(output_response);
    try std.testing.expect(std.mem.startsWith(u8, output_response, "RESP 63 "));
    try std.testing.expect(std.mem.indexOf(u8, output_response, "index=0 scanout=0 connector=virtual interface=none connected=0 current=640x400 preferred=640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_response, "mode_count=1") != null);

    const output_modes_response = try handleFramedRequest(std.testing.allocator, "REQ 163 DISPLAYOUTPUTMODES 0", 512, 256, 512);
    defer std.testing.allocator.free(output_modes_response);
    try std.testing.expect(std.mem.startsWith(u8, output_modes_response, "RESP 163 "));
    try std.testing.expect(std.mem.indexOf(u8, output_modes_response, "mode 0 640x400 refresh=0") != null);

    const modes_response = try handleFramedRequest(std.testing.allocator, "REQ 64 DISPLAYMODES", 512, 256, 512);
    defer std.testing.allocator.free(modes_response);
    try std.testing.expect(std.mem.startsWith(u8, modes_response, "RESP 64 "));
    try std.testing.expect(std.mem.indexOf(u8, modes_response, "mode 0 640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, modes_response, "mode 4 1280x1024") != null);

    const set_response = try handleFramedRequest(std.testing.allocator, "REQ 65 DISPLAYSET 800 600", 512, 256, 512);
    defer std.testing.allocator.free(set_response);
    try std.testing.expectEqualStrings("RESP 65 16\nDISPLAY 800x600\n", set_response);

    const updated_info = try handleFramedRequest(std.testing.allocator, "REQ 66 DISPLAYINFO", 512, 256, 512);
    defer std.testing.allocator.free(updated_info);
    try std.testing.expect(std.mem.indexOf(u8, updated_info, "current=800x600") != null);
}

test "baremetal tool service activates requested display connector" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
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

    const activate_response = try handleFramedRequest(std.testing.allocator, "REQ 67 DISPLAYACTIVATE displayport", 512, 256, 512);
    defer std.testing.allocator.free(activate_response);
    try std.testing.expectEqualStrings("RESP 67 56\nDISPLAYACTIVATE displayport scanout=1 current=1920x1080\n", activate_response);

    const activate_preferred_response = try handleFramedRequest(std.testing.allocator, "REQ 167 DISPLAYACTIVATEPREFERRED displayport", 512, 256, 512);
    defer std.testing.allocator.free(activate_preferred_response);
    try std.testing.expect(std.mem.startsWith(u8, activate_preferred_response, "RESP 167 "));
    try std.testing.expect(std.mem.indexOf(u8, activate_preferred_response, "DISPLAYACTIVATEPREFERRED displayport scanout=1 current=1920x1080 preferred=1920x1080\n") != null);

    const activate_interface_response = try handleFramedRequest(std.testing.allocator, "REQ 267 DISPLAYACTIVATEINTERFACE displayport", 512, 256, 512);
    defer std.testing.allocator.free(activate_interface_response);
    try std.testing.expect(std.mem.startsWith(u8, activate_interface_response, "RESP 267 "));
    try std.testing.expect(std.mem.indexOf(u8, activate_interface_response, "DISPLAYACTIVATEINTERFACE displayport connector=displayport scanout=1 current=1920x1080\n") != null);

    const activate_interface_preferred_response = try handleFramedRequest(std.testing.allocator, "REQ 268 DISPLAYACTIVATEINTERFACEPREFERRED displayport", 512, 256, 512);
    defer std.testing.allocator.free(activate_interface_preferred_response);
    try std.testing.expect(std.mem.startsWith(u8, activate_interface_preferred_response, "RESP 268 "));
    try std.testing.expect(std.mem.indexOf(u8, activate_interface_preferred_response, "DISPLAYACTIVATEINTERFACEPREFERRED displayport connector=displayport scanout=1 current=1920x1080 preferred=1920x1080\n") != null);

    const activate_interface_mismatch_response = try handleFramedRequest(std.testing.allocator, "REQ 269 DISPLAYACTIVATEINTERFACE hdmi-b", 512, 256, 512);
    defer std.testing.allocator.free(activate_interface_mismatch_response);
    try std.testing.expect(std.mem.startsWith(u8, activate_interface_mismatch_response, "RESP 269 "));
    try std.testing.expect(std.mem.indexOf(u8, activate_interface_mismatch_response, "ERR DISPLAYACTIVATEINTERFACE: DisplayInterfaceMismatch\n") != null);

    const output_modes_response = try handleFramedRequest(std.testing.allocator, "REQ 168 DISPLAYOUTPUTMODES 1", 512, 256, 512);
    defer std.testing.allocator.free(output_modes_response);
    try std.testing.expect(std.mem.startsWith(u8, output_modes_response, "RESP 168 "));
    try std.testing.expect(std.mem.indexOf(u8, output_modes_response, "mode 1 1024x768 refresh=60") != null);

    const interface_modes_response = try handleFramedRequest(std.testing.allocator, "REQ 283 DISPLAYINTERFACEMODES displayport", 512, 256, 512);
    defer std.testing.allocator.free(interface_modes_response);
    try std.testing.expect(std.mem.startsWith(u8, interface_modes_response, "RESP 283 "));
    try std.testing.expect(std.mem.indexOf(u8, interface_modes_response, "mode 1 1024x768 refresh=60") != null);

    const mismatch_response = try handleFramedRequest(std.testing.allocator, "REQ 68 DISPLAYACTIVATE embedded-displayport", 512, 256, 512);
    defer std.testing.allocator.free(mismatch_response);
    try std.testing.expectEqualStrings("RESP 68 46\nERR DISPLAYACTIVATE: DisplayConnectorMismatch\n", mismatch_response);

    const activate_output_response = try handleFramedRequest(std.testing.allocator, "REQ 69 DISPLAYACTIVATEOUTPUT 1", 512, 256, 512);
    defer std.testing.allocator.free(activate_output_response);
    try std.testing.expectEqualStrings("RESP 69 74\nDISPLAYACTIVATEOUTPUT 1 connector=displayport scanout=1 current=1920x1080\n", activate_output_response);

    const activate_output_preferred_response = try handleFramedRequest(std.testing.allocator, "REQ 169 DISPLAYACTIVATEOUTPUTPREFERRED 1", 512, 256, 512);
    defer std.testing.allocator.free(activate_output_preferred_response);
    try std.testing.expect(std.mem.startsWith(u8, activate_output_preferred_response, "RESP 169 "));
    try std.testing.expect(std.mem.indexOf(u8, activate_output_preferred_response, "DISPLAYACTIVATEOUTPUTPREFERRED 1 connector=displayport scanout=1 current=1920x1080 preferred=1920x1080\n") != null);

    const activate_output_mode_response = try handleFramedRequest(std.testing.allocator, "REQ 170 DISPLAYOUTPUTACTIVATEMODE 1 1", 512, 256, 512);
    defer std.testing.allocator.free(activate_output_mode_response);
    try std.testing.expectEqualStrings("RESP 170 71\nDISPLAYOUTPUTACTIVATEMODE 1 1 1024x768 connector=displayport scanout=1\n", activate_output_mode_response);

    const set_interface_mode_response = try handleFramedRequest(std.testing.allocator, "REQ 284 DISPLAYINTERFACESET displayport 1024 768", 512, 256, 512);
    defer std.testing.allocator.free(set_interface_mode_response);
    try std.testing.expectEqualStrings("RESP 284 73\nDISPLAYINTERFACESET displayport 1024x768 connector=displayport scanout=1\n", set_interface_mode_response);

    const activate_interface_mode_response = try handleFramedRequest(std.testing.allocator, "REQ 285 DISPLAYINTERFACEACTIVATEMODE displayport 0", 512, 256, 512);
    defer std.testing.allocator.free(activate_interface_mode_response);
    try std.testing.expectEqualStrings("RESP 285 85\nDISPLAYINTERFACEACTIVATEMODE displayport 0 1920x1080 connector=displayport scanout=1\n", activate_interface_mode_response);

    const missing_output_response = try handleFramedRequest(std.testing.allocator, "REQ 70 DISPLAYACTIVATEOUTPUT 2", 512, 256, 512);
    defer std.testing.allocator.free(missing_output_response);
    try std.testing.expectEqualStrings("RESP 70 49\nERR DISPLAYACTIVATEOUTPUT: DisplayOutputNotFound\n", missing_output_response);

    const set_output_response = try handleFramedRequest(std.testing.allocator, "REQ 71 DISPLAYOUTPUTSET 1 1024 768", 512, 256, 512);
    defer std.testing.allocator.free(set_output_response);
    try std.testing.expectEqualStrings("RESP 71 60\nDISPLAYOUTPUTSET 1 1024x768 connector=displayport scanout=1\n", set_output_response);

    const unsupported_output_set_response = try handleFramedRequest(std.testing.allocator, "REQ 72 DISPLAYOUTPUTSET 1 2560 1440", 512, 256, 512);
    defer std.testing.allocator.free(unsupported_output_set_response);
    try std.testing.expectEqualStrings("RESP 72 51\nERR DISPLAYOUTPUTSET: DisplayOutputUnsupportedMode\n", unsupported_output_set_response);

    const missing_output_set_response = try handleFramedRequest(std.testing.allocator, "REQ 73 DISPLAYOUTPUTSET 2 800 600", 512, 256, 512);
    defer std.testing.allocator.free(missing_output_set_response);
    try std.testing.expectEqualStrings("RESP 73 44\nERR DISPLAYOUTPUTSET: DisplayOutputNotFound\n", missing_output_set_response);

    const missing_output_modes_response = try handleFramedRequest(std.testing.allocator, "REQ 74 DISPLAYOUTPUTMODES 2", 512, 256, 512);
    defer std.testing.allocator.free(missing_output_modes_response);
    try std.testing.expectEqualStrings("RESP 74 33\nERR DISPLAYOUTPUTMODES: NotFound\n", missing_output_modes_response);

    const missing_interface_modes_response = try handleFramedRequest(std.testing.allocator, "REQ 286 DISPLAYINTERFACEMODES hdmi-b", 512, 256, 512);
    defer std.testing.allocator.free(missing_interface_modes_response);
    try std.testing.expectEqualStrings("RESP 286 36\nERR DISPLAYINTERFACEMODES: NotFound\n", missing_interface_modes_response);

    const invalid_output_mode_response = try handleFramedRequest(std.testing.allocator, "REQ 75 DISPLAYOUTPUTACTIVATEMODE 1 7", 512, 256, 512);
    defer std.testing.allocator.free(invalid_output_mode_response);
    try std.testing.expectEqualStrings("RESP 75 60\nERR DISPLAYOUTPUTACTIVATEMODE: DisplayOutputUnsupportedMode\n", invalid_output_mode_response);

    const invalid_interface_mode_response = try handleFramedRequest(std.testing.allocator, "REQ 287 DISPLAYINTERFACEACTIVATEMODE displayport 7", 512, 256, 512);
    defer std.testing.allocator.free(invalid_interface_mode_response);
    try std.testing.expectEqualStrings("RESP 287 63\nERR DISPLAYINTERFACEACTIVATEMODE: DisplayOutputUnsupportedMode\n", invalid_interface_mode_response);

    const save_profile_response = try handleFramedRequest(std.testing.allocator, "REQ 74 DISPLAYPROFILESAVE golden", 512, 256, 512);
    defer std.testing.allocator.free(save_profile_response);
    try std.testing.expectEqualStrings("RESP 74 74\nDISPLAYPROFILESAVE golden output=1 current=1024x768 connector=displayport\n", save_profile_response);

    const list_profile_response = try handleFramedRequest(std.testing.allocator, "REQ 75 DISPLAYPROFILELIST", 512, 256, 512);
    defer std.testing.allocator.free(list_profile_response);
    try std.testing.expectEqualStrings("RESP 75 7\ngolden\n", list_profile_response);

    const info_profile_response = try handleFramedRequest(std.testing.allocator, "REQ 76 DISPLAYPROFILEINFO golden", 512, 256, 512);
    defer std.testing.allocator.free(info_profile_response);
    try std.testing.expect(std.mem.indexOf(u8, info_profile_response, "name=golden") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_profile_response, "output_index=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_profile_response, "width=1024") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_profile_response, "height=768") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_profile_response, "selected=0") != null);

    const mutate_profile_response = try handleFramedRequest(std.testing.allocator, "REQ 77 DISPLAYOUTPUTSET 1 800 600", 512, 256, 512);
    defer std.testing.allocator.free(mutate_profile_response);
    try std.testing.expectEqualStrings("RESP 77 59\nDISPLAYOUTPUTSET 1 800x600 connector=displayport scanout=1\n", mutate_profile_response);

    const apply_profile_response = try handleFramedRequest(std.testing.allocator, "REQ 78 DISPLAYPROFILEAPPLY golden", 512, 256, 512);
    defer std.testing.allocator.free(apply_profile_response);
    try std.testing.expectEqualStrings("RESP 78 75\nDISPLAYPROFILEAPPLY golden output=1 current=1024x768 connector=displayport\n", apply_profile_response);

    const active_profile_response = try handleFramedRequest(std.testing.allocator, "REQ 79 DISPLAYPROFILEACTIVE", 512, 256, 512);
    defer std.testing.allocator.free(active_profile_response);
    try std.testing.expect(std.mem.indexOf(u8, active_profile_response, "selected=1") != null);

    const delete_profile_response = try handleFramedRequest(std.testing.allocator, "REQ 80 DISPLAYPROFILEDELETE golden", 512, 256, 512);
    defer std.testing.allocator.free(delete_profile_response);
    try std.testing.expectEqualStrings("RESP 80 28\nDISPLAYPROFILEDELETE golden\n", delete_profile_response);
}

test "baremetal tool service reports detailed display sink metadata" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
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

    const detail_response = try handleFramedRequest(std.testing.allocator, "REQ 500 DISPLAYOUTPUTDETAIL 0", 512, 256, 512);
    defer std.testing.allocator.free(detail_response);
    try std.testing.expect(std.mem.startsWith(u8, detail_response, "RESP 500 "));
    try std.testing.expect(std.mem.indexOf(u8, detail_response, "connector=displayport interface=displayport declared_interface=displayport") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_response, "name=QEMU-EDID manufacturer=QEM") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_response, "week=1 year=2024 edid=1.4 extensions=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail_response, "physical=300x190mm audio=1 hdmi_vendor=0 displayid=1") != null);

    const capability_response = try handleFramedRequest(std.testing.allocator, "REQ 503 DISPLAYOUTPUTCAPABILITIES 0", 512, 256, 512);
    defer std.testing.allocator.free(capability_response);
    try std.testing.expect(std.mem.startsWith(u8, capability_response, "RESP 503 "));
    try std.testing.expect(std.mem.indexOf(u8, capability_response, "connector=displayport interface=displayport declared_interface=displayport") != null);
    try std.testing.expect(std.mem.indexOf(u8, capability_response, "digital=1 preferred=1 cea=0 audio=1 hdmi_vendor=0 displayid=1 underscan=0 ycbcr444=0 ycbcr422=0") != null);

    const interface_response = try handleFramedRequest(std.testing.allocator, "REQ 501 DISPLAYINTERFACEDETAIL displayport", 512, 256, 512);
    defer std.testing.allocator.free(interface_response);
    try std.testing.expect(std.mem.startsWith(u8, interface_response, "RESP 501 "));
    try std.testing.expect(std.mem.indexOf(u8, interface_response, "name=QEMU-EDID manufacturer=QEM") != null);

    const interface_capability_response = try handleFramedRequest(std.testing.allocator, "REQ 504 DISPLAYINTERFACECAPABILITIES displayport", 512, 256, 512);
    defer std.testing.allocator.free(interface_capability_response);
    try std.testing.expect(std.mem.startsWith(u8, interface_capability_response, "RESP 504 "));
    try std.testing.expect(std.mem.indexOf(u8, interface_capability_response, "digital=1 preferred=1 cea=0 audio=1 hdmi_vendor=0 displayid=1 underscan=0 ycbcr444=0 ycbcr422=0") != null);

    const missing_response = try handleFramedRequest(std.testing.allocator, "REQ 502 DISPLAYINTERFACEDETAIL hdmi-a", 512, 256, 512);
    defer std.testing.allocator.free(missing_response);
    try std.testing.expect(std.mem.startsWith(u8, missing_response, "RESP 502 "));
    try std.testing.expect(std.mem.indexOf(u8, missing_response, "ERR DISPLAYINTERFACEDETAIL: NotFound\n") != null);

    const missing_capability_response = try handleFramedRequest(std.testing.allocator, "REQ 505 DISPLAYINTERFACECAPABILITIES hdmi-a", 512, 256, 512);
    defer std.testing.allocator.free(missing_capability_response);
    try std.testing.expect(std.mem.startsWith(u8, missing_capability_response, "RESP 505 "));
    try std.testing.expect(std.mem.indexOf(u8, missing_capability_response, "ERR DISPLAYINTERFACECAPABILITIES: NotFound\n") != null);
}

test "baremetal tool service rotates queries and deletes trust bundles" {
    resetPersistentStateForTest();

    const install_response = try handleFramedRequest(std.testing.allocator, "REQ 41 TRUSTPUT fs55-root 9\nroot-cert", 512, 256, 512);
    defer std.testing.allocator.free(install_response);
    try std.testing.expect(std.mem.startsWith(u8, install_response, "RESP 41 "));
    try std.testing.expect(std.mem.indexOf(u8, install_response, "TRUSTED fs55-root -> /runtime/trust/bundles/fs55-root.der\n") != null);

    const install_backup_response = try handleFramedRequest(std.testing.allocator, "REQ 42 TRUSTPUT fs55-backup 11\nbackup-cert", 512, 256, 512);
    defer std.testing.allocator.free(install_backup_response);
    try std.testing.expect(std.mem.startsWith(u8, install_backup_response, "RESP 42 "));
    try std.testing.expect(std.mem.indexOf(u8, install_backup_response, "TRUSTED fs55-backup -> /runtime/trust/bundles/fs55-backup.der\n") != null);

    const list_response = try handleFramedRequest(std.testing.allocator, "REQ 43 TRUSTLIST", 512, 256, 512);
    defer std.testing.allocator.free(list_response);
    try std.testing.expectEqualStrings("RESP 43 22\nfs55-root\nfs55-backup\n", list_response);

    const info_response = try handleFramedRequest(std.testing.allocator, "REQ 44 TRUSTINFO fs55-root", 512, 256, 512);
    defer std.testing.allocator.free(info_response);
    try std.testing.expect(std.mem.startsWith(u8, info_response, "RESP 44 "));
    try std.testing.expect(std.mem.indexOf(u8, info_response, "name=fs55-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "selected=0") != null);

    const select_response = try handleFramedRequest(std.testing.allocator, "REQ 45 TRUSTSELECT fs55-root", 512, 256, 512);
    defer std.testing.allocator.free(select_response);
    try std.testing.expectEqualStrings("RESP 45 19\nSELECTED fs55-root\n", select_response);

    const active_response = try handleFramedRequest(std.testing.allocator, "REQ 46 TRUSTACTIVE", 512, 256, 512);
    defer std.testing.allocator.free(active_response);
    try std.testing.expect(std.mem.startsWith(u8, active_response, "RESP 46 "));
    try std.testing.expect(std.mem.indexOf(u8, active_response, "name=fs55-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, active_response, "selected=1") != null);

    const rotate_response = try handleFramedRequest(std.testing.allocator, "REQ 47 TRUSTSELECT fs55-backup", 512, 256, 512);
    defer std.testing.allocator.free(rotate_response);
    try std.testing.expectEqualStrings("RESP 47 21\nSELECTED fs55-backup\n", rotate_response);

    const delete_response = try handleFramedRequest(std.testing.allocator, "REQ 48 TRUSTDELETE fs55-root", 512, 256, 512);
    defer std.testing.allocator.free(delete_response);
    try std.testing.expectEqualStrings("RESP 48 18\nDELETED fs55-root\n", delete_response);

    const remaining_list_response = try handleFramedRequest(std.testing.allocator, "REQ 49 TRUSTLIST", 512, 256, 512);
    defer std.testing.allocator.free(remaining_list_response);
    try std.testing.expectEqualStrings("RESP 49 12\nfs55-backup\n", remaining_list_response);

    const selected_info_response = try handleFramedRequest(std.testing.allocator, "REQ 50 TRUSTACTIVE", 512, 256, 512);
    defer std.testing.allocator.free(selected_info_response);
    try std.testing.expect(std.mem.indexOf(u8, selected_info_response, "name=fs55-backup") != null);
    try std.testing.expect(std.mem.indexOf(u8, selected_info_response, "selected=1") != null);
}

test "baremetal tool service configures and runs app lifecycle requests" {
    resetPersistentStateForTest();

    try trust_store.installBundle("fs55-root", "root-cert", 0);
    try package_store.installScriptPackage("demo", "mkdir /pkg/out\nwrite-file /pkg/out/app.txt app-service-data\necho app-service-ok", 1);

    const app_list_response = try handleFramedRequest(std.testing.allocator, "REQ 51 APPLIST", 512, 256, 512);
    defer std.testing.allocator.free(app_list_response);
    try std.testing.expectEqualStrings("RESP 51 5\ndemo\n", app_list_response);

    const app_connector_response = try handleFramedRequest(std.testing.allocator, "REQ 52 APPCONNECTOR demo virtual", 512, 256, 512);
    defer std.testing.allocator.free(app_connector_response);
    try std.testing.expectEqualStrings("RESP 52 26\nAPPCONNECTOR demo virtual\n", app_connector_response);

    const app_trust_response = try handleFramedRequest(std.testing.allocator, "REQ 53 APPTRUST demo fs55-root", 512, 256, 512);
    defer std.testing.allocator.free(app_trust_response);
    try std.testing.expectEqualStrings("RESP 53 24\nAPPTRUST demo fs55-root\n", app_trust_response);

    const app_info_response = try handleFramedRequest(std.testing.allocator, "REQ 54 APPINFO demo", 512, 256, 512);
    defer std.testing.allocator.free(app_info_response);
    try std.testing.expect(std.mem.startsWith(u8, app_info_response, "RESP 54 "));
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "trust_bundle=fs55-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "state_path=/runtime/apps/demo/last_run.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "stdout_path=/runtime/apps/demo/stdout.log") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "stderr_path=/runtime/apps/demo/stderr.log") != null);

    const app_run_response = try handleFramedRequest(std.testing.allocator, "REQ 55 APPRUN demo", 512, 256, 512);
    defer std.testing.allocator.free(app_run_response);
    try std.testing.expect(std.mem.startsWith(u8, app_run_response, "RESP 55 "));
    try std.testing.expect(std.mem.indexOf(u8, app_run_response, "app-service-ok\n") != null);

    const app_state_response = try handleFramedRequest(std.testing.allocator, "REQ 56 APPSTATE demo", 512, 256, 512);
    defer std.testing.allocator.free(app_state_response);
    try std.testing.expect(std.mem.startsWith(u8, app_state_response, "RESP 56 "));
    try std.testing.expect(std.mem.indexOf(u8, app_state_response, "exit_code=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_state_response, "requested_connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_state_response, "actual_connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_state_response, "trust_bundle=fs55-root") != null);

    const app_history_response = try handleFramedRequest(std.testing.allocator, "REQ 57 APPHISTORY demo", 512, 256, 512);
    defer std.testing.allocator.free(app_history_response);
    try std.testing.expect(std.mem.startsWith(u8, app_history_response, "RESP 57 "));
    try std.testing.expect(std.mem.indexOf(u8, app_history_response, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_history_response, "trust_bundle=fs55-root") != null);

    const app_stdout_response = try handleFramedRequest(std.testing.allocator, "REQ 58 APPSTDOUT demo", 512, 256, 512);
    defer std.testing.allocator.free(app_stdout_response);
    try std.testing.expectEqualStrings("RESP 58 67\ncreated /pkg/out\nwrote 16 bytes to /pkg/out/app.txt\napp-service-ok\n", app_stdout_response);

    const app_stderr_response = try handleFramedRequest(std.testing.allocator, "REQ 59 APPSTDERR demo", 512, 256, 512);
    defer std.testing.allocator.free(app_stderr_response);
    try std.testing.expectEqualStrings("RESP 59 0\n", app_stderr_response);
}

test "baremetal tool service manages persisted app plans" {
    resetPersistentStateForTest();

    try trust_store.installBundle("fs55-root", "root-cert", 1);
    try package_store.installScriptPackage("demo", "echo stable-plan", 2);
    try package_store.configureDisplayMode("demo", 1280, 720, 3);
    try package_store.configureConnectorType("demo", abi.display_connector_virtual, 4);
    try package_store.configureTrustBundle("demo", "fs55-root", 5);
    try package_store.snapshotPackageRelease("demo", "stable", 6);
    try package_store.installScriptPackage("demo", "echo drift-plan", 7);

    const save_response = try handleFramedRequest(std.testing.allocator, "REQ 160 APPPLANSAVE demo golden stable fs55-root virtual 1280 720 1", 512, 256, 512);
    defer std.testing.allocator.free(save_response);
    try std.testing.expectEqualStrings("RESP 160 24\nAPPPLANSAVE demo golden\n", save_response);

    const list_response = try handleFramedRequest(std.testing.allocator, "REQ 161 APPPLANLIST demo", 512, 256, 512);
    defer std.testing.allocator.free(list_response);
    try std.testing.expectEqualStrings("RESP 161 7\ngolden\n", list_response);

    const info_response = try handleFramedRequest(std.testing.allocator, "REQ 162 APPPLANINFO demo golden", 512, 256, 512);
    defer std.testing.allocator.free(info_response);
    try std.testing.expect(std.mem.startsWith(u8, info_response, "RESP 162 "));
    try std.testing.expect(std.mem.indexOf(u8, info_response, "release=stable") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "trust_bundle=fs55-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "autorun=1") != null);

    const apply_response = try handleFramedRequest(std.testing.allocator, "REQ 163 APPPLANAPPLY demo golden", 512, 256, 512);
    defer std.testing.allocator.free(apply_response);
    try std.testing.expectEqualStrings("RESP 163 25\nAPPPLANAPPLY demo golden\n", apply_response);

    const active_response = try handleFramedRequest(std.testing.allocator, "REQ 164 APPPLANACTIVE demo", 512, 256, 512);
    defer std.testing.allocator.free(active_response);
    try std.testing.expect(std.mem.startsWith(u8, active_response, "RESP 164 "));
    try std.testing.expect(std.mem.indexOf(u8, active_response, "active_plan=golden") != null);

    const app_info_response = try handleFramedRequest(std.testing.allocator, "REQ 165 APPINFO demo", 512, 256, 512);
    defer std.testing.allocator.free(app_info_response);
    try std.testing.expect(std.mem.startsWith(u8, app_info_response, "RESP 165 "));
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "display_width=1280") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "display_height=720") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "trust_bundle=fs55-root") != null);

    const autorun_response = try handleFramedRequest(std.testing.allocator, "REQ 166 APPAUTORUNLIST", 512, 256, 512);
    defer std.testing.allocator.free(autorun_response);
    try std.testing.expectEqualStrings("RESP 166 5\ndemo\n", autorun_response);

    const app_run_response = try handleFramedRequest(std.testing.allocator, "REQ 167 APPRUN demo", 512, 256, 512);
    defer std.testing.allocator.free(app_run_response);
    try std.testing.expect(std.mem.startsWith(u8, app_run_response, "RESP 167 "));
    try std.testing.expect(std.mem.indexOf(u8, app_run_response, "stable-plan\n") != null);

    const delete_response = try handleFramedRequest(std.testing.allocator, "REQ 168 APPPLANDELETE demo golden", 512, 256, 512);
    defer std.testing.allocator.free(delete_response);
    try std.testing.expectEqualStrings("RESP 168 26\nAPPPLANDELETE demo golden\n", delete_response);

    const list_after_delete = try handleFramedRequest(std.testing.allocator, "REQ 169 APPPLANLIST demo", 512, 256, 512);
    defer std.testing.allocator.free(list_after_delete);
    try std.testing.expectEqualStrings("RESP 169 0\n", list_after_delete);

    try std.testing.expectError(error.FileNotFound, filesystem.statSummary("/runtime/apps/demo/active_plan.txt"));
}

test "baremetal tool service manages persisted app suites" {
    resetPersistentStateForTest();

    try package_store.installScriptPackage("demo", "echo suite-demo", 1);
    try package_store.installScriptPackage("aux", "echo suite-aux", 2);

    const save_demo_plan = try handleFramedRequest(std.testing.allocator, "REQ 170 APPPLANSAVE demo golden none none virtual 1280 720 1", 512, 256, 512);
    defer std.testing.allocator.free(save_demo_plan);
    try std.testing.expectEqualStrings("RESP 170 24\nAPPPLANSAVE demo golden\n", save_demo_plan);

    const save_aux_plan = try handleFramedRequest(std.testing.allocator, "REQ 171 APPPLANSAVE aux sidecar none none virtual 800 600 0", 512, 256, 512);
    defer std.testing.allocator.free(save_aux_plan);
    try std.testing.expectEqualStrings("RESP 171 24\nAPPPLANSAVE aux sidecar\n", save_aux_plan);

    const save_suite = try handleFramedRequest(std.testing.allocator, "REQ 172 APPSUITESAVE duo demo:golden aux:sidecar", 512, 256, 512);
    defer std.testing.allocator.free(save_suite);
    try std.testing.expectEqualStrings("RESP 172 17\nAPPSUITESAVE duo\n", save_suite);

    const suite_list = try handleFramedRequest(std.testing.allocator, "REQ 173 APPSUITELIST", 512, 256, 512);
    defer std.testing.allocator.free(suite_list);
    try std.testing.expectEqualStrings("RESP 173 4\nduo\n", suite_list);

    const suite_info = try handleFramedRequest(std.testing.allocator, "REQ 174 APPSUITEINFO duo", 512, 256, 512);
    defer std.testing.allocator.free(suite_info);
    try std.testing.expect(std.mem.startsWith(u8, suite_info, "RESP 174 "));
    try std.testing.expect(std.mem.indexOf(u8, suite_info, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info, "entry=demo:golden") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info, "entry=aux:sidecar") != null);

    const apply_suite = try handleFramedRequest(std.testing.allocator, "REQ 175 APPSUITEAPPLY duo", 512, 256, 512);
    defer std.testing.allocator.free(apply_suite);
    try std.testing.expectEqualStrings("RESP 175 18\nAPPSUITEAPPLY duo\n", apply_suite);

    const demo_active = try handleFramedRequest(std.testing.allocator, "REQ 176 APPPLANACTIVE demo", 512, 256, 512);
    defer std.testing.allocator.free(demo_active);
    try std.testing.expect(std.mem.indexOf(u8, demo_active, "active_plan=golden") != null);

    const aux_active = try handleFramedRequest(std.testing.allocator, "REQ 177 APPPLANACTIVE aux", 512, 256, 512);
    defer std.testing.allocator.free(aux_active);
    try std.testing.expect(std.mem.indexOf(u8, aux_active, "active_plan=sidecar") != null);

    const autorun_response = try handleFramedRequest(std.testing.allocator, "REQ 178 APPAUTORUNLIST", 512, 256, 512);
    defer std.testing.allocator.free(autorun_response);
    try std.testing.expectEqualStrings("RESP 178 5\ndemo\n", autorun_response);

    const run_suite = try handleFramedRequest(std.testing.allocator, "REQ 179 APPSUITERUN duo", 512, 256, 512);
    defer std.testing.allocator.free(run_suite);
    try std.testing.expect(std.mem.startsWith(u8, run_suite, "RESP 179 "));
    try std.testing.expect(std.mem.indexOf(u8, run_suite, "suite-demo\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, run_suite, "suite-aux\n") != null);

    const delete_suite = try handleFramedRequest(std.testing.allocator, "REQ 180 APPSUITEDELETE duo", 512, 256, 512);
    defer std.testing.allocator.free(delete_suite);
    try std.testing.expectEqualStrings("RESP 180 19\nAPPSUITEDELETE duo\n", delete_suite);

    const suite_list_after_delete = try handleFramedRequest(std.testing.allocator, "REQ 181 APPSUITELIST", 512, 256, 512);
    defer std.testing.allocator.free(suite_list_after_delete);
    try std.testing.expectEqualStrings("RESP 181 0\n", suite_list_after_delete);
}

test "baremetal tool service manages app suite releases" {
    resetPersistentStateForTest();

    try package_store.installScriptPackage("demo", "echo suite-demo", 1);
    try package_store.installScriptPackage("aux", "echo suite-aux", 2);

    const save_demo_plan = try handleFramedRequest(std.testing.allocator, "REQ 182 APPPLANSAVE demo golden none none virtual 1280 720 1", 512, 256, 512);
    defer std.testing.allocator.free(save_demo_plan);
    try std.testing.expectEqualStrings("RESP 182 24\nAPPPLANSAVE demo golden\n", save_demo_plan);

    const save_demo_canary = try handleFramedRequest(std.testing.allocator, "REQ 183 APPPLANSAVE demo canary none none virtual 640 400 0", 512, 256, 512);
    defer std.testing.allocator.free(save_demo_canary);
    try std.testing.expectEqualStrings("RESP 183 24\nAPPPLANSAVE demo canary\n", save_demo_canary);

    const save_aux_plan = try handleFramedRequest(std.testing.allocator, "REQ 184 APPPLANSAVE aux sidecar none none virtual 800 600 0", 512, 256, 512);
    defer std.testing.allocator.free(save_aux_plan);
    try std.testing.expectEqualStrings("RESP 184 24\nAPPPLANSAVE aux sidecar\n", save_aux_plan);

    const save_suite = try handleFramedRequest(std.testing.allocator, "REQ 185 APPSUITESAVE duo demo:golden aux:sidecar", 512, 256, 512);
    defer std.testing.allocator.free(save_suite);
    try std.testing.expectEqualStrings("RESP 185 17\nAPPSUITESAVE duo\n", save_suite);

    const save_release_golden = try handleFramedRequest(std.testing.allocator, "REQ 186 APPSUITERELEASESAVE duo golden", 512, 256, 512);
    defer std.testing.allocator.free(save_release_golden);
    try std.testing.expectEqualStrings("RESP 186 31\nAPPSUITERELEASESAVE duo golden\n", save_release_golden);

    const mutate_suite = try handleFramedRequest(std.testing.allocator, "REQ 187 APPSUITESAVE duo demo:canary", 512, 256, 512);
    defer std.testing.allocator.free(mutate_suite);
    try std.testing.expectEqualStrings("RESP 187 17\nAPPSUITESAVE duo\n", mutate_suite);

    const save_release_staging = try handleFramedRequest(std.testing.allocator, "REQ 188 APPSUITERELEASESAVE duo staging", 512, 256, 512);
    defer std.testing.allocator.free(save_release_staging);
    try std.testing.expectEqualStrings("RESP 188 32\nAPPSUITERELEASESAVE duo staging\n", save_release_staging);

    const release_list = try handleFramedRequest(std.testing.allocator, "REQ 189 APPSUITERELEASELIST duo", 512, 256, 512);
    defer std.testing.allocator.free(release_list);
    try std.testing.expectEqualStrings("RESP 189 15\ngolden\nstaging\n", release_list);

    const release_info = try handleFramedRequest(std.testing.allocator, "REQ 190 APPSUITERELEASEINFO duo staging", 512, 256, 512);
    defer std.testing.allocator.free(release_info);
    try std.testing.expect(std.mem.startsWith(u8, release_info, "RESP 190 "));
    try std.testing.expect(std.mem.indexOf(u8, release_info, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info, "release=staging") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info, "saved_seq=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info, "entry=demo:canary") != null);

    const activate_release = try handleFramedRequest(std.testing.allocator, "REQ 191 APPSUITERELEASEACTIVATE duo golden", 512, 256, 512);
    defer std.testing.allocator.free(activate_release);
    try std.testing.expectEqualStrings("RESP 191 35\nAPPSUITERELEASEACTIVATE duo golden\n", activate_release);

    const restored_suite_info = try handleFramedRequest(std.testing.allocator, "REQ 192 APPSUITEINFO duo", 512, 256, 512);
    defer std.testing.allocator.free(restored_suite_info);
    try std.testing.expect(std.mem.indexOf(u8, restored_suite_info, "entry=demo:golden") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored_suite_info, "entry=aux:sidecar") != null);

    const delete_release = try handleFramedRequest(std.testing.allocator, "REQ 193 APPSUITERELEASEDELETE duo staging", 512, 256, 512);
    defer std.testing.allocator.free(delete_release);
    try std.testing.expectEqualStrings("RESP 193 34\nAPPSUITERELEASEDELETE duo staging\n", delete_release);

    const mutate_fallback = try handleFramedRequest(std.testing.allocator, "REQ 194 APPSUITESAVE duo demo:canary aux:sidecar", 512, 256, 512);
    defer std.testing.allocator.free(mutate_fallback);
    try std.testing.expectEqualStrings("RESP 194 17\nAPPSUITESAVE duo\n", mutate_fallback);

    const save_release_fallback = try handleFramedRequest(std.testing.allocator, "REQ 195 APPSUITERELEASESAVE duo fallback", 512, 256, 512);
    defer std.testing.allocator.free(save_release_fallback);
    try std.testing.expectEqualStrings("RESP 195 33\nAPPSUITERELEASESAVE duo fallback\n", save_release_fallback);

    const prune_release = try handleFramedRequest(std.testing.allocator, "REQ 196 APPSUITERELEASEPRUNE duo 1", 512, 256, 512);
    defer std.testing.allocator.free(prune_release);
    try std.testing.expectEqualStrings("RESP 196 49\nAPPSUITERELEASEPRUNE duo keep=1 deleted=1 kept=1\n", prune_release);

    const release_list_after_prune = try handleFramedRequest(std.testing.allocator, "REQ 197 APPSUITERELEASELIST duo", 512, 256, 512);
    defer std.testing.allocator.free(release_list_after_prune);
    try std.testing.expectEqualStrings("RESP 197 9\nfallback\n", release_list_after_prune);

    const set_release_channel = try handleFramedRequest(std.testing.allocator, "REQ 198 APPSUITECHANNELSET duo stable fallback", 512, 256, 512);
    defer std.testing.allocator.free(set_release_channel);
    try std.testing.expectEqualStrings("RESP 198 39\nAPPSUITECHANNELSET duo stable fallback\n", set_release_channel);

    const list_release_channels = try handleFramedRequest(std.testing.allocator, "REQ 199 APPSUITECHANNELLIST duo", 512, 256, 512);
    defer std.testing.allocator.free(list_release_channels);
    try std.testing.expectEqualStrings("RESP 199 7\nstable\n", list_release_channels);

    const release_channel_info = try handleFramedRequest(std.testing.allocator, "REQ 200 APPSUITECHANNELINFO duo stable", 512, 256, 512);
    defer std.testing.allocator.free(release_channel_info);
    try std.testing.expect(std.mem.startsWith(u8, release_channel_info, "RESP 200 "));
    try std.testing.expect(std.mem.indexOf(u8, release_channel_info, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_channel_info, "channel=stable") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_channel_info, "release=fallback") != null);

    const activate_release_channel = try handleFramedRequest(std.testing.allocator, "REQ 201 APPSUITECHANNELACTIVATE duo stable", 512, 256, 512);
    defer std.testing.allocator.free(activate_release_channel);
    try std.testing.expectEqualStrings("RESP 201 35\nAPPSUITECHANNELACTIVATE duo stable\n", activate_release_channel);

    const suite_info_after_channel = try handleFramedRequest(std.testing.allocator, "REQ 202 APPSUITEINFO duo", 512, 256, 512);
    defer std.testing.allocator.free(suite_info_after_channel);
    try std.testing.expect(std.mem.indexOf(u8, suite_info_after_channel, "entry=demo:canary") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info_after_channel, "entry=aux:sidecar") != null);
}

test "baremetal tool service manages persisted workspaces" {
    resetPersistentStateForTest();

    try trust_store.installBundle("root-a", "root-a-cert", 1);
    try trust_store.installBundle("root-b", "root-b-cert", 2);
    try trust_store.selectBundle("root-a", 3);

    try package_store.installScriptPackage("demo", "echo release-r1", 4);
    try package_store.snapshotPackageRelease("demo", "r1", 5);
    try package_store.installScriptPackage("demo", "echo release-r2", 6);
    try package_store.snapshotPackageRelease("demo", "r2", 7);
    try package_store.setPackageReleaseChannel("demo", "stable", "r1", 8);
    try package_store.activatePackageReleaseChannel("demo", "stable", 9);

    try package_store.installScriptPackage("aux", "echo aux-sidecar", 10);
    try app_runtime.savePlan("demo", "golden", "", "root-a", abi.display_connector_virtual, 1024, 768, true, 11);
    try app_runtime.savePlan("demo", "alt", "", "", abi.display_connector_virtual, 640, 400, false, 12);
    try app_runtime.savePlan("aux", "sidecar", "", "", abi.display_connector_virtual, 800, 600, false, 13);
    try app_runtime.savePlan("aux", "fallback", "", "", abi.display_connector_virtual, 640, 400, false, 14);
    try app_runtime.saveSuite("duo", "demo:golden aux:sidecar", 15);
    try app_runtime.applyPlan("demo", "golden", 16);
    try app_runtime.applyPlan("aux", "sidecar", 17);

    const save_response = try handleFramedRequest(std.testing.allocator, "REQ 182 WORKSPACESAVE ops duo root-a 1024 768 demo:stable:r1", 512, 256, 512);
    defer std.testing.allocator.free(save_response);
    try std.testing.expectEqualStrings("RESP 182 18\nWORKSPACESAVE ops\n", save_response);

    const list_response = try handleFramedRequest(std.testing.allocator, "REQ 183 WORKSPACELIST", 512, 256, 512);
    defer std.testing.allocator.free(list_response);
    try std.testing.expectEqualStrings("RESP 183 4\nops\n", list_response);

    const info_response = try handleFramedRequest(std.testing.allocator, "REQ 184 WORKSPACEINFO ops", 512, 256, 512);
    defer std.testing.allocator.free(info_response);
    try std.testing.expect(std.mem.startsWith(u8, info_response, "RESP 184 "));
    try std.testing.expect(std.mem.indexOf(u8, info_response, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "trust_bundle=root-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "display=1024x768") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "state_path=/runtime/workspace-runs/ops/last_run.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "channel=demo:stable:r1") != null);

    const plan_save_golden_response = try handleFramedRequest(std.testing.allocator, "REQ 1831 WORKSPACEPLANSAVE ops golden duo root-a 1024 768 demo:stable:r1", 512, 256, 512);
    defer std.testing.allocator.free(plan_save_golden_response);
    try std.testing.expectEqualStrings("RESP 1831 29\nWORKSPACEPLANSAVE ops golden\n", plan_save_golden_response);

    const plan_save_staging_response = try handleFramedRequest(std.testing.allocator, "REQ 1832 WORKSPACEPLANSAVE ops staging none none 640 400 demo:stable:r2", 512, 256, 512);
    defer std.testing.allocator.free(plan_save_staging_response);
    try std.testing.expectEqualStrings("RESP 1832 30\nWORKSPACEPLANSAVE ops staging\n", plan_save_staging_response);

    const plan_list_response = try handleFramedRequest(std.testing.allocator, "REQ 1833 WORKSPACEPLANLIST ops", 512, 256, 512);
    defer std.testing.allocator.free(plan_list_response);
    try std.testing.expectEqualStrings("RESP 1833 15\ngolden\nstaging\n", plan_list_response);

    const plan_info_response = try handleFramedRequest(std.testing.allocator, "REQ 1834 WORKSPACEPLANINFO ops staging", 512, 256, 512);
    defer std.testing.allocator.free(plan_info_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_info_response, "RESP 1834 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_info_response, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_info_response, "plan=staging") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_info_response, "suite=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_info_response, "trust_bundle=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_info_response, "display=640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_info_response, "channel=demo:stable:r2") != null);

    const plan_apply_staging_response = try handleFramedRequest(std.testing.allocator, "REQ 1835 WORKSPACEPLANAPPLY ops staging", 512, 256, 512);
    defer std.testing.allocator.free(plan_apply_staging_response);
    try std.testing.expectEqualStrings("RESP 1835 31\nWORKSPACEPLANAPPLY ops staging\n", plan_apply_staging_response);

    const plan_active_response = try handleFramedRequest(std.testing.allocator, "REQ 1836 WORKSPACEPLANACTIVE ops", 512, 256, 512);
    defer std.testing.allocator.free(plan_active_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_active_response, "RESP 1836 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_active_response, "active_plan=staging") != null);

    const plan_staging_info_response = try handleFramedRequest(std.testing.allocator, "REQ 1837 WORKSPACEINFO ops", 512, 256, 512);
    defer std.testing.allocator.free(plan_staging_info_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_staging_info_response, "RESP 1837 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_staging_info_response, "suite=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_staging_info_response, "trust_bundle=none") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_staging_info_response, "display=640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_staging_info_response, "channel=demo:stable:r2") != null);

    const plan_apply_golden_response = try handleFramedRequest(std.testing.allocator, "REQ 1838 WORKSPACEPLANAPPLY ops golden", 512, 256, 512);
    defer std.testing.allocator.free(plan_apply_golden_response);
    try std.testing.expectEqualStrings("RESP 1838 30\nWORKSPACEPLANAPPLY ops golden\n", plan_apply_golden_response);

    const plan_restored_info_response = try handleFramedRequest(std.testing.allocator, "REQ 1839 WORKSPACEINFO ops", 512, 256, 512);
    defer std.testing.allocator.free(plan_restored_info_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_restored_info_response, "RESP 1839 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_restored_info_response, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_restored_info_response, "trust_bundle=root-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_restored_info_response, "display=1024x768") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_restored_info_response, "channel=demo:stable:r1") != null);

    const plan_delete_staging_response = try handleFramedRequest(std.testing.allocator, "REQ 18391 WORKSPACEPLANDELETE ops staging", 512, 256, 512);
    defer std.testing.allocator.free(plan_delete_staging_response);
    try std.testing.expectEqualStrings("RESP 18391 32\nWORKSPACEPLANDELETE ops staging\n", plan_delete_staging_response);

    const plan_list_after_delete_response = try handleFramedRequest(std.testing.allocator, "REQ 18392 WORKSPACEPLANLIST ops", 512, 256, 512);
    defer std.testing.allocator.free(plan_list_after_delete_response);
    try std.testing.expectEqualStrings("RESP 18392 7\ngolden\n", plan_list_after_delete_response);

    const plan_release_save_v1_response = try handleFramedRequest(std.testing.allocator, "REQ 18393 WORKSPACEPLANRELEASESAVE ops golden v1", 512, 256, 512);
    defer std.testing.allocator.free(plan_release_save_v1_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_release_save_v1_response, "RESP 18393 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_release_save_v1_response, "WORKSPACEPLANRELEASESAVE ops golden v1\n") != null);

    const mutate_plan_release_response = try handleFramedRequest(std.testing.allocator, "REQ 18394 WORKSPACEPLANSAVE ops golden none root-b 800 600 demo:stable:r2", 512, 256, 512);
    defer std.testing.allocator.free(mutate_plan_release_response);
    try std.testing.expectEqualStrings("RESP 18394 29\nWORKSPACEPLANSAVE ops golden\n", mutate_plan_release_response);

    const plan_release_save_v2_response = try handleFramedRequest(std.testing.allocator, "REQ 18395 WORKSPACEPLANRELEASESAVE ops golden v2", 512, 256, 512);
    defer std.testing.allocator.free(plan_release_save_v2_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_release_save_v2_response, "RESP 18395 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_release_save_v2_response, "WORKSPACEPLANRELEASESAVE ops golden v2\n") != null);

    const plan_release_list_response = try handleFramedRequest(std.testing.allocator, "REQ 18396 WORKSPACEPLANRELEASELIST ops golden", 512, 256, 512);
    defer std.testing.allocator.free(plan_release_list_response);
    try std.testing.expectEqualStrings("RESP 18396 6\nv1\nv2\n", plan_release_list_response);

    const plan_release_info_response = try handleFramedRequest(std.testing.allocator, "REQ 18397 WORKSPACEPLANRELEASEINFO ops golden v2", 512, 256, 512);
    defer std.testing.allocator.free(plan_release_info_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_release_info_response, "RESP 18397 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_release_info_response, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_release_info_response, "plan=golden") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_release_info_response, "release=v2") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_release_info_response, "saved_seq=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_release_info_response, "trust_bundle=root-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_release_info_response, "display=800x600") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_release_info_response, "channel=demo:stable:r2") != null);

    const plan_release_activate_v1_response = try handleFramedRequest(std.testing.allocator, "REQ 18398 WORKSPACEPLANRELEASEACTIVATE ops golden v1", 512, 256, 512);
    defer std.testing.allocator.free(plan_release_activate_v1_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_release_activate_v1_response, "RESP 18398 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_release_activate_v1_response, "WORKSPACEPLANRELEASEACTIVATE ops golden v1\n") != null);

    const plan_release_restored_info_response = try handleFramedRequest(std.testing.allocator, "REQ 18399 WORKSPACEPLANINFO ops golden", 512, 256, 512);
    defer std.testing.allocator.free(plan_release_restored_info_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_release_restored_info_response, "RESP 18399 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_release_restored_info_response, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_release_restored_info_response, "trust_bundle=root-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_release_restored_info_response, "display=1024x768") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_release_restored_info_response, "channel=demo:stable:r1") != null);

    const plan_release_delete_v2_response = try handleFramedRequest(std.testing.allocator, "REQ 183901 WORKSPACEPLANRELEASEDELETE ops golden v2", 512, 256, 512);
    defer std.testing.allocator.free(plan_release_delete_v2_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_release_delete_v2_response, "RESP 183901 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_release_delete_v2_response, "WORKSPACEPLANRELEASEDELETE ops golden v2\n") != null);

    const mutate_plan_release_fallback_response = try handleFramedRequest(std.testing.allocator, "REQ 183902 WORKSPACEPLANSAVE ops golden duo root-b 1280 720 demo:stable:r2", 512, 256, 512);
    defer std.testing.allocator.free(mutate_plan_release_fallback_response);
    try std.testing.expectEqualStrings("RESP 183902 29\nWORKSPACEPLANSAVE ops golden\n", mutate_plan_release_fallback_response);

    const plan_release_save_fallback_response = try handleFramedRequest(std.testing.allocator, "REQ 183903 WORKSPACEPLANRELEASESAVE ops golden fallback", 512, 256, 512);
    defer std.testing.allocator.free(plan_release_save_fallback_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_release_save_fallback_response, "RESP 183903 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_release_save_fallback_response, "WORKSPACEPLANRELEASESAVE ops golden fallback\n") != null);

    const plan_release_prune_response = try handleFramedRequest(std.testing.allocator, "REQ 183904 WORKSPACEPLANRELEASEPRUNE ops golden 1", 512, 256, 512);
    defer std.testing.allocator.free(plan_release_prune_response);
    try std.testing.expect(std.mem.startsWith(u8, plan_release_prune_response, "RESP 183904 "));
    try std.testing.expect(std.mem.indexOf(u8, plan_release_prune_response, "WORKSPACEPLANRELEASEPRUNE ops golden keep=1 deleted=1 kept=1\n") != null);

    const plan_release_list_after_prune_response = try handleFramedRequest(std.testing.allocator, "REQ 183905 WORKSPACEPLANRELEASELIST ops golden", 512, 256, 512);
    defer std.testing.allocator.free(plan_release_list_after_prune_response);
    try std.testing.expectEqualStrings("RESP 183905 9\nfallback\n", plan_release_list_after_prune_response);

    const release_save_response = try handleFramedRequest(std.testing.allocator, "REQ 1841 WORKSPACERELEASESAVE ops golden", 512, 256, 512);
    defer std.testing.allocator.free(release_save_response);
    try std.testing.expect(std.mem.startsWith(u8, release_save_response, "RESP 1841 "));
    try std.testing.expect(std.mem.indexOf(u8, release_save_response, "WORKSPACERELEASESAVE ops golden\n") != null);

    const mutate_workspace_response = try handleFramedRequest(std.testing.allocator, "REQ 1842 WORKSPACESAVE ops duo root-b 640 400 demo:stable:r2", 512, 256, 512);
    defer std.testing.allocator.free(mutate_workspace_response);
    try std.testing.expectEqualStrings("RESP 1842 18\nWORKSPACESAVE ops\n", mutate_workspace_response);

    const release_save_staging_response = try handleFramedRequest(std.testing.allocator, "REQ 1843 WORKSPACERELEASESAVE ops staging", 512, 256, 512);
    defer std.testing.allocator.free(release_save_staging_response);
    try std.testing.expect(std.mem.startsWith(u8, release_save_staging_response, "RESP 1843 "));
    try std.testing.expect(std.mem.indexOf(u8, release_save_staging_response, "WORKSPACERELEASESAVE ops staging\n") != null);

    const release_list_response = try handleFramedRequest(std.testing.allocator, "REQ 1844 WORKSPACERELEASELIST ops", 512, 256, 512);
    defer std.testing.allocator.free(release_list_response);
    try std.testing.expectEqualStrings("RESP 1844 15\ngolden\nstaging\n", release_list_response);

    const release_info_response = try handleFramedRequest(std.testing.allocator, "REQ 1845 WORKSPACERELEASEINFO ops staging", 512, 256, 512);
    defer std.testing.allocator.free(release_info_response);
    try std.testing.expect(std.mem.startsWith(u8, release_info_response, "RESP 1845 "));
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "release=staging") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "saved_seq=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "trust_bundle=root-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "display=640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "channel=demo:stable:r2") != null);

    const channel_set_staging_response = try handleFramedRequest(std.testing.allocator, "REQ 1852 WORKSPACECHANNELSET ops stable staging", 512, 256, 512);
    defer std.testing.allocator.free(channel_set_staging_response);
    try std.testing.expect(std.mem.startsWith(u8, channel_set_staging_response, "RESP 1852 "));
    try std.testing.expect(std.mem.indexOf(u8, channel_set_staging_response, "WORKSPACECHANNELSET ops stable staging\n") != null);

    const channel_list_response = try handleFramedRequest(std.testing.allocator, "REQ 1853 WORKSPACECHANNELLIST ops", 512, 256, 512);
    defer std.testing.allocator.free(channel_list_response);
    try std.testing.expectEqualStrings("RESP 1853 7\nstable\n", channel_list_response);

    const channel_info_response = try handleFramedRequest(std.testing.allocator, "REQ 1854 WORKSPACECHANNELINFO ops stable", 512, 256, 512);
    defer std.testing.allocator.free(channel_info_response);
    try std.testing.expect(std.mem.startsWith(u8, channel_info_response, "RESP 1854 "));
    try std.testing.expect(std.mem.indexOf(u8, channel_info_response, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, channel_info_response, "channel=stable") != null);
    try std.testing.expect(std.mem.indexOf(u8, channel_info_response, "release=staging") != null);

    const channel_activate_staging_response = try handleFramedRequest(std.testing.allocator, "REQ 1855 WORKSPACECHANNELACTIVATE ops stable", 512, 256, 512);
    defer std.testing.allocator.free(channel_activate_staging_response);
    try std.testing.expect(std.mem.startsWith(u8, channel_activate_staging_response, "RESP 1855 "));
    try std.testing.expect(std.mem.indexOf(u8, channel_activate_staging_response, "WORKSPACECHANNELACTIVATE ops stable\n") != null);

    const staging_info_response = try handleFramedRequest(std.testing.allocator, "REQ 1856 WORKSPACEINFO ops", 512, 256, 512);
    defer std.testing.allocator.free(staging_info_response);
    try std.testing.expect(std.mem.indexOf(u8, staging_info_response, "trust_bundle=root-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, staging_info_response, "display=640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, staging_info_response, "channel=demo:stable:r2") != null);

    const channel_set_golden_response = try handleFramedRequest(std.testing.allocator, "REQ 1857 WORKSPACECHANNELSET ops stable golden", 512, 256, 512);
    defer std.testing.allocator.free(channel_set_golden_response);
    try std.testing.expect(std.mem.startsWith(u8, channel_set_golden_response, "RESP 1857 "));
    try std.testing.expect(std.mem.indexOf(u8, channel_set_golden_response, "WORKSPACECHANNELSET ops stable golden\n") != null);

    const channel_activate_golden_response = try handleFramedRequest(std.testing.allocator, "REQ 1858 WORKSPACECHANNELACTIVATE ops stable", 512, 256, 512);
    defer std.testing.allocator.free(channel_activate_golden_response);
    try std.testing.expect(std.mem.startsWith(u8, channel_activate_golden_response, "RESP 1858 "));
    try std.testing.expect(std.mem.indexOf(u8, channel_activate_golden_response, "WORKSPACECHANNELACTIVATE ops stable\n") != null);

    const release_activate_response = try handleFramedRequest(std.testing.allocator, "REQ 1846 WORKSPACERELEASEACTIVATE ops golden", 512, 256, 512);
    defer std.testing.allocator.free(release_activate_response);
    try std.testing.expect(std.mem.startsWith(u8, release_activate_response, "RESP 1846 "));
    try std.testing.expect(std.mem.indexOf(u8, release_activate_response, "WORKSPACERELEASEACTIVATE ops golden\n") != null);

    const restored_info_response = try handleFramedRequest(std.testing.allocator, "REQ 1847 WORKSPACEINFO ops", 512, 256, 512);
    defer std.testing.allocator.free(restored_info_response);
    try std.testing.expect(std.mem.indexOf(u8, restored_info_response, "trust_bundle=root-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored_info_response, "display=1024x768") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored_info_response, "channel=demo:stable:r1") != null);

    const release_delete_response = try handleFramedRequest(std.testing.allocator, "REQ 1848 WORKSPACERELEASEDELETE ops staging", 512, 256, 512);
    defer std.testing.allocator.free(release_delete_response);
    try std.testing.expect(std.mem.startsWith(u8, release_delete_response, "RESP 1848 "));
    try std.testing.expect(std.mem.indexOf(u8, release_delete_response, "WORKSPACERELEASEDELETE ops staging\n") != null);

    const release_save_fallback_response = try handleFramedRequest(std.testing.allocator, "REQ 1849 WORKSPACERELEASESAVE ops fallback", 512, 256, 512);
    defer std.testing.allocator.free(release_save_fallback_response);
    try std.testing.expect(std.mem.startsWith(u8, release_save_fallback_response, "RESP 1849 "));
    try std.testing.expect(std.mem.indexOf(u8, release_save_fallback_response, "WORKSPACERELEASESAVE ops fallback\n") != null);

    const release_prune_response = try handleFramedRequest(std.testing.allocator, "REQ 1850 WORKSPACERELEASEPRUNE ops 1", 512, 256, 512);
    defer std.testing.allocator.free(release_prune_response);
    try std.testing.expect(std.mem.startsWith(u8, release_prune_response, "RESP 1850 "));
    try std.testing.expect(std.mem.indexOf(u8, release_prune_response, "WORKSPACERELEASEPRUNE ops keep=1 deleted=1 kept=1\n") != null);

    const release_list_after_prune = try handleFramedRequest(std.testing.allocator, "REQ 1851 WORKSPACERELEASELIST ops", 512, 256, 512);
    defer std.testing.allocator.free(release_list_after_prune);
    try std.testing.expectEqualStrings("RESP 1851 9\nfallback\n", release_list_after_prune);

    try package_store.setPackageReleaseChannel("demo", "stable", "r2", 18);
    try package_store.activatePackageReleaseChannel("demo", "stable", 19);
    try trust_store.selectBundle("root-b", 20);
    try framebuffer_console.setMode(640, 400);
    try app_runtime.applyPlan("demo", "alt", 21);
    try app_runtime.applyPlan("aux", "fallback", 22);

    const apply_response = try handleFramedRequest(std.testing.allocator, "REQ 185 WORKSPACEAPPLY ops", 512, 256, 512);
    defer std.testing.allocator.free(apply_response);
    try std.testing.expectEqualStrings("RESP 185 19\nWORKSPACEAPPLY ops\n", apply_response);

    const active_bundle = try trust_store.activeBundleNameAlloc(std.testing.allocator, trust_store.max_name_len);
    defer std.testing.allocator.free(active_bundle);
    try std.testing.expectEqualStrings("root-a", active_bundle);

    const display_state = framebuffer_console.statePtr();
    try std.testing.expectEqual(@as(u16, 1024), display_state.width);
    try std.testing.expectEqual(@as(u16, 768), display_state.height);

    var entrypoint_buffer: [filesystem.max_path_len]u8 = undefined;
    const profile = try package_store.loadLaunchProfile("demo", &entrypoint_buffer);
    const restored_script = try filesystem.readFileAlloc(std.testing.allocator, profile.entrypoint, 64);
    defer std.testing.allocator.free(restored_script);
    try std.testing.expectEqualStrings("echo release-r1", restored_script);

    const demo_active = try app_runtime.activePlanInfoAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(demo_active);
    try std.testing.expect(std.mem.indexOf(u8, demo_active, "active_plan=golden") != null);

    const aux_active = try app_runtime.activePlanInfoAlloc(std.testing.allocator, "aux", 256);
    defer std.testing.allocator.free(aux_active);
    try std.testing.expect(std.mem.indexOf(u8, aux_active, "active_plan=sidecar") != null);

    const run_response = try handleFramedRequest(std.testing.allocator, "REQ 186 WORKSPACERUN ops", 512, 256, 512);
    defer std.testing.allocator.free(run_response);
    try std.testing.expectEqualStrings("RESP 186 23\nrelease-r1\naux-sidecar\n", run_response);

    const state_response = try handleFramedRequest(std.testing.allocator, "REQ 187 WORKSPACESTATE ops", 512, 256, 512);
    defer std.testing.allocator.free(state_response);
    try std.testing.expect(std.mem.startsWith(u8, state_response, "RESP 187 "));
    try std.testing.expect(std.mem.indexOf(u8, state_response, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, state_response, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, state_response, "exit_code=0") != null);

    const history_response = try handleFramedRequest(std.testing.allocator, "REQ 188 WORKSPACEHISTORY ops", 512, 256, 512);
    defer std.testing.allocator.free(history_response);
    try std.testing.expect(std.mem.startsWith(u8, history_response, "RESP 188 "));
    try std.testing.expect(std.mem.indexOf(u8, history_response, "workspace=ops") != null);

    const stdout_response = try handleFramedRequest(std.testing.allocator, "REQ 189 WORKSPACESTDOUT ops", 512, 256, 512);
    defer std.testing.allocator.free(stdout_response);
    try std.testing.expectEqualStrings("RESP 189 23\nrelease-r1\naux-sidecar\n", stdout_response);

    const stderr_response = try handleFramedRequest(std.testing.allocator, "REQ 190 WORKSPACESTDERR ops", 512, 256, 512);
    defer std.testing.allocator.free(stderr_response);
    try std.testing.expectEqualStrings("RESP 190 0\n", stderr_response);

    const delete_response = try handleFramedRequest(std.testing.allocator, "REQ 191 WORKSPACEDELETE ops", 512, 256, 512);
    defer std.testing.allocator.free(delete_response);
    try std.testing.expectEqualStrings("RESP 191 20\nWORKSPACEDELETE ops\n", delete_response);

    const list_after_delete = try handleFramedRequest(std.testing.allocator, "REQ 192 WORKSPACELIST", 512, 256, 512);
    defer std.testing.allocator.free(list_after_delete);
    try std.testing.expectEqualStrings("RESP 192 0\n", list_after_delete);

    try std.testing.expectError(error.FileNotFound, filesystem.statSummary("/runtime/workspaces/ops.txt"));
    try std.testing.expectError(error.FileNotFound, filesystem.statSummary("/runtime/workspace-runs/ops"));
}

test "baremetal tool service persists and runs workspace suites" {
    resetPersistentStateForTest();

    try trust_store.installBundle("root-a", "root-a-cert", 1);
    try trust_store.installBundle("root-b", "root-b-cert", 2);
    try package_store.installScriptPackage("demo", "echo demo-workspace", 3);
    try package_store.installScriptPackage("aux", "echo aux-workspace", 4);
    try app_runtime.savePlan("demo", "boot", "", "", abi.display_connector_virtual, 1024, 768, false, 5);
    try app_runtime.savePlan("aux", "sidecar", "", "", abi.display_connector_virtual, 800, 600, false, 6);
    try app_runtime.saveSuite("demo-suite", "demo:boot", 7);
    try app_runtime.saveSuite("aux-suite", "aux:sidecar", 8);

    const save_ops_response = try handleFramedRequest(std.testing.allocator, "REQ 2031 WORKSPACESAVE ops demo-suite root-a 1024 768", 512, 256, 512);
    defer std.testing.allocator.free(save_ops_response);
    try std.testing.expectEqualStrings("RESP 2031 18\nWORKSPACESAVE ops\n", save_ops_response);

    const save_sidecar_response = try handleFramedRequest(std.testing.allocator, "REQ 2032 WORKSPACESAVE sidecar aux-suite root-b 800 600", 512, 256, 512);
    defer std.testing.allocator.free(save_sidecar_response);
    try std.testing.expectEqualStrings("RESP 2032 22\nWORKSPACESAVE sidecar\n", save_sidecar_response);

    const suite_save_response = try handleFramedRequest(std.testing.allocator, "REQ 2033 WORKSPACESUITESAVE crew ops sidecar", 512, 256, 512);
    defer std.testing.allocator.free(suite_save_response);
    const suite_save_payload = "WORKSPACESUITESAVE crew\n";
    const suite_save_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 2033 {d}\n{s}", .{ suite_save_payload.len, suite_save_payload });
    defer std.testing.allocator.free(suite_save_expected);
    try std.testing.expectEqualStrings(suite_save_expected, suite_save_response);

    const suite_list_response = try handleFramedRequest(std.testing.allocator, "REQ 2034 WORKSPACESUITELIST", 512, 256, 512);
    defer std.testing.allocator.free(suite_list_response);
    try std.testing.expectEqualStrings("RESP 2034 5\ncrew\n", suite_list_response);

    const suite_info_response = try handleFramedRequest(std.testing.allocator, "REQ 2035 WORKSPACESUITEINFO crew", 512, 256, 512);
    defer std.testing.allocator.free(suite_info_response);
    try std.testing.expect(std.mem.startsWith(u8, suite_info_response, "RESP 2035 "));
    try std.testing.expect(std.mem.indexOf(u8, suite_info_response, "suite=crew") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info_response, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info_response, "workspace=sidecar") != null);

    const suite_apply_response = try handleFramedRequest(std.testing.allocator, "REQ 2036 WORKSPACESUITEAPPLY crew", 512, 256, 512);
    defer std.testing.allocator.free(suite_apply_response);
    const suite_apply_payload = "WORKSPACESUITEAPPLY crew\n";
    const suite_apply_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 2036 {d}\n{s}", .{ suite_apply_payload.len, suite_apply_payload });
    defer std.testing.allocator.free(suite_apply_expected);
    try std.testing.expectEqualStrings(suite_apply_expected, suite_apply_response);

    const active_bundle = try trust_store.activeBundleNameAlloc(std.testing.allocator, trust_store.max_name_len);
    defer std.testing.allocator.free(active_bundle);
    try std.testing.expectEqualStrings("root-b", active_bundle);

    const display_state = framebuffer_console.statePtr();
    try std.testing.expectEqual(@as(u16, 800), display_state.width);
    try std.testing.expectEqual(@as(u16, 600), display_state.height);

    const suite_run_response = try handleFramedRequest(std.testing.allocator, "REQ 2037 WORKSPACESUITERUN crew", 512, 256, 512);
    defer std.testing.allocator.free(suite_run_response);
    const suite_run_payload = "demo-workspace\naux-workspace\n";
    const suite_run_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 2037 {d}\n{s}", .{ suite_run_payload.len, suite_run_payload });
    defer std.testing.allocator.free(suite_run_expected);
    try std.testing.expectEqualStrings(suite_run_expected, suite_run_response);

    const suite_delete_response = try handleFramedRequest(std.testing.allocator, "REQ 2038 WORKSPACESUITEDELETE crew", 512, 256, 512);
    defer std.testing.allocator.free(suite_delete_response);
    const suite_delete_payload = "WORKSPACESUITEDELETE crew\n";
    const suite_delete_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 2038 {d}\n{s}", .{ suite_delete_payload.len, suite_delete_payload });
    defer std.testing.allocator.free(suite_delete_expected);
    try std.testing.expectEqualStrings(suite_delete_expected, suite_delete_response);

    const suite_list_after_delete = try handleFramedRequest(std.testing.allocator, "REQ 2039 WORKSPACESUITELIST", 512, 256, 512);
    defer std.testing.allocator.free(suite_list_after_delete);
    try std.testing.expectEqualStrings("RESP 2039 0\n", suite_list_after_delete);

    try std.testing.expectError(error.FileNotFound, filesystem.statSummary("/runtime/workspace-suites/crew.txt"));
}

test "baremetal tool service manages workspace suite releases" {
    resetPersistentStateForTest();

    try trust_store.installBundle("root-a", "root-a-cert", 1);
    try trust_store.installBundle("root-b", "root-b-cert", 2);
    try package_store.installScriptPackage("demo", "echo demo-workspace", 3);
    try package_store.installScriptPackage("aux", "echo aux-workspace", 4);
    try app_runtime.savePlan("demo", "boot", "", "", abi.display_connector_virtual, 1024, 768, false, 5);
    try app_runtime.savePlan("aux", "sidecar", "", "", abi.display_connector_virtual, 800, 600, false, 6);
    try app_runtime.saveSuite("demo-suite", "demo:boot", 7);
    try app_runtime.saveSuite("aux-suite", "aux:sidecar", 8);

    const save_ops_response = try handleFramedRequest(std.testing.allocator, "REQ 2041 WORKSPACESAVE ops demo-suite root-a 1024 768", 512, 256, 768);
    defer std.testing.allocator.free(save_ops_response);
    try std.testing.expectEqualStrings("RESP 2041 18\nWORKSPACESAVE ops\n", save_ops_response);

    const save_sidecar_response = try handleFramedRequest(std.testing.allocator, "REQ 2042 WORKSPACESAVE sidecar aux-suite root-b 800 600", 512, 256, 768);
    defer std.testing.allocator.free(save_sidecar_response);
    try std.testing.expectEqualStrings("RESP 2042 22\nWORKSPACESAVE sidecar\n", save_sidecar_response);

    const suite_save_response = try handleFramedRequest(std.testing.allocator, "REQ 2043 WORKSPACESUITESAVE crew ops sidecar", 512, 256, 768);
    defer std.testing.allocator.free(suite_save_response);
    try std.testing.expectEqualStrings("RESP 2043 24\nWORKSPACESUITESAVE crew\n", suite_save_response);

    const release_save_golden_response = try handleFramedRequest(std.testing.allocator, "REQ 2044 WORKSPACESUITERELEASESAVE crew golden", 512, 256, 768);
    defer std.testing.allocator.free(release_save_golden_response);
    try std.testing.expect(std.mem.startsWith(u8, release_save_golden_response, "RESP 2044 "));
    try std.testing.expect(std.mem.indexOf(u8, release_save_golden_response, "WORKSPACESUITERELEASESAVE crew golden\n") != null);

    const mutate_ops_response = try handleFramedRequest(std.testing.allocator, "REQ 2045 WORKSPACESAVE ops demo-suite root-b 640 400", 512, 256, 768);
    defer std.testing.allocator.free(mutate_ops_response);
    try std.testing.expectEqualStrings("RESP 2045 18\nWORKSPACESAVE ops\n", mutate_ops_response);

    const suite_overwrite_response = try handleFramedRequest(std.testing.allocator, "REQ 2046 WORKSPACESUITESAVE crew ops", 512, 256, 768);
    defer std.testing.allocator.free(suite_overwrite_response);
    try std.testing.expectEqualStrings("RESP 2046 24\nWORKSPACESUITESAVE crew\n", suite_overwrite_response);

    const release_save_staging_response = try handleFramedRequest(std.testing.allocator, "REQ 2047 WORKSPACESUITERELEASESAVE crew staging", 512, 256, 768);
    defer std.testing.allocator.free(release_save_staging_response);
    try std.testing.expect(std.mem.startsWith(u8, release_save_staging_response, "RESP 2047 "));
    try std.testing.expect(std.mem.indexOf(u8, release_save_staging_response, "WORKSPACESUITERELEASESAVE crew staging\n") != null);

    const release_list_response = try handleFramedRequest(std.testing.allocator, "REQ 2048 WORKSPACESUITERELEASELIST crew", 512, 256, 768);
    defer std.testing.allocator.free(release_list_response);
    try std.testing.expectEqualStrings("RESP 2048 15\ngolden\nstaging\n", release_list_response);

    const release_info_response = try handleFramedRequest(std.testing.allocator, "REQ 2049 WORKSPACESUITERELEASEINFO crew staging", 512, 256, 768);
    defer std.testing.allocator.free(release_info_response);
    try std.testing.expect(std.mem.startsWith(u8, release_info_response, "RESP 2049 "));
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "suite=crew") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "release=staging") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "saved_seq=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, release_info_response, "workspace=ops") != null);

    const release_activate_response = try handleFramedRequest(std.testing.allocator, "REQ 2050 WORKSPACESUITERELEASEACTIVATE crew golden", 512, 256, 768);
    defer std.testing.allocator.free(release_activate_response);
    try std.testing.expect(std.mem.startsWith(u8, release_activate_response, "RESP 2050 "));
    try std.testing.expect(std.mem.indexOf(u8, release_activate_response, "WORKSPACESUITERELEASEACTIVATE crew golden\n") != null);

    const suite_info_response = try handleFramedRequest(std.testing.allocator, "REQ 2051 WORKSPACESUITEINFO crew", 512, 256, 768);
    defer std.testing.allocator.free(suite_info_response);
    try std.testing.expect(std.mem.startsWith(u8, suite_info_response, "RESP 2051 "));
    try std.testing.expect(std.mem.indexOf(u8, suite_info_response, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info_response, "workspace=sidecar") != null);

    const release_delete_response = try handleFramedRequest(std.testing.allocator, "REQ 2052 WORKSPACESUITERELEASEDELETE crew staging", 512, 256, 768);
    defer std.testing.allocator.free(release_delete_response);
    try std.testing.expect(std.mem.startsWith(u8, release_delete_response, "RESP 2052 "));
    try std.testing.expect(std.mem.indexOf(u8, release_delete_response, "WORKSPACESUITERELEASEDELETE crew staging\n") != null);

    const release_list_after_delete_response = try handleFramedRequest(std.testing.allocator, "REQ 2053 WORKSPACESUITERELEASELIST crew", 512, 256, 768);
    defer std.testing.allocator.free(release_list_after_delete_response);
    try std.testing.expectEqualStrings("RESP 2053 7\ngolden\n", release_list_after_delete_response);

    const mutate_ops_fallback_response = try handleFramedRequest(std.testing.allocator, "REQ 2054 WORKSPACESAVE ops demo-suite root-b 640 400", 512, 256, 768);
    defer std.testing.allocator.free(mutate_ops_fallback_response);
    try std.testing.expectEqualStrings("RESP 2054 18\nWORKSPACESAVE ops\n", mutate_ops_fallback_response);

    const suite_fallback_response = try handleFramedRequest(std.testing.allocator, "REQ 2055 WORKSPACESUITESAVE crew ops", 512, 256, 768);
    defer std.testing.allocator.free(suite_fallback_response);
    try std.testing.expectEqualStrings("RESP 2055 24\nWORKSPACESUITESAVE crew\n", suite_fallback_response);

    const release_save_fallback_response = try handleFramedRequest(std.testing.allocator, "REQ 2056 WORKSPACESUITERELEASESAVE crew fallback", 512, 256, 768);
    defer std.testing.allocator.free(release_save_fallback_response);
    try std.testing.expect(std.mem.startsWith(u8, release_save_fallback_response, "RESP 2056 "));
    try std.testing.expect(std.mem.indexOf(u8, release_save_fallback_response, "WORKSPACESUITERELEASESAVE crew fallback\n") != null);

    const release_prune_response = try handleFramedRequest(std.testing.allocator, "REQ 2057 WORKSPACESUITERELEASEPRUNE crew 1", 512, 256, 768);
    defer std.testing.allocator.free(release_prune_response);
    try std.testing.expect(std.mem.startsWith(u8, release_prune_response, "RESP 2057 "));
    try std.testing.expect(std.mem.indexOf(u8, release_prune_response, "WORKSPACESUITERELEASEPRUNE crew keep=1 deleted=1 kept=1\n") != null);

    const release_list_final_response = try handleFramedRequest(std.testing.allocator, "REQ 2058 WORKSPACESUITERELEASELIST crew", 512, 256, 768);
    defer std.testing.allocator.free(release_list_final_response);
    try std.testing.expectEqualStrings("RESP 2058 9\nfallback\n", release_list_final_response);

    const channel_set_response = try handleFramedRequest(std.testing.allocator, "REQ 2059 WORKSPACESUITECHANNELSET crew stable fallback", 512, 256, 768);
    defer std.testing.allocator.free(channel_set_response);
    try std.testing.expect(std.mem.startsWith(u8, channel_set_response, "RESP 2059 "));
    try std.testing.expect(std.mem.indexOf(u8, channel_set_response, "WORKSPACESUITECHANNELSET crew stable fallback\n") != null);

    const channel_list_response = try handleFramedRequest(std.testing.allocator, "REQ 2060 WORKSPACESUITECHANNELLIST crew", 512, 256, 768);
    defer std.testing.allocator.free(channel_list_response);
    try std.testing.expectEqualStrings("RESP 2060 7\nstable\n", channel_list_response);

    const channel_info_response = try handleFramedRequest(std.testing.allocator, "REQ 2061 WORKSPACESUITECHANNELINFO crew stable", 512, 256, 768);
    defer std.testing.allocator.free(channel_info_response);
    try std.testing.expect(std.mem.startsWith(u8, channel_info_response, "RESP 2061 "));
    try std.testing.expect(std.mem.indexOf(u8, channel_info_response, "suite=crew") != null);
    try std.testing.expect(std.mem.indexOf(u8, channel_info_response, "channel=stable") != null);
    try std.testing.expect(std.mem.indexOf(u8, channel_info_response, "release=fallback") != null);

    const channel_activate_response = try handleFramedRequest(std.testing.allocator, "REQ 2062 WORKSPACESUITECHANNELACTIVATE crew stable", 512, 256, 768);
    defer std.testing.allocator.free(channel_activate_response);
    try std.testing.expect(std.mem.startsWith(u8, channel_activate_response, "RESP 2062 "));
    try std.testing.expect(std.mem.indexOf(u8, channel_activate_response, "WORKSPACESUITECHANNELACTIVATE crew stable\n") != null);

    const suite_info_after_channel_response = try handleFramedRequest(std.testing.allocator, "REQ 2063 WORKSPACESUITEINFO crew", 512, 256, 768);
    defer std.testing.allocator.free(suite_info_after_channel_response);
    try std.testing.expect(std.mem.startsWith(u8, suite_info_after_channel_response, "RESP 2063 "));
    try std.testing.expect(std.mem.indexOf(u8, suite_info_after_channel_response, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info_after_channel_response, "workspace=sidecar") == null);
}

test "baremetal tool service persists and runs workspace autorun requests" {
    resetPersistentStateForTest();

    try package_store.installScriptPackage("demo", "echo demo-workspace", 1);
    try package_store.installScriptPackage("aux", "echo aux-workspace", 2);
    try app_runtime.savePlan("demo", "boot", "", "", abi.display_connector_virtual, 1024, 768, false, 3);
    try app_runtime.savePlan("aux", "sidecar", "", "", abi.display_connector_virtual, 800, 600, false, 4);
    try app_runtime.saveSuite("demo-suite", "demo:boot", 5);
    try app_runtime.saveSuite("aux-suite", "aux:sidecar", 6);

    const save_ops_response = try handleFramedRequest(std.testing.allocator, "REQ 193 WORKSPACESAVE ops demo-suite none 1024 768", 512, 256, 512);
    defer std.testing.allocator.free(save_ops_response);
    try std.testing.expectEqualStrings("RESP 193 18\nWORKSPACESAVE ops\n", save_ops_response);

    const save_sidecar_response = try handleFramedRequest(std.testing.allocator, "REQ 194 WORKSPACESAVE sidecar aux-suite none 800 600", 512, 256, 512);
    defer std.testing.allocator.free(save_sidecar_response);
    try std.testing.expectEqualStrings("RESP 194 22\nWORKSPACESAVE sidecar\n", save_sidecar_response);

    const add_ops_response = try handleFramedRequest(std.testing.allocator, "REQ 195 WORKSPACEAUTORUNADD ops", 512, 256, 512);
    defer std.testing.allocator.free(add_ops_response);
    const add_ops_payload = "WORKSPACEAUTORUNADD ops\n";
    const add_ops_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 195 {d}\n{s}", .{ add_ops_payload.len, add_ops_payload });
    defer std.testing.allocator.free(add_ops_expected);
    try std.testing.expectEqualStrings(add_ops_expected, add_ops_response);

    const add_sidecar_response = try handleFramedRequest(std.testing.allocator, "REQ 196 WORKSPACEAUTORUNADD sidecar", 512, 256, 512);
    defer std.testing.allocator.free(add_sidecar_response);
    const add_sidecar_payload = "WORKSPACEAUTORUNADD sidecar\n";
    const add_sidecar_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 196 {d}\n{s}", .{ add_sidecar_payload.len, add_sidecar_payload });
    defer std.testing.allocator.free(add_sidecar_expected);
    try std.testing.expectEqualStrings(add_sidecar_expected, add_sidecar_response);

    const list_response = try handleFramedRequest(std.testing.allocator, "REQ 197 WORKSPACEAUTORUNLIST", 512, 256, 512);
    defer std.testing.allocator.free(list_response);
    const list_payload = "ops\nsidecar\n";
    const list_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 197 {d}\n{s}", .{ list_payload.len, list_payload });
    defer std.testing.allocator.free(list_expected);
    try std.testing.expectEqualStrings(list_expected, list_response);

    const run_response = try handleFramedRequest(std.testing.allocator, "REQ 198 WORKSPACEAUTORUNRUN", 512, 256, 512);
    defer std.testing.allocator.free(run_response);
    const run_payload = "demo-workspace\naux-workspace\n";
    const run_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 198 {d}\n{s}", .{ run_payload.len, run_payload });
    defer std.testing.allocator.free(run_expected);
    try std.testing.expectEqualStrings(run_expected, run_response);

    const sidecar_state = try workspace_runtime.stateAlloc(std.testing.allocator, "sidecar", 256);
    defer std.testing.allocator.free(sidecar_state);
    try std.testing.expect(std.mem.indexOf(u8, sidecar_state, "exit_code=0") != null);

    const sidecar_stdout = try workspace_runtime.stdoutAlloc(std.testing.allocator, "sidecar", 256);
    defer std.testing.allocator.free(sidecar_stdout);
    try std.testing.expectEqualStrings("aux-workspace\n", sidecar_stdout);

    const remove_ops_response = try handleFramedRequest(std.testing.allocator, "REQ 199 WORKSPACEAUTORUNREMOVE ops", 512, 256, 512);
    defer std.testing.allocator.free(remove_ops_response);
    const remove_ops_payload = "WORKSPACEAUTORUNREMOVE ops\n";
    const remove_ops_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 199 {d}\n{s}", .{ remove_ops_payload.len, remove_ops_payload });
    defer std.testing.allocator.free(remove_ops_expected);
    try std.testing.expectEqualStrings(remove_ops_expected, remove_ops_response);

    const updated_list_response = try handleFramedRequest(std.testing.allocator, "REQ 200 WORKSPACEAUTORUNLIST", 512, 256, 512);
    defer std.testing.allocator.free(updated_list_response);
    const updated_list_payload = "sidecar\n";
    const updated_list_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 200 {d}\n{s}", .{ updated_list_payload.len, updated_list_payload });
    defer std.testing.allocator.free(updated_list_expected);
    try std.testing.expectEqualStrings(updated_list_expected, updated_list_response);

    const delete_sidecar_response = try handleFramedRequest(std.testing.allocator, "REQ 201 WORKSPACEDELETE sidecar", 512, 256, 512);
    defer std.testing.allocator.free(delete_sidecar_response);
    try std.testing.expectEqualStrings("RESP 201 24\nWORKSPACEDELETE sidecar\n", delete_sidecar_response);

    const final_list_response = try handleFramedRequest(std.testing.allocator, "REQ 202 WORKSPACEAUTORUNLIST", 512, 256, 512);
    defer std.testing.allocator.free(final_list_response);
    try std.testing.expectEqualStrings("RESP 202 0\n", final_list_response);
}

test "baremetal tool service persists and runs autorun requests" {
    resetPersistentStateForTest();

    try package_store.installScriptPackage("demo", "echo demo-autorun", 1);
    try package_store.installScriptPackage("aux", "echo aux-autorun", 2);

    const add_demo_payload = "APPAUTORUNADD demo\n";
    const add_aux_payload = "APPAUTORUNADD aux\n";
    const list_payload = "demo\naux\n";
    const run_payload = "demo-autorun\naux-autorun\n";
    const remove_demo_payload = "APPAUTORUNREMOVE demo\n";
    const updated_list_payload = "aux\n";

    const add_demo_response = try handleFramedRequest(std.testing.allocator, "REQ 60 APPAUTORUNADD demo", 512, 256, 512);
    defer std.testing.allocator.free(add_demo_response);
    const add_demo_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 60 {d}\n{s}", .{ add_demo_payload.len, add_demo_payload });
    defer std.testing.allocator.free(add_demo_expected);
    try std.testing.expectEqualStrings(add_demo_expected, add_demo_response);

    const add_aux_response = try handleFramedRequest(std.testing.allocator, "REQ 61 APPAUTORUNADD aux", 512, 256, 512);
    defer std.testing.allocator.free(add_aux_response);
    const add_aux_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 61 {d}\n{s}", .{ add_aux_payload.len, add_aux_payload });
    defer std.testing.allocator.free(add_aux_expected);
    try std.testing.expectEqualStrings(add_aux_expected, add_aux_response);

    const list_response = try handleFramedRequest(std.testing.allocator, "REQ 62 APPAUTORUNLIST", 512, 256, 512);
    defer std.testing.allocator.free(list_response);
    const list_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 62 {d}\n{s}", .{ list_payload.len, list_payload });
    defer std.testing.allocator.free(list_expected);
    try std.testing.expectEqualStrings(list_expected, list_response);

    const run_response = try handleFramedRequest(std.testing.allocator, "REQ 63 APPAUTORUNRUN", 512, 256, 512);
    defer std.testing.allocator.free(run_response);
    const run_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 63 {d}\n{s}", .{ run_payload.len, run_payload });
    defer std.testing.allocator.free(run_expected);
    try std.testing.expectEqualStrings(run_expected, run_response);

    const demo_state = try app_runtime.stateAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(demo_state);
    try std.testing.expect(std.mem.indexOf(u8, demo_state, "exit_code=0") != null);

    const aux_stdout = try app_runtime.stdoutAlloc(std.testing.allocator, "aux", 256);
    defer std.testing.allocator.free(aux_stdout);
    try std.testing.expectEqualStrings("aux-autorun\n", aux_stdout);

    const remove_demo_response = try handleFramedRequest(std.testing.allocator, "REQ 64 APPAUTORUNREMOVE demo", 512, 256, 512);
    defer std.testing.allocator.free(remove_demo_response);
    const remove_demo_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 64 {d}\n{s}", .{ remove_demo_payload.len, remove_demo_payload });
    defer std.testing.allocator.free(remove_demo_expected);
    try std.testing.expectEqualStrings(remove_demo_expected, remove_demo_response);

    const updated_list_response = try handleFramedRequest(std.testing.allocator, "REQ 65 APPAUTORUNLIST", 512, 256, 512);
    defer std.testing.allocator.free(updated_list_response);
    const updated_list_expected = try std.fmt.allocPrint(std.testing.allocator, "RESP 65 {d}\n{s}", .{ updated_list_payload.len, updated_list_payload });
    defer std.testing.allocator.free(updated_list_expected);
    try std.testing.expectEqualStrings(updated_list_expected, updated_list_response);
}

test "baremetal tool service uninstalls packages and clears app state" {
    resetPersistentStateForTest();

    try package_store.installScriptPackage("demo", "echo uninstall-demo", 1);
    try package_store.installScriptPackage("alias-demo", "echo uninstall-alias", 2);

    const app_run_response = try handleFramedRequest(std.testing.allocator, "REQ 71 APPRUN demo", 512, 256, 512);
    defer std.testing.allocator.free(app_run_response);
    try std.testing.expect(std.mem.startsWith(u8, app_run_response, "RESP 71 "));

    const pkg_delete_response = try handleFramedRequest(std.testing.allocator, "REQ 72 PKGDELETE demo", 512, 256, 512);
    defer std.testing.allocator.free(pkg_delete_response);
    try std.testing.expectEqualStrings("RESP 72 16\nPKGDELETED demo\n", pkg_delete_response);

    const app_delete_response = try handleFramedRequest(std.testing.allocator, "REQ 73 APPDELETE alias-demo", 512, 256, 512);
    defer std.testing.allocator.free(app_delete_response);
    try std.testing.expectEqualStrings("RESP 73 22\nAPPDELETED alias-demo\n", app_delete_response);

    const app_list_response = try handleFramedRequest(std.testing.allocator, "REQ 74 APPLIST", 512, 256, 512);
    defer std.testing.allocator.free(app_list_response);
    try std.testing.expectEqualStrings("RESP 74 0\n", app_list_response);

    const app_state_missing = try handleFramedRequest(std.testing.allocator, "REQ 75 APPSTATE demo", 512, 256, 512);
    defer std.testing.allocator.free(app_state_missing);
    try std.testing.expectEqualStrings("RESP 75 31\nERR APPSTATE: AppStateNotFound\n", app_state_missing);

    const app_history_missing = try handleFramedRequest(std.testing.allocator, "REQ 76 APPHISTORY demo", 512, 256, 512);
    defer std.testing.allocator.free(app_history_missing);
    try std.testing.expectEqualStrings("RESP 76 35\nERR APPHISTORY: AppHistoryNotFound\n", app_history_missing);

    const app_stdout_missing = try handleFramedRequest(std.testing.allocator, "REQ 77 APPSTDOUT demo", 512, 256, 512);
    defer std.testing.allocator.free(app_stdout_missing);
    try std.testing.expectEqualStrings("RESP 77 33\nERR APPSTDOUT: AppStdoutNotFound\n", app_stdout_missing);

    const app_stderr_missing = try handleFramedRequest(std.testing.allocator, "REQ 78 APPSTDERR demo", 512, 256, 512);
    defer std.testing.allocator.free(app_stderr_missing);
    try std.testing.expectEqualStrings("RESP 78 33\nERR APPSTDERR: AppStderrNotFound\n", app_stderr_missing);

    const package_list_response = try handleFramedRequest(std.testing.allocator, "REQ 79 PKGLIST", 512, 256, 512);
    defer std.testing.allocator.free(package_list_response);
    try std.testing.expectEqualStrings("RESP 79 0\n", package_list_response);

    try std.testing.expectError(error.FileNotFound, filesystem.statSummary("/packages/demo"));
    try std.testing.expectError(error.FileNotFound, filesystem.statSummary("/packages/alias-demo"));
    try std.testing.expectError(error.FileNotFound, filesystem.statSummary("/runtime/apps/demo"));
}

test "baremetal tool service handles batched trust requests" {
    resetPersistentStateForTest();

    const batch_request =
        "REQ 51 TRUSTPUT fs55-root 9\nroot-cert\nREQ 52 TRUSTPUT fs55-backup 11\nbackup-cert\nREQ 53 TRUSTSELECT fs55-backup\nREQ 54 TRUSTACTIVE\nREQ 55 TRUSTDELETE fs55-root\nREQ 56 TRUSTLIST";
    const batch_response = try handleFramedRequestBatch(std.testing.allocator, batch_request, 512, 256, 768);
    defer std.testing.allocator.free(batch_response);

    const expected_install = try handleFramedRequest(std.testing.allocator, "REQ 51 TRUSTPUT fs55-root 9\nroot-cert", 512, 256, 512);
    defer std.testing.allocator.free(expected_install);
    const expected_install_backup = try handleFramedRequest(std.testing.allocator, "REQ 52 TRUSTPUT fs55-backup 11\nbackup-cert", 512, 256, 512);
    defer std.testing.allocator.free(expected_install_backup);
    const expected_select = try handleFramedRequest(std.testing.allocator, "REQ 53 TRUSTSELECT fs55-backup", 512, 256, 512);
    defer std.testing.allocator.free(expected_select);
    const expected_active = try handleFramedRequest(std.testing.allocator, "REQ 54 TRUSTACTIVE", 512, 256, 512);
    defer std.testing.allocator.free(expected_active);
    const expected_delete = try handleFramedRequest(std.testing.allocator, "REQ 55 TRUSTDELETE fs55-root", 512, 256, 512);
    defer std.testing.allocator.free(expected_delete);
    const expected_list = try handleFramedRequest(std.testing.allocator, "REQ 56 TRUSTLIST", 512, 256, 512);
    defer std.testing.allocator.free(expected_list);
    const expected = try std.mem.concat(std.testing.allocator, u8, &.{ expected_install, expected_install_backup, expected_select, expected_active, expected_delete, expected_list });
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, batch_response);
}

test "baremetal tool service bridges persisted runtime queries and rpc calls" {
    resetPersistentStateForTest();

    const runtime_write_frame =
        "{\"id\":\"svc-write\",\"method\":\"file.write\",\"params\":{\"sessionId\":\"svc-runtime\",\"path\":\"/runtime/tmp/service-runtime.txt\",\"content\":\"service-runtime-data\"}}";
    const runtime_write_request = try std.fmt.allocPrint(
        std.testing.allocator,
        "REQ 57 RUNTIMECALL {d}\n{s}",
        .{ runtime_write_frame.len, runtime_write_frame },
    );
    defer std.testing.allocator.free(runtime_write_request);

    const runtime_write_response = try handleFramedRequest(std.testing.allocator, runtime_write_request, 512, 256, 768);
    defer std.testing.allocator.free(runtime_write_response);
    try std.testing.expect(std.mem.startsWith(u8, runtime_write_response, "RESP 57 "));
    try std.testing.expect(std.mem.indexOf(u8, runtime_write_response, "\"id\":\"svc-write\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, runtime_write_response, "\"path\":\"/runtime/tmp/service-runtime.txt\"") != null);

    const runtime_exec_frame =
        "{\"id\":\"svc-exec\",\"method\":\"exec.run\",\"params\":{\"sessionId\":\"svc-runtime\",\"command\":\"echo service-runtime\",\"timeoutMs\":1000}}";
    const runtime_exec_request = try std.fmt.allocPrint(
        std.testing.allocator,
        "REQ 58 RUNTIMECALL {d}\n{s}",
        .{ runtime_exec_frame.len, runtime_exec_frame },
    );
    defer std.testing.allocator.free(runtime_exec_request);

    const runtime_exec_response = try handleFramedRequest(std.testing.allocator, runtime_exec_request, 512, 256, 768);
    defer std.testing.allocator.free(runtime_exec_response);
    try std.testing.expect(std.mem.startsWith(u8, runtime_exec_response, "RESP 58 "));
    try std.testing.expect(std.mem.indexOf(u8, runtime_exec_response, "\"id\":\"svc-exec\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, runtime_exec_response, "\"stdout\"") != null);

    const runtime_read_frame =
        "{\"id\":\"svc-read\",\"method\":\"file.read\",\"params\":{\"sessionId\":\"svc-runtime\",\"path\":\"/runtime/tmp/service-runtime.txt\"}}";
    const runtime_read_request = try std.fmt.allocPrint(
        std.testing.allocator,
        "REQ 59 RUNTIMECALL {d}\n{s}",
        .{ runtime_read_frame.len, runtime_read_frame },
    );
    defer std.testing.allocator.free(runtime_read_request);

    const runtime_read_response = try handleFramedRequest(std.testing.allocator, runtime_read_request, 512, 256, 768);
    defer std.testing.allocator.free(runtime_read_response);
    try std.testing.expect(std.mem.startsWith(u8, runtime_read_response, "RESP 59 "));
    try std.testing.expect(std.mem.indexOf(u8, runtime_read_response, "\"content\":\"service-runtime-data\"") != null);

    const runtime_snapshot_response = try handleFramedRequest(std.testing.allocator, "REQ 60 RUNTIMESNAPSHOT", 512, 256, 512);
    defer std.testing.allocator.free(runtime_snapshot_response);
    try std.testing.expect(std.mem.indexOf(u8, runtime_snapshot_response, "state_path=/runtime/state/runtime-state.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, runtime_snapshot_response, "sessions=1") != null);

    const runtime_sessions_response = try handleFramedRequest(std.testing.allocator, "REQ 61 RUNTIMESESSIONS", 512, 256, 512);
    defer std.testing.allocator.free(runtime_sessions_response);
    try std.testing.expectEqualStrings("RESP 61 12\nsvc-runtime\n", runtime_sessions_response);

    const runtime_session_response = try handleFramedRequest(std.testing.allocator, "REQ 62 RUNTIMESESSION svc-runtime", 512, 256, 512);
    defer std.testing.allocator.free(runtime_session_response);
    try std.testing.expect(std.mem.startsWith(u8, runtime_session_response, "RESP 62 "));
    try std.testing.expect(std.mem.indexOf(u8, runtime_session_response, "id=svc-runtime") != null);
    try std.testing.expect(std.mem.indexOf(u8, runtime_session_response, "last_message=file.read:/runtime/tmp/service-runtime.txt") != null);

    const state_payload = try filesystem.readFileAlloc(std.testing.allocator, "/runtime/state/runtime-state.json", 2048);
    defer std.testing.allocator.free(state_payload);
    try std.testing.expect(std.mem.indexOf(u8, state_payload, "svc-runtime") != null);
}

test "baremetal tool service installs default runtime layout and returns manifest" {
    resetPersistentStateForTest();

    const install_response = try handleFramedRequest(std.testing.allocator, "REQ 34 INSTALL", 512, 256, 512);
    defer std.testing.allocator.free(install_response);
    try std.testing.expectEqualStrings("RESP 34 40\nINSTALLED /runtime/install/manifest.txt\n", install_response);

    var manifest_buf: [192]u8 = undefined;
    const expected_manifest = try disk_installer.installManifestForCurrentBackend(manifest_buf[0..]);
    const manifest_response = try handleFramedRequest(std.testing.allocator, "REQ 35 MANIFEST", 512, 256, 512);
    defer std.testing.allocator.free(manifest_response);
    const expected_response = try std.fmt.allocPrint(std.testing.allocator, "RESP 35 {d}\n{s}", .{ expected_manifest.len, expected_manifest });
    defer std.testing.allocator.free(expected_response);
    try std.testing.expectEqualStrings(expected_response, manifest_response);

    const loader_cfg = try filesystem.readFileAlloc(std.testing.allocator, disk_installer.loader_cfg_path, 160);
    defer std.testing.allocator.free(loader_cfg);
    try std.testing.expect(std.mem.indexOf(u8, loader_cfg, "default=bootstrap") != null);
}

test "baremetal tool service handles batched filesystem requests" {
    resetPersistentStateForTest();

    const batch_request = "REQ 11 PUT /tools/cache/tool.txt 4\nedge\nREQ 12 GET /tools/cache/tool.txt\nREQ 13 STAT /tools/cache/tool.txt";
    const batch_response = try handleFramedRequestBatch(std.testing.allocator, batch_request, 256, 256, 512);
    defer std.testing.allocator.free(batch_response);

    const expected_put = try handleFramedRequest(std.testing.allocator, "REQ 11 PUT /tools/cache/tool.txt 4\nedge", 256, 256, 256);
    defer std.testing.allocator.free(expected_put);
    const expected_get = try handleFramedRequest(std.testing.allocator, "REQ 12 GET /tools/cache/tool.txt", 256, 256, 256);
    defer std.testing.allocator.free(expected_get);
    const expected_stat = try handleFramedRequest(std.testing.allocator, "REQ 13 STAT /tools/cache/tool.txt", 256, 256, 256);
    defer std.testing.allocator.free(expected_stat);
    const expected = try std.mem.concat(std.testing.allocator, u8, &.{ expected_put, expected_get, expected_stat });
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, batch_response);
}

test "baremetal tool service handles batched package requests" {
    resetPersistentStateForTest();

    const script = "mkdir /pkg/out\nwrite-file /pkg/out/result.txt pkg-service-data\necho pkg-service-ok";
    const install_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 31 PKG demo {d}\n{s}", .{ script.len, script });
    defer std.testing.allocator.free(install_request);
    const asset_body = "{\"mode\":\"tcp\"}";
    const asset_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 32 PKGPUT demo config/app.json {d}\n{s}", .{ asset_body.len, asset_body });
    defer std.testing.allocator.free(asset_request);
    const batch_request = try std.mem.concat(std.testing.allocator, u8, &.{
        install_request,
        "\n",
        asset_request,
        "\nREQ 33 PKGLS demo\nREQ 34 PKGGET demo config/app.json\nREQ 35 PKGVERIFY demo\nREQ 36 PKGLIST\nREQ 37 PKGINFO demo\nREQ 38 PKGAPP demo\nREQ 39 PKGDISPLAY demo 1280 720\nREQ 40 PKGRUN demo\nREQ 41 DISPLAYSET 800 600\nREQ 42 DISPLAYINFO\nREQ 43 DISPLAYMODES",
    });
    defer std.testing.allocator.free(batch_request);
    const batch_response = try handleFramedRequestBatch(std.testing.allocator, batch_request, 512, 256, 2048);
    defer std.testing.allocator.free(batch_response);

    const expected_install = try handleFramedRequest(std.testing.allocator, install_request, 512, 256, 512);
    defer std.testing.allocator.free(expected_install);
    const expected_asset = try handleFramedRequest(std.testing.allocator, asset_request, 512, 256, 512);
    defer std.testing.allocator.free(expected_asset);
    const expected_asset_list = try handleFramedRequest(std.testing.allocator, "REQ 33 PKGLS demo", 512, 256, 512);
    defer std.testing.allocator.free(expected_asset_list);
    const expected_asset_get = try handleFramedRequest(std.testing.allocator, "REQ 34 PKGGET demo config/app.json", 512, 256, 512);
    defer std.testing.allocator.free(expected_asset_get);
    const expected_verify = try handleFramedRequest(std.testing.allocator, "REQ 35 PKGVERIFY demo", 512, 256, 512);
    defer std.testing.allocator.free(expected_verify);
    const expected_list = try handleFramedRequest(std.testing.allocator, "REQ 36 PKGLIST", 512, 256, 512);
    defer std.testing.allocator.free(expected_list);
    const expected_info = try handleFramedRequest(std.testing.allocator, "REQ 37 PKGINFO demo", 512, 256, 512);
    defer std.testing.allocator.free(expected_info);
    const expected_app = try handleFramedRequest(std.testing.allocator, "REQ 38 PKGAPP demo", 512, 256, 512);
    defer std.testing.allocator.free(expected_app);
    const expected_pkg_display = try handleFramedRequest(std.testing.allocator, "REQ 39 PKGDISPLAY demo 1280 720", 512, 256, 512);
    defer std.testing.allocator.free(expected_pkg_display);
    const expected_run = try handleFramedRequest(std.testing.allocator, "REQ 40 PKGRUN demo", 512, 256, 512);
    defer std.testing.allocator.free(expected_run);
    const expected_display_set = try handleFramedRequest(std.testing.allocator, "REQ 41 DISPLAYSET 800 600", 512, 256, 512);
    defer std.testing.allocator.free(expected_display_set);
    const expected_display_info = try handleFramedRequest(std.testing.allocator, "REQ 42 DISPLAYINFO", 512, 256, 512);
    defer std.testing.allocator.free(expected_display_info);
    const expected_display_modes = try handleFramedRequest(std.testing.allocator, "REQ 43 DISPLAYMODES", 512, 256, 512);
    defer std.testing.allocator.free(expected_display_modes);
    const expected = try std.mem.concat(std.testing.allocator, u8, &.{ expected_install, expected_asset, expected_asset_list, expected_asset_get, expected_verify, expected_list, expected_info, expected_app, expected_pkg_display, expected_run, expected_display_set, expected_display_info, expected_display_modes });
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, batch_response);
}

test "baremetal tool service rejects invalid mid-batch frames" {
    resetPersistentStateForTest();
    try filesystem.createDirPath("/tools/cache");
    try filesystem.writeFile("/tools/cache/tool.txt", "edge", 0);

    try std.testing.expectError(
        error.InvalidFrame,
        handleFramedRequestBatch(
            std.testing.allocator,
            "REQ 11 GET /tools/cache/tool.txt\nREQ nope GET /tools/cache/tool.txt",
            256,
            256,
            512,
        ),
    );
}
