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
const suite_root_dir = "/runtime/app-suites";
const max_history_bytes: usize = 1024;
const max_autorun_bytes: usize = 1024;
const max_plan_bytes: usize = 512;
const max_suite_bytes: usize = 1024;
const max_suite_entries: usize = 8;
const autorun_list_path = "/runtime/apps/autorun.txt";

pub const Error = filesystem.Error || package_store.Error || std.mem.Allocator.Error || error{
    AppStateNotFound,
    AppHistoryNotFound,
    AppStdoutNotFound,
    AppStderrNotFound,
    AppAutorunEntryNotFound,
    AppPlanNotFound,
    AppActivePlanNotSet,
    AppSuiteNotFound,
    InvalidAppPlanName,
    InvalidAppPlan,
    InvalidAppSuiteName,
    InvalidAppSuite,
    AppSuiteEmpty,
    ResponseTooLarge,
};

const AppPlan = struct {
    package_name_len: u8 = 0,
    package_name_storage: [package_store.max_name_len]u8 = [_]u8{0} ** package_store.max_name_len,
    plan_name_len: u8 = 0,
    plan_name_storage: [package_store.max_release_len]u8 = [_]u8{0} ** package_store.max_release_len,
    release_name_len: u8 = 0,
    release_name_storage: [package_store.max_release_len]u8 = [_]u8{0} ** package_store.max_release_len,
    trust_bundle_len: u8 = 0,
    trust_bundle_storage: [trust_store.max_name_len]u8 = [_]u8{0} ** trust_store.max_name_len,
    display_width: u16 = package_store.default_display_width,
    display_height: u16 = package_store.default_display_height,
    connector_type: u8 = package_store.default_connector_type,
    autorun: bool = false,

    fn packageName(self: *const @This()) []const u8 {
        return self.package_name_storage[0..self.package_name_len];
    }

    fn planName(self: *const @This()) []const u8 {
        return self.plan_name_storage[0..self.plan_name_len];
    }

    fn releaseName(self: *const @This()) []const u8 {
        return self.release_name_storage[0..self.release_name_len];
    }

    fn trustBundle(self: *const @This()) []const u8 {
        return self.trust_bundle_storage[0..self.trust_bundle_len];
    }
};

const AppSuiteEntry = struct {
    package_name_len: u8 = 0,
    package_name_storage: [package_store.max_name_len]u8 = [_]u8{0} ** package_store.max_name_len,
    plan_name_len: u8 = 0,
    plan_name_storage: [package_store.max_release_len]u8 = [_]u8{0} ** package_store.max_release_len,

    fn packageName(self: *const @This()) []const u8 {
        return self.package_name_storage[0..self.package_name_len];
    }

    fn planName(self: *const @This()) []const u8 {
        return self.plan_name_storage[0..self.plan_name_len];
    }
};

const AppSuite = struct {
    suite_name_len: u8 = 0,
    suite_name_storage: [package_store.max_release_len]u8 = [_]u8{0} ** package_store.max_release_len,
    entry_count: u8 = 0,
    entries: [max_suite_entries]AppSuiteEntry = [_]AppSuiteEntry{.{}} ** max_suite_entries,

    fn suiteName(self: *const @This()) []const u8 {
        return self.suite_name_storage[0..self.suite_name_len];
    }
};

pub fn listAppsAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    return package_store.listPackagesAlloc(allocator, max_bytes);
}

pub fn autorunListAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    return readAutorunListAlloc(allocator, max_bytes);
}

pub fn addAutorun(name: []const u8, tick: u64) Error!void {
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    _ = try package_store.loadLaunchProfile(name, &entrypoint_buf);

    var existing_scratch: [max_autorun_bytes]u8 = undefined;
    const existing = try loadAutorunListScratch(&existing_scratch);
    if (containsAutorunName(existing, name)) return;

    var rendered: [max_autorun_bytes + package_store.max_name_len + 2]u8 = undefined;
    var len: usize = 0;
    if (existing.len != 0) {
        @memcpy(rendered[0..existing.len], existing);
        len = existing.len;
        if (rendered[len - 1] != '\n') {
            rendered[len] = '\n';
            len += 1;
        }
    }
    @memcpy(rendered[len .. len + name.len], name);
    len += name.len;
    rendered[len] = '\n';
    len += 1;

    try filesystem.createDirPath(root_dir);
    try filesystem.writeFile(autorun_list_path, rendered[0..len], tick);
}

