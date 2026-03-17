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
const max_history_bytes: usize = 1024;

pub const Error = filesystem.Error || package_store.Error || std.mem.Allocator.Error || error{
    AppStateNotFound,
    AppHistoryNotFound,
    AppStdoutNotFound,
    AppStderrNotFound,
    ResponseTooLarge,
};

pub fn listAppsAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    return package_store.listPackagesAlloc(allocator, max_bytes);
}

pub fn infoAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try package_store.loadLaunchProfile(name, &entrypoint_buf);

    var state_path_buf: [filesystem.max_path_len]u8 = undefined;
    var history_path_buf: [filesystem.max_path_len]u8 = undefined;
    var stdout_path_buf: [filesystem.max_path_len]u8 = undefined;
    var stderr_path_buf: [filesystem.max_path_len]u8 = undefined;
    const state_path = try statePath(name, &state_path_buf);
    const history_path = try historyPath(name, &history_path_buf);
    const stdout_path = try stdoutPath(name, &stdout_path_buf);
    const stderr_path = try stderrPath(name, &stderr_path_buf);
    const trust_bundle = profile.trustBundle();
    const response = try std.fmt.allocPrint(
        allocator,
        "name={s}\nentrypoint={s}\ndisplay_width={d}\ndisplay_height={d}\nconnector={s}\ntrust_bundle={s}\nstate_path={s}\nhistory_path={s}\nstdout_path={s}\nstderr_path={s}\n",
        .{
            name,
            profile.entrypoint,
            profile.display_width,
            profile.display_height,
            package_store.connectorNameFromType(profile.connector_type),
            trust_bundle,
            state_path,
            history_path,
            stdout_path,
            stderr_path,
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

pub fn historyAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var history_path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try historyPath(name, &history_path_buf);
    return filesystem.readFileAlloc(allocator, path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => error.AppHistoryNotFound,
        else => err,
    };
}

pub fn stdoutAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var stdout_path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try stdoutPath(name, &stdout_path_buf);
    return filesystem.readFileAlloc(allocator, path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => error.AppStdoutNotFound,
        else => err,
    };
}

pub fn stderrAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var stderr_path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try stderrPath(name, &stderr_path_buf);
    return filesystem.readFileAlloc(allocator, path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => error.AppStderrNotFound,
        else => err,
    };
}

pub fn writeLastRun(
    name: []const u8,
    profile: package_store.LaunchProfile,
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
    tick: u64,
) Error!void {
    var app_dir_buf: [filesystem.max_path_len]u8 = undefined;
    var state_path_buf: [filesystem.max_path_len]u8 = undefined;
    var history_path_buf: [filesystem.max_path_len]u8 = undefined;
    var stdout_path_buf: [filesystem.max_path_len]u8 = undefined;
    var stderr_path_buf: [filesystem.max_path_len]u8 = undefined;
    const app_dir = try appDirPath(name, &app_dir_buf);
    const state_path = try statePath(name, &state_path_buf);
    const history_path = try historyPath(name, &history_path_buf);
    const stdout_path = try stdoutPath(name, &stdout_path_buf);
    const stderr_path = try stderrPath(name, &stderr_path_buf);
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
            stdout.len,
            stderr.len,
            profile.display_width,
            profile.display_height,
            package_store.connectorNameFromType(profile.connector_type),
            package_store.connectorNameFromType(output.connector_type),
            trust_bundle,
        },
    ) catch return error.InvalidPath;
    try filesystem.writeFile(state_path, rendered, tick);
    try filesystem.writeFile(stdout_path, stdout, tick);
    try filesystem.writeFile(stderr_path, stderr, tick);

    var history_line_buf: [256]u8 = undefined;
    const history_line = std.fmt.bufPrint(
        &history_line_buf,
        "tick={d} name={s} exit_code={d} stdout_bytes={d} stderr_bytes={d} display={d}x{d} requested_connector={s} actual_connector={s} trust_bundle={s}\n",
        .{
            tick,
            name,
            exit_code,
            stdout.len,
            stderr.len,
            profile.display_width,
            profile.display_height,
            package_store.connectorNameFromType(profile.connector_type),
            package_store.connectorNameFromType(output.connector_type),
            trust_bundle,
        },
    ) catch return error.InvalidPath;
    try appendHistoryLine(history_path, history_line, tick);
}

pub fn deleteState(name: []const u8, tick: u64) Error!void {
    var app_dir_buf: [filesystem.max_path_len]u8 = undefined;
    const app_dir = try appDirPath(name, &app_dir_buf);
    filesystem.deleteTree(app_dir, tick) catch |err| switch (err) {
        error.FileNotFound => return error.AppStateNotFound,
        else => return err,
    };
}

pub fn uninstallApp(name: []const u8, tick: u64) Error!void {
    try package_store.deletePackage(name, tick);
    deleteState(name, tick) catch |err| switch (err) {
        error.AppStateNotFound => {},
        else => return err,
    };
}

pub fn statePath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try package_store.validatePackageName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/last_run.txt", .{ root_dir, name }) catch error.InvalidPath;
}

