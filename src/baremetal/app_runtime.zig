// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");
const display_output = @import("display_output.zig");
const filesystem = @import("filesystem.zig");
const package_store = @import("package_store.zig");
const storage_backend = @import("storage_backend.zig");
const ata_pio_disk = @import("ata_pio_disk.zig");
const trust_store = @import("trust_store.zig");

const root_dir = "/runtime/apps";

pub const Error = filesystem.Error || package_store.Error || std.mem.Allocator.Error || error{
    AppStateNotFound,
    ResponseTooLarge,
};

pub fn listAppsAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    return package_store.listPackagesAlloc(allocator, max_bytes);
}

pub fn infoAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try package_store.loadLaunchProfile(name, &entrypoint_buf);

    var state_path_buf: [filesystem.max_path_len]u8 = undefined;
    const state_path = try statePath(name, &state_path_buf);
    const trust_bundle = profile.trustBundle();
    const response = try std.fmt.allocPrint(
        allocator,
        "name={s}\nentrypoint={s}\ndisplay_width={d}\ndisplay_height={d}\nconnector={s}\ntrust_bundle={s}\nstate_path={s}\n",
        .{
            name,
            profile.entrypoint,
            profile.display_width,
            profile.display_height,
            package_store.connectorNameFromType(profile.connector_type),
            trust_bundle,
            state_path,
        },
    );
    errdefer allocator.free(response);
    if (response.len > max_bytes) return error.ResponseTooLarge;
    return response;
}

pub fn stateAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var state_path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try statePath(name, &state_path_buf);
    return filesystem.readFileAlloc(allocator, path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => error.AppStateNotFound,
        else => err,
    };
}

pub fn writeLastRun(
    name: []const u8,
    profile: package_store.LaunchProfile,
    exit_code: u8,
    stdout_bytes: usize,
    stderr_bytes: usize,
    tick: u64,
) Error!void {
    var app_dir_buf: [filesystem.max_path_len]u8 = undefined;
    var state_path_buf: [filesystem.max_path_len]u8 = undefined;
    const app_dir = try appDirPath(name, &app_dir_buf);
    const path = try statePath(name, &state_path_buf);
    try filesystem.createDirPath(root_dir);
    try filesystem.createDirPath(app_dir);

    const output = display_output.statePtr();
    const trust_bundle = profile.trustBundle();
    var body: [384]u8 = undefined;
    const rendered = std.fmt.bufPrint(
        &body,
        "name={s}\nexit_code={d}\nstdout_bytes={d}\nstderr_bytes={d}\ndisplay_width={d}\ndisplay_height={d}\nrequested_connector={s}\nactual_connector={s}\ntrust_bundle={s}\n",
        .{
            name,
            exit_code,
            stdout_bytes,
            stderr_bytes,
            profile.display_width,
            profile.display_height,
            package_store.connectorNameFromType(profile.connector_type),
            package_store.connectorNameFromType(output.connector_type),
            trust_bundle,
        },
    ) catch return error.InvalidPath;
    try filesystem.writeFile(path, rendered, tick);
}

pub fn statePath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try package_store.validatePackageName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/last_run.txt", .{ root_dir, name }) catch error.InvalidPath;
}

fn appDirPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try package_store.validatePackageName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}", .{ root_dir, name }) catch error.InvalidPath;
}

test "app runtime reports package app info and persists last run state on ram disk" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try package_store.installScriptPackage("demo", "echo app-runtime-ok", 5);
    try package_store.configureConnectorType("demo", abi.display_connector_virtual, 6);

    const info = try infoAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "/runtime/apps/demo/last_run.txt") != null);

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try package_store.loadLaunchProfile("demo", &entrypoint_buf);
    writeLastRun("demo", profile, 0, 32, 0, 7) catch |err| return err;

    const state = try stateAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(state);
    try std.testing.expect(std.mem.indexOf(u8, state, "exit_code=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, state, "requested_connector=virtual") != null);
}

test "app runtime state persists on ata-backed storage" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try trust_store.installBundle("app-root", "root-cert", 10);
    try package_store.installScriptPackage("persisted", "echo persisted-runtime", 11);
    try package_store.configureTrustBundle("persisted", "app-root", 12);
    try package_store.configureConnectorType("persisted", abi.display_connector_virtual, 13);

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try package_store.loadLaunchProfile("persisted", &entrypoint_buf);
    try writeLastRun("persisted", profile, 0, 48, 0, 14);
    try std.testing.expectEqual(@as(u32, 2048), ata_pio_disk.logicalBaseLba());

    filesystem.resetForTest();

    const state = try stateAlloc(std.testing.allocator, "persisted", 256);
    defer std.testing.allocator.free(state);
    try std.testing.expect(std.mem.indexOf(u8, state, "trust_bundle=app-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, state, "requested_connector=virtual") != null);
}