pub fn removeAutorun(name: []const u8, tick: u64) Error!void {
    try package_store.validatePackageName(name);
    var existing_scratch: [max_autorun_bytes]u8 = undefined;
    const existing = try loadAutorunListScratch(&existing_scratch);

    var rendered: [max_autorun_bytes]u8 = undefined;
    var len: usize = 0;
    var found = false;
    var lines = std.mem.splitScalar(u8, existing, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, name)) {
            found = true;
            continue;
        }
        @memcpy(rendered[len .. len + line.len], line);
        len += line.len;
        rendered[len] = '\n';
        len += 1;
    }

    if (!found) return error.AppAutorunEntryNotFound;

    try filesystem.createDirPath(root_dir);
    try filesystem.writeFile(autorun_list_path, rendered[0..len], tick);
}

pub fn planListAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    try ensurePackageInstalled(name);

    var plans_dir_buf: [filesystem.max_path_len]u8 = undefined;
    const plans_dir = try plansDirPath(name, &plans_dir_buf);
    const raw_listing = filesystem.listDirectoryAlloc(allocator, plans_dir, max_plan_bytes) catch |err| switch (err) {
        error.FileNotFound => return allocator.alloc(u8, 0),
        else => return err,
    };
    defer allocator.free(raw_listing);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, raw_listing, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "file ")) continue;
        const file_part = std.mem.splitScalar(u8, line["file ".len..], ' ');
        var part_iter = file_part;
        const file_name = part_iter.next() orelse continue;
        if (!std.mem.endsWith(u8, file_name, ".txt")) continue;
        const plan_name = file_name[0 .. file_name.len - ".txt".len];
        if (plan_name.len == 0) continue;
        if (out.items.len + plan_name.len + 1 > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, plan_name);
        try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

pub fn planInfoAlloc(allocator: std.mem.Allocator, name: []const u8, plan_name: []const u8, max_bytes: usize) Error![]u8 {
    const plan = try loadPlan(name, plan_name);

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try planPath(name, plan_name, &path_buf);
    return renderPlanAlloc(allocator, plan, path, null, max_bytes);
}

pub fn activePlanInfoAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    const active_plan_name = try activePlanNameAlloc(allocator, name, package_store.max_release_len);
    defer allocator.free(active_plan_name);

    const plan = try loadPlan(name, active_plan_name);
    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try planPath(name, active_plan_name, &path_buf);
    return renderPlanAlloc(allocator, plan, path, active_plan_name, max_bytes);
}

pub fn savePlan(
    name: []const u8,
    plan_name: []const u8,
    release_name: []const u8,
    trust_bundle: []const u8,
    connector_type: u8,
    display_width: u16,
    display_height: u16,
    autorun: bool,
    tick: u64,
) Error!void {
    try ensurePackageInstalled(name);
    try validatePlanName(plan_name);
    try validatePlanInputs(name, release_name, trust_bundle, connector_type, display_width, display_height);

    var app_dir_buf: [filesystem.max_path_len]u8 = undefined;
    var plans_dir_buf: [filesystem.max_path_len]u8 = undefined;
    var plan_path_buf: [filesystem.max_path_len]u8 = undefined;
    const app_dir = try appDirPath(name, &app_dir_buf);
    const plans_dir = try plansDirPath(name, &plans_dir_buf);
    const path = try planPath(name, plan_name, &plan_path_buf);

    try filesystem.createDirPath(root_dir);
    try filesystem.createDirPath(app_dir);
    try filesystem.createDirPath(plans_dir);

    var body: [256]u8 = undefined;
    const rendered = std.fmt.bufPrint(
        &body,
        "package={s}\nplan={s}\nrelease={s}\ntrust_bundle={s}\nconnector={s}\ndisplay_width={d}\ndisplay_height={d}\nautorun={d}\n",
        .{
            name,
            plan_name,
            if (release_name.len == 0) "none" else release_name,
            if (trust_bundle.len == 0) "none" else trust_bundle,
            package_store.connectorNameFromType(connector_type),
            display_width,
            display_height,
            @intFromBool(autorun),
        },
    ) catch return error.InvalidPath;
    try filesystem.writeFile(path, rendered, tick);
}

pub fn applyPlan(name: []const u8, plan_name: []const u8, tick: u64) Error!void {
    const plan = try loadPlan(name, plan_name);

    if (plan.releaseName().len != 0) {
        try package_store.activatePackageRelease(name, plan.releaseName(), tick);
    }
    try package_store.configureDisplayMode(name, plan.display_width, plan.display_height, tick);
    try package_store.configureConnectorType(name, plan.connector_type, tick);
    try package_store.configureTrustBundle(name, plan.trustBundle(), tick);
    if (plan.autorun) {
        try addAutorun(name, tick);
    } else {
        removeAutorun(name, tick) catch |err| switch (err) {
            error.AppAutorunEntryNotFound => {},
            else => return err,
        };
    }

    try setActivePlan(name, plan_name, tick);
}