pub fn historyPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try package_store.validatePackageName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/history.log", .{ root_dir, name }) catch error.InvalidPath;
}

pub fn stdoutPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try package_store.validatePackageName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/stdout.log", .{ root_dir, name }) catch error.InvalidPath;
}

pub fn stderrPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try package_store.validatePackageName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/stderr.log", .{ root_dir, name }) catch error.InvalidPath;
}

fn appDirPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try package_store.validatePackageName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}", .{ root_dir, name }) catch error.InvalidPath;
}

fn appendHistoryLine(path: []const u8, line: []const u8, tick: u64) Error!void {
    var existing_storage: [max_history_bytes]u8 = undefined;
    var existing_fba = std.heap.FixedBufferAllocator.init(&existing_storage);
    const existing = filesystem.readFileAlloc(existing_fba.allocator(), path, max_history_bytes) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };

    var combined: [max_history_bytes + 256]u8 = undefined;
    var combined_len: usize = 0;
    if (existing) |bytes| {
        @memcpy(combined[0..bytes.len], bytes);
        combined_len = bytes.len;
    }
    @memcpy(combined[combined_len .. combined_len + line.len], line);
    combined_len += line.len;

    const bounded = boundHistoryTail(combined[0..combined_len]);
    try filesystem.writeFile(path, bounded, tick);
}

fn boundHistoryTail(bytes: []const u8) []const u8 {
    if (bytes.len <= max_history_bytes) return bytes;

    const start = bytes.len - max_history_bytes;
    const tail = bytes[start..];
    const newline_index = std.mem.indexOfScalar(u8, tail, '\n') orelse return tail;
    if (newline_index + 1 >= tail.len) return tail;
    return tail[newline_index + 1 ..];
}

test "app runtime reports package app info and persists last run state on ram disk" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try package_store.installScriptPackage("demo", "echo app-runtime-ok", 5);
    try package_store.configureConnectorType("demo", abi.display_connector_virtual, 6);

    const info = try infoAlloc(std.testing.allocator, "demo", 384);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "/runtime/apps/demo/last_run.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "/runtime/apps/demo/history.log") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "/runtime/apps/demo/stdout.log") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "/runtime/apps/demo/stderr.log") != null);

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try package_store.loadLaunchProfile("demo", &entrypoint_buf);
    writeLastRun("demo", profile, 0, "app-runtime-ok\n", "", 7) catch |err| return err;

    const state = try stateAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(state);
    try std.testing.expect(std.mem.indexOf(u8, state, "exit_code=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, state, "requested_connector=virtual") != null);

    const history = try historyAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(history);
    try std.testing.expect(std.mem.indexOf(u8, history, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, history, "exit_code=0") != null);

    const stdout = try stdoutAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(stdout);
    try std.testing.expectEqualStrings("app-runtime-ok\n", stdout);

    const stderr = try stderrAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
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
    try writeLastRun("persisted", profile, 0, "persisted-runtime\n", "", 14);
    try std.testing.expectEqual(@as(u32, 2048), ata_pio_disk.logicalBaseLba());

    filesystem.resetForTest();

    const state = try stateAlloc(std.testing.allocator, "persisted", 256);
    defer std.testing.allocator.free(state);
    try std.testing.expect(std.mem.indexOf(u8, state, "trust_bundle=app-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, state, "requested_connector=virtual") != null);

    const history = try historyAlloc(std.testing.allocator, "persisted", 256);
    defer std.testing.allocator.free(history);
    try std.testing.expect(std.mem.indexOf(u8, history, "name=persisted") != null);
    try std.testing.expect(std.mem.indexOf(u8, history, "trust_bundle=app-root") != null);

    const stdout = try stdoutAlloc(std.testing.allocator, "persisted", 256);
    defer std.testing.allocator.free(stdout);
    try std.testing.expectEqualStrings("persisted-runtime\n", stdout);

    const stderr = try stderrAlloc(std.testing.allocator, "persisted", 256);
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

test "app runtime uninstall removes package tree and persisted state" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try package_store.installScriptPackage("demo", "echo app-runtime-delete", 10);
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try package_store.loadLaunchProfile("demo", &entrypoint_buf);
    try writeLastRun("demo", profile, 0, "app-delete\n", "", 11);

    try uninstallApp("demo", 12);
    try std.testing.expectError(error.PackageNotFound, package_store.loadLaunchProfile("demo", &entrypoint_buf));
    try std.testing.expectError(error.AppStateNotFound, stateAlloc(std.testing.allocator, "demo", 256));
    try std.testing.expectError(error.AppHistoryNotFound, historyAlloc(std.testing.allocator, "demo", 256));
    try std.testing.expectError(error.AppStdoutNotFound, stdoutAlloc(std.testing.allocator, "demo", 256));
    try std.testing.expectError(error.AppStderrNotFound, stderrAlloc(std.testing.allocator, "demo", 256));

    const packages_listing = try filesystem.listDirectoryAlloc(std.testing.allocator, "/packages", 64);
    defer std.testing.allocator.free(packages_listing);
    try std.testing.expectEqualStrings("", packages_listing);
}