pub fn deletePlan(name: []const u8, plan_name: []const u8, tick: u64) Error!void {
    try ensurePackageInstalled(name);
    try validatePlanName(plan_name);

    var plan_path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try planPath(name, plan_name, &plan_path_buf);
    filesystem.deleteFile(path, tick) catch |err| switch (err) {
        error.FileNotFound => return error.AppPlanNotFound,
        else => return err,
    };

    var active_name_buf: [package_store.max_release_len]u8 = undefined;
    const active_name = loadActivePlanNameScratch(name, &active_name_buf) catch |err| switch (err) {
        error.AppActivePlanNotSet => null,
        else => return err,
    };
    if (active_name) |selected| {
        if (std.mem.eql(u8, selected, plan_name)) {
            clearActivePlan(name, tick) catch |err| switch (err) {
                error.AppActivePlanNotSet => {},
                else => return err,
            };
        }
    }
}

pub fn suiteListAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const raw_listing = filesystem.listDirectoryAlloc(allocator, suite_root_dir, max_suite_bytes) catch |err| switch (err) {
        error.FileNotFound => return allocator.alloc(u8, 0),
        else => return err,
    };
    defer allocator.free(raw_listing);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, raw_listing, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "file ")) continue;
        var parts = std.mem.splitScalar(u8, line["file ".len..], ' ');
        const file_name = parts.next() orelse continue;
        if (!std.mem.endsWith(u8, file_name, ".txt")) continue;
        const suite_name = file_name[0 .. file_name.len - ".txt".len];
        if (suite_name.len == 0) continue;
        if (out.items.len + suite_name.len + 1 > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, suite_name);
        try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

pub fn suiteEntriesAlloc(allocator: std.mem.Allocator, suite_name: []const u8, max_bytes: usize) Error![]u8 {
    const suite = try loadSuite(suite_name);
    return renderSuiteEntriesAlloc(allocator, suite, max_bytes);
}

pub fn suiteInfoAlloc(allocator: std.mem.Allocator, suite_name: []const u8, max_bytes: usize) Error![]u8 {
    const suite = try loadSuite(suite_name);
    var path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try suitePath(suite_name, &path_buf);
    return renderSuiteInfoAlloc(allocator, suite, path, max_bytes);
}

pub fn saveSuite(suite_name: []const u8, entries_spec: []const u8, tick: u64) Error!void {
    try validateSuiteName(suite_name);

    const suite = try parseSuiteEntriesSpec(suite_name, entries_spec);
    if (suite.entry_count == 0) return error.AppSuiteEmpty;

    var suite_path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try suitePath(suite_name, &suite_path_buf);
    try filesystem.createDirPath(suite_root_dir);

    var body: [max_suite_bytes]u8 = undefined;
    var used: usize = 0;
    const suite_line = std.fmt.bufPrint(body[used..], "suite={s}\n", .{suite.suiteName()}) catch |err| switch (err) {
        error.NoSpaceLeft => return error.ResponseTooLarge,
    };
    used += suite_line.len;
    var entry_index: usize = 0;
    while (entry_index < suite.entry_count) : (entry_index += 1) {
        const entry = suite.entries[entry_index];
        const entry_line = std.fmt.bufPrint(body[used..], "entry={s}:{s}\n", .{ entry.packageName(), entry.planName() }) catch |err| switch (err) {
            error.NoSpaceLeft => return error.ResponseTooLarge,
        };
        used += entry_line.len;
    }
    try filesystem.writeFile(path, body[0..used], tick);
}

pub fn applySuite(suite_name: []const u8, tick: u64) Error!void {
    const suite = try loadSuite(suite_name);
    var entry_index: usize = 0;
    while (entry_index < suite.entry_count) : (entry_index += 1) {
        const entry = suite.entries[entry_index];
        try applyPlan(entry.packageName(), entry.planName(), tick);
    }
}

pub fn deleteSuite(suite_name: []const u8, tick: u64) Error!void {
    var suite_path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try suitePath(suite_name, &suite_path_buf);
    filesystem.deleteFile(path, tick) catch |err| switch (err) {
        error.FileNotFound => return error.AppSuiteNotFound,
        else => return err,
    };
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

fn plansDirPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try package_store.validatePackageName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/plans", .{ root_dir, name }) catch error.InvalidPath;
}

fn planPath(name: []const u8, plan_name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try package_store.validatePackageName(name);
    try validatePlanName(plan_name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/plans/{s}.txt", .{ root_dir, name, plan_name }) catch error.InvalidPath;
}

fn activePlanPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try package_store.validatePackageName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/active_plan.txt", .{ root_dir, name }) catch error.InvalidPath;
}

fn ensurePackageInstalled(name: []const u8) Error!void {
    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    _ = try package_store.loadLaunchProfile(name, &entrypoint_buf);
}

fn validatePlanName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > package_store.max_release_len) return error.InvalidAppPlanName;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
        return error.InvalidAppPlanName;
    }
}

fn validatePlanInputs(
    package_name: []const u8,
    release_name: []const u8,
    trust_bundle: []const u8,
    connector_type: u8,
    display_width: u16,
    display_height: u16,
) Error!void {
    if (display_width == 0 or display_height == 0) return error.InvalidAppPlan;
    if (release_name.len != 0 and !try package_store.releaseExistsAlloc(package_name, release_name)) {
        return error.PackageReleaseNotFound;
    }
    if (trust_bundle.len != 0 and !try trust_store.bundleExists(trust_bundle)) {
        return error.TrustBundleNotFound;
    }
    _ = package_store.parseConnectorType(package_store.connectorNameFromType(connector_type)) catch return error.InvalidDisplayConnector;
}

fn validateSuiteName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > package_store.max_release_len) return error.InvalidAppSuiteName;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
        return error.InvalidAppSuiteName;
    }
}

fn setActivePlan(name: []const u8, plan_name: []const u8, tick: u64) Error!void {
    var active_path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try activePlanPath(name, &active_path_buf);
    try filesystem.writeFile(path, plan_name, tick);
}

fn clearActivePlan(name: []const u8, tick: u64) Error!void {
    var active_path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try activePlanPath(name, &active_path_buf);
    filesystem.deleteFile(path, tick) catch |err| switch (err) {
        error.FileNotFound => return error.AppActivePlanNotSet,
        else => return err,
    };
}

fn suitePath(suite_name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateSuiteName(suite_name);
    return std.fmt.bufPrint(buffer, "{s}/{s}.txt", .{ suite_root_dir, suite_name }) catch error.InvalidPath;
}

fn activePlanNameAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var active_path_buf: [filesystem.max_path_len]u8 = undefined;
    const path = try activePlanPath(name, &active_path_buf);
    return filesystem.readFileAlloc(allocator, path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => error.AppActivePlanNotSet,
        else => err,
    };
}

fn loadActivePlanNameScratch(name: []const u8, buffer: *[package_store.max_release_len]u8) Error!?[]const u8 {
    var fba = std.heap.FixedBufferAllocator.init(buffer);
    const active_name = activePlanNameAlloc(fba.allocator(), name, buffer.len) catch |err| switch (err) {
        error.AppActivePlanNotSet => return null,
        else => return err,
    };
    try validatePlanName(active_name);
    return active_name;
}

fn initPlan(package_name: []const u8, plan_name: []const u8) Error!AppPlan {
    var plan = AppPlan{};
    try copyPlanComponent(plan.package_name_storage[0..], &plan.package_name_len, package_name, error.InvalidPackageName);
    try copyPlanComponent(plan.plan_name_storage[0..], &plan.plan_name_len, plan_name, error.InvalidAppPlanName);
    return plan;
}

fn initSuite(suite_name: []const u8) Error!AppSuite {
    var suite = AppSuite{};
    try copyPlanComponent(suite.suite_name_storage[0..], &suite.suite_name_len, suite_name, error.InvalidAppSuiteName);
    return suite;
}

fn loadSuite(suite_name: []const u8) Error!AppSuite {
    try validateSuiteName(suite_name);

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    var body_storage: [max_suite_bytes]u8 = undefined;
    const path = try suitePath(suite_name, &path_buf);
    var fba = std.heap.FixedBufferAllocator.init(&body_storage);
    const body = filesystem.readFileAlloc(fba.allocator(), path, body_storage.len) catch |err| switch (err) {
        error.FileNotFound => return error.AppSuiteNotFound,
        else => return err,
    };
    return parseSuite(suite_name, body);
}

fn parseSuiteEntriesSpec(suite_name: []const u8, entries_spec: []const u8) Error!AppSuite {
    var suite = try initSuite(suite_name);
    var tokens = std.mem.tokenizeAny(u8, entries_spec, " \t\r\n");
    while (tokens.next()) |token| {
        if (suite.entry_count >= max_suite_entries) return error.InvalidAppSuite;
        const entry = try parseSuiteEntryValue(token);
        _ = try loadPlan(entry.packageName(), entry.planName());
        suite.entries[suite.entry_count] = entry;
        suite.entry_count += 1;
    }
    if (suite.entry_count == 0) return error.AppSuiteEmpty;
    return suite;
}

fn parseSuite(suite_name: []const u8, body: []const u8) Error!AppSuite {
    var suite = try initSuite(suite_name);
    var saw_suite_name = false;

    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        if (std.mem.startsWith(u8, line, "suite=")) {
            if (!std.mem.eql(u8, line["suite=".len..], suite_name)) return error.InvalidAppSuite;
            saw_suite_name = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "entry=")) {
            if (suite.entry_count >= max_suite_entries) return error.InvalidAppSuite;
            suite.entries[suite.entry_count] = try parseSuiteEntryValue(line["entry=".len..]);
            suite.entry_count += 1;
            continue;
        }
        return error.InvalidAppSuite;
    }

    if (!saw_suite_name or suite.entry_count == 0) return error.InvalidAppSuite;
    return suite;
}

fn parseSuiteEntryValue(value: []const u8) Error!AppSuiteEntry {
    const separator_index = std.mem.indexOfScalar(u8, value, ':') orelse return error.InvalidAppSuite;
    const package_name = value[0..separator_index];
    const plan_name = value[separator_index + 1 ..];
    if (package_name.len == 0 or plan_name.len == 0) return error.InvalidAppSuite;

    try package_store.validatePackageName(package_name);
    try validatePlanName(plan_name);

    var entry = AppSuiteEntry{};
    try copyPlanComponent(entry.package_name_storage[0..], &entry.package_name_len, package_name, error.InvalidPackageName);
    try copyPlanComponent(entry.plan_name_storage[0..], &entry.plan_name_len, plan_name, error.InvalidAppPlanName);
    return entry;
}

fn renderSuiteEntriesAlloc(allocator: std.mem.Allocator, suite: AppSuite, max_bytes: usize) Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var entry_index: usize = 0;
    while (entry_index < suite.entry_count) : (entry_index += 1) {
        const entry = suite.entries[entry_index];
        const line = try std.fmt.allocPrint(allocator, "{s}:{s}\n", .{ entry.packageName(), entry.planName() });
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

fn renderSuiteInfoAlloc(allocator: std.mem.Allocator, suite: AppSuite, path: []const u8, max_bytes: usize) Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    const header = try std.fmt.allocPrint(allocator, "suite={s}\npath={s}\n", .{ suite.suiteName(), path });
    defer allocator.free(header);
    if (header.len > max_bytes) return error.ResponseTooLarge;
    try out.appendSlice(allocator, header);

    var entry_index: usize = 0;
    while (entry_index < suite.entry_count) : (entry_index += 1) {
        const entry = suite.entries[entry_index];
        const line = try std.fmt.allocPrint(allocator, "entry={s}:{s}\n", .{ entry.packageName(), entry.planName() });
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

fn loadPlan(name: []const u8, plan_name: []const u8) Error!AppPlan {
    try ensurePackageInstalled(name);
    try validatePlanName(plan_name);

    var path_buf: [filesystem.max_path_len]u8 = undefined;
    var body_storage: [max_plan_bytes]u8 = undefined;
    const path = try planPath(name, plan_name, &path_buf);
    var fba = std.heap.FixedBufferAllocator.init(&body_storage);
    const body = filesystem.readFileAlloc(fba.allocator(), path, body_storage.len) catch |err| switch (err) {
        error.FileNotFound => return error.AppPlanNotFound,
        else => return err,
    };
    return parsePlan(name, plan_name, body);
}

fn parsePlan(name: []const u8, plan_name: []const u8, body: []const u8) Error!AppPlan {
    var plan = try initPlan(name, plan_name);
    var saw_release = false;
    var saw_trust = false;
    var saw_connector = false;
    var saw_width = false;
    var saw_height = false;
    var saw_autorun = false;

    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        if (std.mem.startsWith(u8, line, "package=")) {
            if (!std.mem.eql(u8, line["package=".len..], name)) return error.InvalidAppPlan;
            continue;
        }
        if (std.mem.startsWith(u8, line, "plan=")) {
            if (!std.mem.eql(u8, line["plan=".len..], plan_name)) return error.InvalidAppPlan;
            continue;
        }
        if (std.mem.startsWith(u8, line, "release=")) {
            const value = line["release=".len..];
            saw_release = true;
            if (std.mem.eql(u8, value, "none")) {
                plan.release_name_len = 0;
            } else {
                try package_store.validateReleaseName(value);
                try copyPlanComponent(plan.release_name_storage[0..], &plan.release_name_len, value, error.InvalidReleaseName);
            }
            continue;
        }
        if (std.mem.startsWith(u8, line, "trust_bundle=")) {
            const value = line["trust_bundle=".len..];
            saw_trust = true;
            if (std.mem.eql(u8, value, "none")) {
                plan.trust_bundle_len = 0;
            } else {
                try copyPlanComponent(plan.trust_bundle_storage[0..], &plan.trust_bundle_len, value, error.InvalidTrustName);
            }
            continue;
        }
        if (std.mem.startsWith(u8, line, "connector=")) {
            plan.connector_type = try package_store.parseConnectorType(line["connector=".len..]);
            saw_connector = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "display_width=")) {
            plan.display_width = std.fmt.parseInt(u16, line["display_width=".len..], 10) catch return error.InvalidAppPlan;
            if (plan.display_width == 0) return error.InvalidAppPlan;
            saw_width = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "display_height=")) {
            plan.display_height = std.fmt.parseInt(u16, line["display_height=".len..], 10) catch return error.InvalidAppPlan;
            if (plan.display_height == 0) return error.InvalidAppPlan;
            saw_height = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "autorun=")) {
            plan.autorun = try parsePlanBool(line["autorun=".len..]);
            saw_autorun = true;
            continue;
        }

        return error.InvalidAppPlan;
    }

    if (!saw_release or !saw_trust or !saw_connector or !saw_width or !saw_height or !saw_autorun) {
        return error.InvalidAppPlan;
    }

    return plan;
}

fn renderPlanAlloc(
    allocator: std.mem.Allocator,
    plan: AppPlan,
    path: []const u8,
    active_name: ?[]const u8,
    max_bytes: usize,
) Error![]u8 {
    const response = if (active_name) |active| try std.fmt.allocPrint(
        allocator,
        "active_plan={s}\npackage={s}\nplan={s}\nrelease={s}\ntrust_bundle={s}\nconnector={s}\ndisplay_width={d}\ndisplay_height={d}\nautorun={d}\npath={s}\n",
        .{
            active,
            plan.packageName(),
            plan.planName(),
            if (plan.releaseName().len == 0) "none" else plan.releaseName(),
            if (plan.trustBundle().len == 0) "none" else plan.trustBundle(),
            package_store.connectorNameFromType(plan.connector_type),
            plan.display_width,
            plan.display_height,
            @intFromBool(plan.autorun),
            path,
        },
    ) else try std.fmt.allocPrint(
        allocator,
        "package={s}\nplan={s}\nrelease={s}\ntrust_bundle={s}\nconnector={s}\ndisplay_width={d}\ndisplay_height={d}\nautorun={d}\npath={s}\n",
        .{
            plan.packageName(),
            plan.planName(),
            if (plan.releaseName().len == 0) "none" else plan.releaseName(),
            if (plan.trustBundle().len == 0) "none" else plan.trustBundle(),
            package_store.connectorNameFromType(plan.connector_type),
            plan.display_width,
            plan.display_height,
            @intFromBool(plan.autorun),
            path,
        },
    );
    errdefer allocator.free(response);
    if (response.len > max_bytes) return error.ResponseTooLarge;
    return response;
}

fn parsePlanBool(value: []const u8) Error!bool {
    if (std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "yes")) {
        return true;
    }
    if (std.mem.eql(u8, value, "0") or std.ascii.eqlIgnoreCase(value, "false") or std.ascii.eqlIgnoreCase(value, "no")) {
        return false;
    }
    return error.InvalidAppPlan;
}

fn copyPlanComponent(storage: []u8, len_ptr: anytype, value: []const u8, comptime err_value: Error) Error!void {
    if (value.len > storage.len) return err_value;
    @memcpy(storage[0..value.len], value);
    len_ptr.* = @intCast(value.len);
}

fn readAutorunListAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    return filesystem.readFileAlloc(allocator, autorun_list_path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => allocator.dupe(u8, ""),
        else => err,
    };
}

fn loadAutorunListScratch(buffer: *[max_autorun_bytes]u8) Error![]const u8 {
    var fba = std.heap.FixedBufferAllocator.init(buffer);
    const existing = filesystem.readFileAlloc(fba.allocator(), autorun_list_path, buffer.len) catch |err| switch (err) {
        error.FileNotFound => "",
        else => return err,
    };
    return existing;
}

fn containsAutorunName(entries: []const u8, name: []const u8) bool {
    var lines = std.mem.splitScalar(u8, entries, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, name)) return true;
    }
    return false;
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

test "app runtime persists autorun registry on ram disk" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try package_store.installScriptPackage("demo", "echo demo", 1);
    try package_store.installScriptPackage("aux", "echo aux", 2);

    try addAutorun("demo", 3);
    try addAutorun("demo", 4);
    try addAutorun("aux", 5);

    const autorun = try autorunListAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(autorun);
    try std.testing.expectEqualStrings("demo\naux\n", autorun);

    try removeAutorun("demo", 6);
    const updated = try autorunListAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(updated);
    try std.testing.expectEqualStrings("aux\n", updated);
}

test "app runtime persists autorun registry on ata-backed storage" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try package_store.installScriptPackage("demo", "echo demo", 1);
    try package_store.installScriptPackage("aux", "echo aux", 2);

    try addAutorun("demo", 3);
    try addAutorun("aux", 4);

    const autorun = try autorunListAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(autorun);
    try std.testing.expectEqualStrings("demo\naux\n", autorun);

    try removeAutorun("aux", 5);
    const updated = try autorunListAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(updated);
    try std.testing.expectEqualStrings("demo\n", updated);
}

test "app runtime saves, applies, and deletes named app plans on ram disk" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try trust_store.installBundle("root-a", "cert-a", 1);
    try package_store.installScriptPackage("demo", "echo stable", 2);
    try package_store.configureDisplayMode("demo", 1280, 720, 3);
    try package_store.configureConnectorType("demo", abi.display_connector_virtual, 4);
    try package_store.configureTrustBundle("demo", "root-a", 5);
    try package_store.snapshotPackageRelease("demo", "stable", 6);
    try package_store.installScriptPackage("demo", "echo drift", 7);

    try savePlan("demo", "golden", "stable", "root-a", abi.display_connector_virtual, 1280, 720, true, 8);

    const plan_list = try planListAlloc(std.testing.allocator, "demo", 128);
    defer std.testing.allocator.free(plan_list);
    try std.testing.expectEqualStrings("golden\n", plan_list);

    const plan_info = try planInfoAlloc(std.testing.allocator, "demo", "golden", 256);
    defer std.testing.allocator.free(plan_info);
    try std.testing.expect(std.mem.indexOf(u8, plan_info, "release=stable") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_info, "trust_bundle=root-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan_info, "autorun=1") != null);

    try applyPlan("demo", "golden", 9);

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const profile = try package_store.loadLaunchProfile("demo", &entrypoint_buf);
    try std.testing.expectEqualStrings("root-a", profile.trustBundle());
    try std.testing.expectEqual(@as(u16, 1280), profile.display_width);
    try std.testing.expectEqual(@as(u16, 720), profile.display_height);
    try std.testing.expectEqual(@as(u8, abi.display_connector_virtual), profile.connector_type);

    const autorun = try autorunListAlloc(std.testing.allocator, 64);
    defer std.testing.allocator.free(autorun);
    try std.testing.expectEqualStrings("demo\n", autorun);

    const active = try activePlanInfoAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(active);
    try std.testing.expect(std.mem.indexOf(u8, active, "active_plan=golden") != null);

    const entrypoint = try filesystem.readFileAlloc(std.testing.allocator, profile.entrypoint, 64);
    defer std.testing.allocator.free(entrypoint);
    try std.testing.expectEqualStrings("echo stable", entrypoint);

    try deletePlan("demo", "golden", 10);
    try std.testing.expectError(error.AppPlanNotFound, planInfoAlloc(std.testing.allocator, "demo", "golden", 256));
    try std.testing.expectError(error.AppActivePlanNotSet, activePlanInfoAlloc(std.testing.allocator, "demo", 256));
}

test "app runtime app plans persist on ata-backed storage" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try trust_store.installBundle("persisted-root", "cert-root", 1);
    try package_store.installScriptPackage("persisted", "echo stable-persisted", 2);
    try package_store.snapshotPackageRelease("persisted", "stable", 3);
    try savePlan("persisted", "boot", "stable", "persisted-root", abi.display_connector_virtual, 1024, 768, true, 4);
    try applyPlan("persisted", "boot", 5);

    filesystem.resetForTest();

    const plan_list = try planListAlloc(std.testing.allocator, "persisted", 128);
    defer std.testing.allocator.free(plan_list);
    try std.testing.expectEqualStrings("boot\n", plan_list);

    const active = try activePlanInfoAlloc(std.testing.allocator, "persisted", 256);
    defer std.testing.allocator.free(active);
    try std.testing.expect(std.mem.indexOf(u8, active, "active_plan=boot") != null);
    try std.testing.expect(std.mem.indexOf(u8, active, "release=stable") != null);

    const autorun = try autorunListAlloc(std.testing.allocator, 64);
    defer std.testing.allocator.free(autorun);
    try std.testing.expectEqualStrings("persisted\n", autorun);
}

test "app runtime saves applies and deletes app suites on ram disk" {
    storage_backend.resetForTest();
    filesystem.resetForTest();

    try trust_store.installBundle("suite-root", "cert-root", 1);
    try package_store.installScriptPackage("demo", "echo suite-demo", 2);
    try package_store.installScriptPackage("aux", "echo suite-aux", 3);
    try savePlan("demo", "golden", "", "suite-root", abi.display_connector_virtual, 1280, 720, true, 4);
    try savePlan("aux", "sidecar", "", "", abi.display_connector_virtual, 800, 600, false, 5);

    try saveSuite("daily", "demo:golden aux:sidecar", 6);

    const suite_list = try suiteListAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(suite_list);
    try std.testing.expectEqualStrings("daily\n", suite_list);

    const suite_info = try suiteInfoAlloc(std.testing.allocator, "daily", 256);
    defer std.testing.allocator.free(suite_info);
    try std.testing.expect(std.mem.indexOf(u8, suite_info, "suite=daily") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info, "entry=demo:golden") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info, "entry=aux:sidecar") != null);

    const suite_entries = try suiteEntriesAlloc(std.testing.allocator, "daily", 128);
    defer std.testing.allocator.free(suite_entries);
    try std.testing.expectEqualStrings("demo:golden\naux:sidecar\n", suite_entries);

    try applySuite("daily", 7);

    const demo_active = try activePlanInfoAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(demo_active);
    try std.testing.expect(std.mem.indexOf(u8, demo_active, "active_plan=golden") != null);

    const aux_active = try activePlanInfoAlloc(std.testing.allocator, "aux", 256);
    defer std.testing.allocator.free(aux_active);
    try std.testing.expect(std.mem.indexOf(u8, aux_active, "active_plan=sidecar") != null);

    const autorun = try autorunListAlloc(std.testing.allocator, 64);
    defer std.testing.allocator.free(autorun);
    try std.testing.expectEqualStrings("demo\n", autorun);

    try deleteSuite("daily", 8);
    try std.testing.expectError(error.AppSuiteNotFound, suiteInfoAlloc(std.testing.allocator, "daily", 256));

    const after_delete = try suiteListAlloc(std.testing.allocator, 64);
    defer std.testing.allocator.free(after_delete);
    try std.testing.expectEqualStrings("", after_delete);
}

test "app runtime app suites persist on ata-backed storage" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try package_store.installScriptPackage("demo", "echo persisted-demo", 1);
    try package_store.installScriptPackage("aux", "echo persisted-aux", 2);
    try savePlan("demo", "golden", "", "", abi.display_connector_virtual, 1024, 768, true, 3);
    try savePlan("aux", "sidecar", "", "", abi.display_connector_virtual, 800, 600, false, 4);
    try saveSuite("persisted", "demo:golden aux:sidecar", 5);
    try applySuite("persisted", 6);

    filesystem.resetForTest();

    const suite_list = try suiteListAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(suite_list);
    try std.testing.expectEqualStrings("persisted\n", suite_list);

    const suite_info = try suiteInfoAlloc(std.testing.allocator, "persisted", 256);
    defer std.testing.allocator.free(suite_info);
    try std.testing.expect(std.mem.indexOf(u8, suite_info, "entry=demo:golden") != null);
    try std.testing.expect(std.mem.indexOf(u8, suite_info, "entry=aux:sidecar") != null);

    const demo_active = try activePlanInfoAlloc(std.testing.allocator, "demo", 256);
    defer std.testing.allocator.free(demo_active);
    try std.testing.expect(std.mem.indexOf(u8, demo_active, "active_plan=golden") != null);

    const aux_active = try activePlanInfoAlloc(std.testing.allocator, "aux", 256);
    defer std.testing.allocator.free(aux_active);
    try std.testing.expect(std.mem.indexOf(u8, aux_active, "active_plan=sidecar") != null);
}
