// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");
const app_runtime = @import("app_runtime.zig");
const ata_pio_disk = @import("ata_pio_disk.zig");
const filesystem = @import("filesystem.zig");
const framebuffer_console = @import("framebuffer_console.zig");
const package_store = @import("package_store.zig");
const storage_backend = @import("storage_backend.zig");
const trust_store = @import("trust_store.zig");

pub const max_name_len: usize = 32;
pub const max_workspace_entries: usize = 8;

const root_dir = "/runtime/workspaces";
const runtime_root_dir = "/runtime/workspace-runs";
const release_root_dir = "/runtime/workspace-releases";
const max_workspace_bytes: usize = 1024;
const max_history_bytes: usize = 1024;
const max_autorun_bytes: usize = 1024;
const release_list_scan_max_bytes: usize = storage_backend.block_size * 4;
const autorun_list_path = "/runtime/workspace-runs/autorun.txt";

pub const Error = filesystem.Error || app_runtime.Error || package_store.Error || trust_store.Error || std.mem.Allocator.Error || error{
    InvalidWorkspaceName,
    WorkspaceNotFound,
    InvalidWorkspace,
    InvalidWorkspaceEntry,
    WorkspaceEntryLimit,
    ResponseTooLarge,
    UnsupportedDisplayMode,
    WorkspaceStateNotFound,
    WorkspaceHistoryNotFound,
    WorkspaceStdoutNotFound,
    WorkspaceStderrNotFound,
    WorkspaceAutorunEntryNotFound,
    WorkspaceReleaseNotFound,
    WorkspaceReleaseAlreadyExists,
};

pub const ReleasePruneResult = struct {
    kept_count: u32,
    deleted_count: u32,
};

const ReleaseMetadata = struct {
    name: []const u8 = "",
    release: []const u8 = "",
    saved_seq: u32 = 0,
    saved_tick: u64 = 0,
};

const ReleaseRecord = struct {
    name_storage: [package_store.max_release_len]u8 = [_]u8{0} ** package_store.max_release_len,
    name_len: u8 = 0,
    saved_seq: u32 = 0,

    fn name(self: *const @This()) []const u8 {
        return self.name_storage[0..self.name_len];
    }
};

const ChannelEntry = struct {
    package_name_len: u8 = 0,
    package_name_storage: [package_store.max_name_len]u8 = [_]u8{0} ** package_store.max_name_len,
    channel_name_len: u8 = 0,
    channel_name_storage: [package_store.max_release_len]u8 = [_]u8{0} ** package_store.max_release_len,
    release_name_len: u8 = 0,
    release_name_storage: [package_store.max_release_len]u8 = [_]u8{0} ** package_store.max_release_len,

    fn packageName(self: *const @This()) []const u8 {
        return self.package_name_storage[0..self.package_name_len];
    }

    fn channelName(self: *const @This()) []const u8 {
        return self.channel_name_storage[0..self.channel_name_len];
    }

    fn releaseName(self: *const @This()) []const u8 {
        return self.release_name_storage[0..self.release_name_len];
    }
};

const Workspace = struct {
    workspace_name_len: u8 = 0,
    workspace_name_storage: [max_name_len]u8 = [_]u8{0} ** max_name_len,
    suite_name_len: u8 = 0,
    suite_name_storage: [package_store.max_release_len]u8 = [_]u8{0} ** package_store.max_release_len,
    trust_bundle_len: u8 = 0,
    trust_bundle_storage: [trust_store.max_name_len]u8 = [_]u8{0} ** trust_store.max_name_len,
    display_width: u16 = 0,
    display_height: u16 = 0,
    entry_count: u8 = 0,
    entries: [max_workspace_entries]ChannelEntry = [_]ChannelEntry{.{}} ** max_workspace_entries,

    fn workspaceName(self: *const @This()) []const u8 {
        return self.workspace_name_storage[0..self.workspace_name_len];
    }

    fn suiteName(self: *const @This()) []const u8 {
        return self.suite_name_storage[0..self.suite_name_len];
    }

    fn trustBundle(self: *const @This()) []const u8 {
        return self.trust_bundle_storage[0..self.trust_bundle_len];
    }
};

pub fn listAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const raw_listing = filesystem.listDirectoryAlloc(allocator, root_dir, max_workspace_bytes) catch |err| switch (err) {
        error.FileNotFound => return allocator.alloc(u8, 0),
        else => return err,
    };
    defer allocator.free(raw_listing);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, raw_listing, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (!std.mem.startsWith(u8, line, "file ")) continue;
        var parts = std.mem.splitScalar(u8, line["file ".len..], ' ');
        const file_name = parts.next() orelse continue;
        if (!std.mem.endsWith(u8, file_name, ".txt")) continue;
        const name = file_name[0 .. file_name.len - ".txt".len];
        if (name.len == 0) continue;
        if (out.items.len + name.len + 1 > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, name);
        try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

pub fn autorunListAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    return readAutorunListAlloc(allocator, max_bytes);
}

pub fn releaseListAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    try validateWorkspaceName(name);
    if (!try workspaceExists(name)) return error.WorkspaceNotFound;

    var records: [filesystem.max_entries]ReleaseRecord = undefined;
    const record_count = try collectReleaseRecords(name, &records);
    sortReleaseRecordsOldestFirst(records[0..record_count]);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (records[0..record_count]) |record| {
        const release_name = record.name();
        if (out.items.len + release_name.len + 1 > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, release_name);
        try out.append(allocator, '\n');
    }

    return out.toOwnedSlice(allocator);
}

pub fn releaseInfoAlloc(
    allocator: std.mem.Allocator,
    name: []const u8,
    release: []const u8,
    max_bytes: usize,
) Error![]u8 {
    try validateWorkspaceName(name);
    try package_store.validateReleaseName(release);
    if (!try releaseExists(name, release)) return error.WorkspaceReleaseNotFound;

    var metadata_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var release_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var release_root_buffer: [filesystem.max_path_len]u8 = undefined;
    const metadata_path = try releaseMetadataPath(name, release, &metadata_path_buffer);
    const release_path = try releasePath(name, release, &release_path_buffer);
    const release_root = try releaseDirPath(name, release, &release_root_buffer);

    var metadata_scratch: [256]u8 = undefined;
    var metadata_fba = std.heap.FixedBufferAllocator.init(&metadata_scratch);
    const metadata_raw = filesystem.readFileAlloc(metadata_fba.allocator(), metadata_path, metadata_scratch.len) catch |err| switch (err) {
        error.FileNotFound => return error.WorkspaceReleaseNotFound,
        else => return err,
    };
    const metadata = try parseReleaseMetadata(metadata_raw);

    var payload_scratch: [max_workspace_bytes]u8 = undefined;
    var payload_fba = std.heap.FixedBufferAllocator.init(&payload_scratch);
    const payload = filesystem.readFileAlloc(payload_fba.allocator(), release_path, payload_scratch.len) catch |err| switch (err) {
        error.FileNotFound => return error.WorkspaceReleaseNotFound,
        else => return err,
    };
    const workspace = try parseWorkspacePayload(name, payload);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "workspace={s}\n", .{name}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "release={s}\n", .{if (metadata.release.len == 0) release else metadata.release}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "saved_seq={d}\n", .{metadata.saved_seq}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "saved_tick={d}\n", .{metadata.saved_tick}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "root={s}\n", .{release_root}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "workspace_path={s}\n", .{release_path}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "metadata_path={s}\n", .{metadata_path}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "suite={s}\n", .{if (workspace.suiteName().len == 0) "none" else workspace.suiteName()}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "trust_bundle={s}\n", .{if (workspace.trustBundle().len == 0) "none" else workspace.trustBundle()}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "display={d}x{d}\n", .{ workspace.display_width, workspace.display_height }));
    for (workspace.entries[0..workspace.entry_count]) |entry| {
        try appendLine(
            &out,
            allocator,
            max_bytes,
            try std.fmt.allocPrint(allocator, "channel={s}:{s}:{s}\n", .{ entry.packageName(), entry.channelName(), entry.releaseName() }),
        );
    }
    return out.toOwnedSlice(allocator);
}

pub fn infoAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    const workspace = try loadWorkspace(name);
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    var state_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var history_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var stdout_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var stderr_path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try workspacePath(name, &path_buffer);
    const state_path = try statePath(name, &state_path_buffer);
    const history_path = try historyPath(name, &history_path_buffer);
    const stdout_path = try stdoutPath(name, &stdout_path_buffer);
    const stderr_path = try stderrPath(name, &stderr_path_buffer);
    return renderWorkspaceAlloc(allocator, workspace, path, state_path, history_path, stdout_path, stderr_path, max_bytes);
}

pub fn saveWorkspace(
    name: []const u8,
    suite_name: []const u8,
    trust_bundle: []const u8,
    display_width: u16,
    display_height: u16,
    channel_entries_spec: []const u8,
    tick: u64,
) Error!void {
    try validateWorkspaceName(name);
    try validateSuiteName(suite_name);
    try validateTrustBundle(trust_bundle);
    try validateDisplayMode(display_width, display_height);

    var workspace = Workspace{};
    try copyComponent(workspace.workspace_name_storage[0..], &workspace.workspace_name_len, name, error.InvalidWorkspaceName);
    try copyComponent(workspace.suite_name_storage[0..], &workspace.suite_name_len, suite_name, error.InvalidWorkspace);
    try copyComponent(workspace.trust_bundle_storage[0..], &workspace.trust_bundle_len, trust_bundle, error.InvalidWorkspace);
    workspace.display_width = display_width;
    workspace.display_height = display_height;
    try parseChannelEntriesSpec(&workspace, channel_entries_spec);

    try filesystem.createDirPath(root_dir);
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    var body_buffer: [max_workspace_bytes]u8 = undefined;
    const body = try renderWorkspaceBody(&workspace, &body_buffer);
    try filesystem.writeFile(try workspacePath(name, &path_buffer), body, tick);
}

pub fn snapshotWorkspaceRelease(name: []const u8, release: []const u8, tick: u64) Error!void {
    try validateWorkspaceName(name);
    try package_store.validateReleaseName(release);
    if (!try workspaceExists(name)) return error.WorkspaceNotFound;
    if (try releaseExists(name, release)) return error.WorkspaceReleaseAlreadyExists;

    const saved_seq = try nextReleaseSequence(name);
    try createReleaseDirectories(name, release);

    var canonical_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var canonical_scratch: [max_workspace_bytes]u8 = undefined;
    var canonical_fba = std.heap.FixedBufferAllocator.init(&canonical_scratch);
    const canonical_payload = filesystem.readFileAlloc(canonical_fba.allocator(), try workspacePath(name, &canonical_path_buffer), canonical_scratch.len) catch |err| switch (err) {
        error.FileNotFound => return error.WorkspaceNotFound,
        else => return err,
    };

    var release_path_buffer: [filesystem.max_path_len]u8 = undefined;
    try filesystem.writeFile(try releasePath(name, release, &release_path_buffer), canonical_payload, tick);
    try writeReleaseMetadata(name, release, saved_seq, tick);
}

pub fn activateWorkspaceRelease(name: []const u8, release: []const u8, tick: u64) Error!void {
    try validateWorkspaceName(name);
    try package_store.validateReleaseName(release);
    if (!try releaseExists(name, release)) return error.WorkspaceReleaseNotFound;

    var release_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var release_scratch: [max_workspace_bytes]u8 = undefined;
    var release_fba = std.heap.FixedBufferAllocator.init(&release_scratch);
    const release_payload = filesystem.readFileAlloc(release_fba.allocator(), try releasePath(name, release, &release_path_buffer), release_scratch.len) catch |err| switch (err) {
        error.FileNotFound => return error.WorkspaceReleaseNotFound,
        else => return err,
    };

    try filesystem.createDirPath(root_dir);
    var canonical_path_buffer: [filesystem.max_path_len]u8 = undefined;
    try filesystem.writeFile(try workspacePath(name, &canonical_path_buffer), release_payload, tick);
}

pub fn deleteWorkspaceRelease(name: []const u8, release: []const u8, tick: u64) Error!void {
    try validateWorkspaceName(name);
    try package_store.validateReleaseName(release);
    if (!try releaseExists(name, release)) return error.WorkspaceReleaseNotFound;

    var release_dir_buffer: [filesystem.max_path_len]u8 = undefined;
    try filesystem.deleteTree(try releaseDirPath(name, release, &release_dir_buffer), tick);
}

pub fn pruneWorkspaceReleases(name: []const u8, keep: usize, tick: u64) Error!ReleasePruneResult {
    try validateWorkspaceName(name);
    if (!try workspaceExists(name)) return error.WorkspaceNotFound;

    var records: [filesystem.max_entries]ReleaseRecord = undefined;
    const record_count = try collectReleaseRecords(name, &records);
    sortReleaseRecordsNewestFirst(records[0..record_count]);

    var deleted_count: u32 = 0;
    var index = keep;
    while (index < record_count) : (index += 1) {
        try deleteWorkspaceRelease(name, records[index].name(), tick);
        deleted_count += 1;
    }

    return .{
        .kept_count = @intCast(@min(keep, record_count)),
        .deleted_count = deleted_count,
    };
}

pub fn applyWorkspace(name: []const u8, tick: u64) Error!void {
    const workspace = try loadWorkspace(name);

    for (workspace.entries[0..workspace.entry_count]) |entry| {
        try package_store.setPackageReleaseChannel(entry.packageName(), entry.channelName(), entry.releaseName(), tick);
        try package_store.activatePackageReleaseChannel(entry.packageName(), entry.channelName(), tick);
    }

    if (workspace.suiteName().len != 0) {
        try app_runtime.applySuite(workspace.suiteName(), tick);
    }

    if (workspace.trustBundle().len != 0) {
        try trust_store.selectBundle(workspace.trustBundle(), tick);
    }

    framebuffer_console.setMode(workspace.display_width, workspace.display_height) catch |err| switch (err) {
        error.UnsupportedMode => return error.UnsupportedDisplayMode,
    };
}

pub fn deleteWorkspace(name: []const u8, tick: u64) Error!void {
    try validateWorkspaceName(name);
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try workspacePath(name, &path_buffer);
    filesystem.deleteFile(path, tick) catch |err| switch (err) {
        error.FileNotFound => return error.WorkspaceNotFound,
        else => return err,
    };
    deleteState(name, tick) catch |err| switch (err) {
        error.WorkspaceStateNotFound => {},
        else => return err,
    };
    removeAutorun(name, tick) catch |err| switch (err) {
        error.WorkspaceAutorunEntryNotFound => {},
        else => return err,
    };
    var releases_buffer: [filesystem.max_path_len]u8 = undefined;
    filesystem.deleteTree(releasesRootPath(name, &releases_buffer), tick) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

pub fn suiteNameAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    const workspace = try loadWorkspace(name);
    if (workspace.suiteName().len == 0) return error.InvalidWorkspace;
    if (workspace.suiteName().len > max_bytes) return error.ResponseTooLarge;
    return allocator.dupe(u8, workspace.suiteName());
}

pub fn stateAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try statePath(name, &path_buffer);
    return filesystem.readFileAlloc(allocator, path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => error.WorkspaceStateNotFound,
        else => err,
    };
}

pub fn historyAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try historyPath(name, &path_buffer);
    return filesystem.readFileAlloc(allocator, path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => error.WorkspaceHistoryNotFound,
        else => err,
    };
}

pub fn stdoutAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try stdoutPath(name, &path_buffer);
    return filesystem.readFileAlloc(allocator, path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => error.WorkspaceStdoutNotFound,
        else => err,
    };
}

pub fn stderrAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try stderrPath(name, &path_buffer);
    return filesystem.readFileAlloc(allocator, path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => error.WorkspaceStderrNotFound,
        else => err,
    };
}

pub fn writeLastRun(name: []const u8, exit_code: u8, stdout: []const u8, stderr: []const u8, tick: u64) Error!void {
    const workspace = try loadWorkspace(name);

    var dir_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var state_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var history_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var stdout_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var stderr_path_buffer: [filesystem.max_path_len]u8 = undefined;
    const dir_path = try workspaceRunDirPath(name, &dir_path_buffer);
    const state_path = try statePath(name, &state_path_buffer);
    const history_path = try historyPath(name, &history_path_buffer);
    const stdout_path = try stdoutPath(name, &stdout_path_buffer);
    const stderr_path = try stderrPath(name, &stderr_path_buffer);

    try filesystem.createDirPath(runtime_root_dir);
    try filesystem.createDirPath(dir_path);

    var state_body: [384]u8 = undefined;
    const rendered_state = std.fmt.bufPrint(
        &state_body,
        "workspace={s}\nexit_code={d}\nstdout_bytes={d}\nstderr_bytes={d}\nsuite={s}\ntrust_bundle={s}\ndisplay={d}x{d}\nchannel_count={d}\n",
        .{
            name,
            exit_code,
            stdout.len,
            stderr.len,
            if (workspace.suiteName().len == 0) "none" else workspace.suiteName(),
            if (workspace.trustBundle().len == 0) "none" else workspace.trustBundle(),
            workspace.display_width,
            workspace.display_height,
            workspace.entry_count,
        },
    ) catch return error.ResponseTooLarge;
    try filesystem.writeFile(state_path, rendered_state, tick);
    try filesystem.writeFile(stdout_path, stdout, tick);
    try filesystem.writeFile(stderr_path, stderr, tick);

    var history_line_buffer: [256]u8 = undefined;
    const history_line = std.fmt.bufPrint(
        &history_line_buffer,
        "tick={d} workspace={s} exit_code={d} stdout_bytes={d} stderr_bytes={d} suite={s} trust_bundle={s} display={d}x{d} channels={d}\n",
        .{
            tick,
            name,
            exit_code,
            stdout.len,
            stderr.len,
            if (workspace.suiteName().len == 0) "none" else workspace.suiteName(),
            if (workspace.trustBundle().len == 0) "none" else workspace.trustBundle(),
            workspace.display_width,
            workspace.display_height,
            workspace.entry_count,
        },
    ) catch return error.ResponseTooLarge;
    try appendHistoryLine(history_path, history_line, tick);
}

pub fn addAutorun(name: []const u8, tick: u64) Error!void {
    _ = try loadWorkspace(name);

    var existing_scratch: [max_autorun_bytes]u8 = undefined;
    const existing = try loadAutorunListScratch(&existing_scratch);
    if (containsAutorunName(existing, name)) return;

    var rendered: [max_autorun_bytes + max_name_len + 2]u8 = undefined;
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

    try filesystem.createDirPath(runtime_root_dir);
    try filesystem.writeFile(autorun_list_path, rendered[0..len], tick);
}

pub fn removeAutorun(name: []const u8, tick: u64) Error!void {
    try validateWorkspaceName(name);

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

    if (!found) return error.WorkspaceAutorunEntryNotFound;

    try filesystem.createDirPath(runtime_root_dir);
    try filesystem.writeFile(autorun_list_path, rendered[0..len], tick);
}

pub fn deleteState(name: []const u8, tick: u64) Error!void {
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try workspaceRunDirPath(name, &path_buffer);
    filesystem.deleteTree(path, tick) catch |err| switch (err) {
        error.FileNotFound => return error.WorkspaceStateNotFound,
        else => return err,
    };
}

fn workspacePath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateWorkspaceName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}.txt", .{ root_dir, name }) catch error.InvalidPath;
}

fn releasesRootPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) []const u8 {
    return std.fmt.bufPrint(buffer, "{s}/{s}", .{ release_root_dir, name }) catch unreachable;
}

fn releaseDirPath(name: []const u8, release: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateWorkspaceName(name);
    try package_store.validateReleaseName(release);
    return std.fmt.bufPrint(buffer, "{s}/{s}/{s}", .{ release_root_dir, name, release }) catch error.InvalidPath;
}

fn releasePath(name: []const u8, release: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateWorkspaceName(name);
    try package_store.validateReleaseName(release);
    return std.fmt.bufPrint(buffer, "{s}/{s}/{s}/workspace.txt", .{ release_root_dir, name, release }) catch error.InvalidPath;
}

fn releaseMetadataPath(name: []const u8, release: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateWorkspaceName(name);
    try package_store.validateReleaseName(release);
    return std.fmt.bufPrint(buffer, "{s}/{s}/{s}/release.txt", .{ release_root_dir, name, release }) catch error.InvalidPath;
}

pub fn statePath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateWorkspaceName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/last_run.txt", .{ runtime_root_dir, name }) catch error.InvalidPath;
}

pub fn historyPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateWorkspaceName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/history.log", .{ runtime_root_dir, name }) catch error.InvalidPath;
}

pub fn stdoutPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateWorkspaceName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/stdout.log", .{ runtime_root_dir, name }) catch error.InvalidPath;
}

pub fn stderrPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateWorkspaceName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}/stderr.log", .{ runtime_root_dir, name }) catch error.InvalidPath;
}

fn workspaceRunDirPath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateWorkspaceName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}", .{ runtime_root_dir, name }) catch error.InvalidPath;
}

fn renderWorkspaceAlloc(
    allocator: std.mem.Allocator,
    workspace: Workspace,
    path: []const u8,
    state_path: []const u8,
    history_path: []const u8,
    stdout_path: []const u8,
    stderr_path: []const u8,
    max_bytes: usize,
) Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "workspace={s}\n", .{workspace.workspaceName()}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "path={s}\n", .{path}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "suite={s}\n", .{if (workspace.suiteName().len == 0) "none" else workspace.suiteName()}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "trust_bundle={s}\n", .{if (workspace.trustBundle().len == 0) "none" else workspace.trustBundle()}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "display={d}x{d}\n", .{ workspace.display_width, workspace.display_height }));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "state_path={s}\n", .{state_path}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "history_path={s}\n", .{history_path}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "stdout_path={s}\n", .{stdout_path}));
    try appendLine(&out, allocator, max_bytes, try std.fmt.allocPrint(allocator, "stderr_path={s}\n", .{stderr_path}));

    for (workspace.entries[0..workspace.entry_count]) |entry| {
        try appendLine(
            &out,
            allocator,
            max_bytes,
            try std.fmt.allocPrint(allocator, "channel={s}:{s}:{s}\n", .{ entry.packageName(), entry.channelName(), entry.releaseName() }),
        );
    }

    return out.toOwnedSlice(allocator);
}

fn appendLine(out: *std.ArrayList(u8), allocator: std.mem.Allocator, max_bytes: usize, line: []u8) Error!void {
    defer allocator.free(line);
    if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
    try out.appendSlice(allocator, line);
}

fn renderWorkspaceBody(workspace: *const Workspace, buffer: *[max_workspace_bytes]u8) Error![]const u8 {
    var used: usize = 0;

    used += (std.fmt.bufPrint(buffer[used..], "suite={s}\n", .{if (workspace.suiteName().len == 0) "none" else workspace.suiteName()}) catch return error.ResponseTooLarge).len;
    used += (std.fmt.bufPrint(buffer[used..], "trust_bundle={s}\n", .{if (workspace.trustBundle().len == 0) "none" else workspace.trustBundle()}) catch return error.ResponseTooLarge).len;
    used += (std.fmt.bufPrint(buffer[used..], "display_width={d}\n", .{workspace.display_width}) catch return error.ResponseTooLarge).len;
    used += (std.fmt.bufPrint(buffer[used..], "display_height={d}\n", .{workspace.display_height}) catch return error.ResponseTooLarge).len;
    for (workspace.entries[0..workspace.entry_count]) |entry| {
        used += (std.fmt.bufPrint(buffer[used..], "channel={s}:{s}:{s}\n", .{ entry.packageName(), entry.channelName(), entry.releaseName() }) catch return error.ResponseTooLarge).len;
    }

    return buffer[0..used];
}

fn loadWorkspace(name: []const u8) Error!Workspace {
    try validateWorkspaceName(name);
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    var scratch: [max_workspace_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&scratch);
    const payload = filesystem.readFileAlloc(fba.allocator(), try workspacePath(name, &path_buffer), max_workspace_bytes) catch |err| switch (err) {
        error.FileNotFound => return error.WorkspaceNotFound,
        else => return err,
    };
    return parseWorkspacePayload(name, payload);
}

fn workspaceExists(name: []const u8) Error!bool {
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    _ = filesystem.statSummary(try workspacePath(name, &path_buffer)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

fn releaseExists(name: []const u8, release: []const u8) Error!bool {
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    _ = filesystem.statSummary(try releasePath(name, release, &path_buffer)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

fn parseWorkspacePayload(name: []const u8, payload: []const u8) Error!Workspace {
    var workspace = Workspace{};
    try copyComponent(workspace.workspace_name_storage[0..], &workspace.workspace_name_len, name, error.InvalidWorkspaceName);

    var have_width = false;
    var have_height = false;

    var lines = std.mem.splitScalar(u8, payload, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, "\r");
        if (line.len == 0) continue;

        if (std.mem.startsWith(u8, line, "suite=")) {
            const value = line["suite=".len..];
            const suite_name = if (std.ascii.eqlIgnoreCase(value, "none")) "" else value;
            try validateSuiteName(suite_name);
            try copyComponent(workspace.suite_name_storage[0..], &workspace.suite_name_len, suite_name, error.InvalidWorkspace);
            continue;
        }
        if (std.mem.startsWith(u8, line, "trust_bundle=")) {
            const value = line["trust_bundle=".len..];
            const trust_name = if (std.ascii.eqlIgnoreCase(value, "none")) "" else value;
            try validateTrustBundle(trust_name);
            try copyComponent(workspace.trust_bundle_storage[0..], &workspace.trust_bundle_len, trust_name, error.InvalidWorkspace);
            continue;
        }
        if (std.mem.startsWith(u8, line, "display_width=")) {
            workspace.display_width = std.fmt.parseInt(u16, line["display_width=".len..], 10) catch return error.InvalidWorkspace;
            have_width = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "display_height=")) {
            workspace.display_height = std.fmt.parseInt(u16, line["display_height=".len..], 10) catch return error.InvalidWorkspace;
            have_height = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "channel=")) {
            try parseChannelEntryLine(&workspace, line["channel=".len..]);
            continue;
        }
        return error.InvalidWorkspace;
    }

    if (!have_width or !have_height) return error.InvalidWorkspace;
    try validateDisplayMode(workspace.display_width, workspace.display_height);
    return workspace;
}

fn parseChannelEntriesSpec(workspace: *Workspace, spec: []const u8) Error!void {
    if (spec.len == 0) return;
    var iter = std.mem.tokenizeAny(u8, spec, " \t\r\n");
    while (iter.next()) |token| {
        try parseChannelEntryLine(workspace, token);
    }
}

fn parseChannelEntryLine(workspace: *Workspace, line: []const u8) Error!void {
    const first_sep = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidWorkspaceEntry;
    const second_rel = std.mem.indexOfScalar(u8, line[first_sep + 1 ..], ':') orelse return error.InvalidWorkspaceEntry;
    const second_sep = first_sep + 1 + second_rel;

    const package_name = line[0..first_sep];
    const channel_name = line[first_sep + 1 .. second_sep];
    const release_name = line[second_sep + 1 ..];
    if (package_name.len == 0 or channel_name.len == 0 or release_name.len == 0) return error.InvalidWorkspaceEntry;
    if (std.mem.indexOfScalar(u8, release_name, ':') != null) return error.InvalidWorkspaceEntry;

    try package_store.validatePackageName(package_name);
    try package_store.validateChannelName(channel_name);
    try package_store.validateReleaseName(release_name);

    var entrypoint_buffer: [filesystem.max_path_len]u8 = undefined;
    _ = try package_store.loadLaunchProfile(package_name, &entrypoint_buffer);
    if (!try package_store.releaseExistsAlloc(package_name, release_name)) return error.PackageReleaseNotFound;

    if (workspace.entry_count >= max_workspace_entries) return error.WorkspaceEntryLimit;
    const entry = &workspace.entries[workspace.entry_count];
    try copyComponent(entry.package_name_storage[0..], &entry.package_name_len, package_name, error.InvalidWorkspaceEntry);
    try copyComponent(entry.channel_name_storage[0..], &entry.channel_name_len, channel_name, error.InvalidWorkspaceEntry);
    try copyComponent(entry.release_name_storage[0..], &entry.release_name_len, release_name, error.InvalidWorkspaceEntry);
    workspace.entry_count += 1;
}

fn validateWorkspaceName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > max_name_len) return error.InvalidWorkspaceName;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
        return error.InvalidWorkspaceName;
    }
}

fn validateSuiteName(name: []const u8) Error!void {
    if (name.len == 0) return;
    var scratch: [512]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&scratch);
    _ = app_runtime.suiteInfoAlloc(fba.allocator(), name, scratch.len) catch |err| switch (err) {
        error.AppSuiteNotFound => return error.AppSuiteNotFound,
        else => return err,
    };
}

fn validateTrustBundle(name: []const u8) Error!void {
    if (name.len == 0) return;
    if (!try trust_store.bundleExists(name)) return error.TrustBundleNotFound;
}

fn validateDisplayMode(width: u16, height: u16) Error!void {
    var index: u16 = 0;
    while (index < framebuffer_console.supportedModeCount()) : (index += 1) {
        if (framebuffer_console.supportedModeWidth(index) == width and framebuffer_console.supportedModeHeight(index) == height) {
            return;
        }
    }
    return error.UnsupportedDisplayMode;
}

fn copyComponent(storage: []u8, len_ptr: anytype, value: []const u8, comptime err_value: Error) Error!void {
    if (value.len > storage.len) return err_value;
    @memcpy(storage[0..value.len], value);
    len_ptr.* = @as(u8, @intCast(value.len));
}

fn readAutorunListAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    return filesystem.readFileAlloc(allocator, autorun_list_path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => allocator.dupe(u8, ""),
        else => err,
    };
}

fn loadAutorunListScratch(buffer: *[max_autorun_bytes]u8) Error![]const u8 {
    var fba = std.heap.FixedBufferAllocator.init(buffer);
    return filesystem.readFileAlloc(fba.allocator(), autorun_list_path, buffer.len) catch |err| switch (err) {
        error.FileNotFound => "",
        else => return err,
    };
}

fn createReleaseDirectories(name: []const u8, release: []const u8) Error!void {
    var release_root_buffer: [filesystem.max_path_len]u8 = undefined;
    var release_dir_buffer: [filesystem.max_path_len]u8 = undefined;
    try filesystem.createDirPath(releasesRootPath(name, &release_root_buffer));
    try filesystem.createDirPath(try releaseDirPath(name, release, &release_dir_buffer));
}

fn writeReleaseMetadata(name: []const u8, release: []const u8, saved_seq: u32, saved_tick: u64) Error!void {
    var metadata_path_buffer: [filesystem.max_path_len]u8 = undefined;
    var body_buffer: [192]u8 = undefined;
    const body = std.fmt.bufPrint(
        &body_buffer,
        "workspace={s}\nrelease={s}\nsaved_seq={d}\nsaved_tick={d}\n",
        .{ name, release, saved_seq, saved_tick },
    ) catch return error.ResponseTooLarge;
    try filesystem.writeFile(try releaseMetadataPath(name, release, &metadata_path_buffer), body, saved_tick);
}

fn parseReleaseMetadata(payload: []const u8) Error!ReleaseMetadata {
    var metadata = ReleaseMetadata{};
    var lines = std.mem.splitScalar(u8, payload, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, "\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "workspace=")) {
            metadata.name = line["workspace=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, line, "release=")) {
            metadata.release = line["release=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, line, "saved_seq=")) {
            metadata.saved_seq = std.fmt.parseInt(u32, line["saved_seq=".len..], 10) catch return error.InvalidWorkspace;
            continue;
        }
        if (std.mem.startsWith(u8, line, "saved_tick=")) {
            metadata.saved_tick = std.fmt.parseInt(u64, line["saved_tick=".len..], 10) catch return error.InvalidWorkspace;
            continue;
        }
        return error.InvalidWorkspace;
    }
    return metadata;
}

fn nextReleaseSequence(name: []const u8) Error!u32 {
    var records: [filesystem.max_entries]ReleaseRecord = undefined;
    const record_count = try collectReleaseRecords(name, &records);
    var max_seq: u32 = 0;
    for (records[0..record_count]) |record| {
        max_seq = @max(max_seq, record.saved_seq);
    }
    return max_seq + 1;
}

fn collectReleaseRecords(name: []const u8, records: *[filesystem.max_entries]ReleaseRecord) Error!usize {
    var releases_buffer: [filesystem.max_path_len]u8 = undefined;
    const releases_root = releasesRootPath(name, &releases_buffer);

    var count: usize = 0;
    var idx: u32 = 0;
    while (idx < filesystem.max_entries) : (idx += 1) {
        const record = filesystem.entry(idx);
        if (record.kind != abi.filesystem_kind_directory) continue;
        const path = record.path[0..record.path_len];
        const release_name = directChildName(releases_root, path) orelse continue;
        if (release_name.len == 0) continue;
        if (findReleaseRecord(records[0..count], release_name) != null) continue;

        var saved_seq: u32 = 0;
        var metadata_path_buffer: [filesystem.max_path_len]u8 = undefined;
        const metadata_path = try releaseMetadataPath(name, release_name, &metadata_path_buffer);
        var metadata_scratch: [release_list_scan_max_bytes]u8 = undefined;
        var metadata_fba = std.heap.FixedBufferAllocator.init(&metadata_scratch);
        const metadata_raw = filesystem.readFileAlloc(metadata_fba.allocator(), metadata_path, metadata_scratch.len) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (metadata_raw) |raw| {
            const metadata = try parseReleaseMetadata(raw);
            saved_seq = metadata.saved_seq;
        }

        records[count] = .{
            .name_len = @intCast(release_name.len),
            .saved_seq = saved_seq,
        };
        @memcpy(records[count].name_storage[0..release_name.len], release_name);
        count += 1;
    }
    return count;
}

fn findReleaseRecord(records: []const ReleaseRecord, release_name: []const u8) ?usize {
    for (records, 0..) |record, index| {
        if (std.mem.eql(u8, record.name(), release_name)) return index;
    }
    return null;
}

fn directChildName(parent: []const u8, candidate: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, candidate, parent)) return null;
    if (candidate.len <= parent.len or candidate[parent.len] != '/') return null;
    const rest = candidate[parent.len + 1 ..];
    if (rest.len == 0) return null;
    const end_index = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
    if (end_index == 0) return null;
    return rest[0..end_index];
}

fn sortReleaseRecordsOldestFirst(records: []ReleaseRecord) void {
    var i: usize = 0;
    while (i < records.len) : (i += 1) {
        var best_index = i;
        var j: usize = i + 1;
        while (j < records.len) : (j += 1) {
            if (records[j].saved_seq < records[best_index].saved_seq) {
                best_index = j;
                continue;
            }
            if (records[j].saved_seq == records[best_index].saved_seq and std.mem.lessThan(u8, records[j].name(), records[best_index].name())) {
                best_index = j;
            }
        }
        if (best_index != i) std.mem.swap(ReleaseRecord, &records[i], &records[best_index]);
    }
}

fn sortReleaseRecordsNewestFirst(records: []ReleaseRecord) void {
    var i: usize = 0;
    while (i < records.len) : (i += 1) {
        var best_index = i;
        var j: usize = i + 1;
        while (j < records.len) : (j += 1) {
            if (records[j].saved_seq > records[best_index].saved_seq) {
                best_index = j;
                continue;
            }
            if (records[j].saved_seq == records[best_index].saved_seq and std.mem.lessThan(u8, records[best_index].name(), records[j].name())) {
                best_index = j;
            }
        }
        if (best_index != i) std.mem.swap(ReleaseRecord, &records[i], &records[best_index]);
    }
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
    var existing_scratch: [max_history_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&existing_scratch);
    const allocator = fba.allocator();
    const existing = filesystem.readFileAlloc(allocator, path, max_history_bytes) catch |err| switch (err) {
        error.FileNotFound => "",
        else => return err,
    };

    var rendered: [max_history_bytes]u8 = undefined;
    var used: usize = 0;
    if (existing.len != 0) {
        if (existing.len > rendered.len) return error.ResponseTooLarge;
        @memcpy(rendered[0..existing.len], existing);
        used = existing.len;
    }
    if (used + line.len > rendered.len) return error.ResponseTooLarge;
    @memcpy(rendered[used .. used + line.len], line);
    used += line.len;
    try filesystem.writeFile(path, rendered[0..used], tick);
}

test "workspace runtime saves applies and deletes orchestrated workspaces on ram disk" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    framebuffer_console.resetForTest();

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

    try saveWorkspace("ops", "duo", "root-a", 1024, 768, "demo:stable:r1", 18);

    const listing = try listAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("ops\n", listing);

    const info = try infoAlloc(std.testing.allocator, "ops", 512);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "workspace=ops") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "suite=duo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "trust_bundle=root-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "display=1024x768") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "state_path=/runtime/workspace-runs/ops/last_run.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "channel=demo:stable:r1") != null);

    try package_store.setPackageReleaseChannel("demo", "stable", "r2", 19);
    try package_store.activatePackageReleaseChannel("demo", "stable", 20);
    try trust_store.selectBundle("root-b", 21);
    try framebuffer_console.setMode(640, 400);
    try app_runtime.applyPlan("demo", "alt", 22);
    try app_runtime.applyPlan("aux", "fallback", 23);

    try applyWorkspace("ops", 24);

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

    try writeLastRun("ops", 0, "workspace-suite-r1\n", "", 25);

    const workspace_state = try stateAlloc(std.testing.allocator, "ops", 256);
    defer std.testing.allocator.free(workspace_state);
    try std.testing.expect(std.mem.indexOf(u8, workspace_state, "exit_code=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, workspace_state, "suite=duo") != null);

    const workspace_history = try historyAlloc(std.testing.allocator, "ops", 256);
    defer std.testing.allocator.free(workspace_history);
    try std.testing.expect(std.mem.indexOf(u8, workspace_history, "workspace=ops") != null);

    const workspace_stdout = try stdoutAlloc(std.testing.allocator, "ops", 64);
    defer std.testing.allocator.free(workspace_stdout);
    try std.testing.expectEqualStrings("workspace-suite-r1\n", workspace_stdout);

    try deleteWorkspace("ops", 26);
    try std.testing.expectError(error.WorkspaceNotFound, infoAlloc(std.testing.allocator, "ops", 128));
    try std.testing.expectError(error.WorkspaceStateNotFound, stateAlloc(std.testing.allocator, "ops", 64));
}

test "workspace runtime persists orchestrated workspaces on ata-backed storage" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    framebuffer_console.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try trust_store.installBundle("persisted-root", "persisted-cert", 1);
    try package_store.installScriptPackage("persisted", "echo persisted-r1", 2);
    try package_store.snapshotPackageRelease("persisted", "r1", 3);
    try package_store.setPackageReleaseChannel("persisted", "stable", "r1", 4);
    try app_runtime.savePlan("persisted", "boot", "", "persisted-root", abi.display_connector_virtual, 1280, 720, false, 5);
    try app_runtime.saveSuite("persisted-suite", "persisted:boot", 6);
    try saveWorkspace("persisted", "persisted-suite", "persisted-root", 1280, 720, "persisted:stable:r1", 7);

    filesystem.resetForTest();
    framebuffer_console.resetForTest();

    const listing = try listAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("persisted\n", listing);

    const info = try infoAlloc(std.testing.allocator, "persisted", 512);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "workspace=persisted") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "channel=persisted:stable:r1") != null);

    try applyWorkspace("persisted", 8);
    try writeLastRun("persisted", 0, "persisted-run\n", "", 9);

    filesystem.resetForTest();
    framebuffer_console.resetForTest();

    const persisted_state = try stateAlloc(std.testing.allocator, "persisted", 256);
    defer std.testing.allocator.free(persisted_state);
    try std.testing.expect(std.mem.indexOf(u8, persisted_state, "suite=persisted-suite") != null);

    const persisted_stdout = try stdoutAlloc(std.testing.allocator, "persisted", 64);
    defer std.testing.allocator.free(persisted_stdout);
    try std.testing.expectEqualStrings("persisted-run\n", persisted_stdout);

    try applyWorkspace("persisted", 10);
    try std.testing.expectEqual(@as(u32, 2048), ata_pio_disk.logicalBaseLba());

    const active_bundle = try trust_store.activeBundleNameAlloc(std.testing.allocator, trust_store.max_name_len);
    defer std.testing.allocator.free(active_bundle);
    try std.testing.expectEqualStrings("persisted-root", active_bundle);

    const display_state = framebuffer_console.statePtr();
    try std.testing.expectEqual(@as(u16, 1280), display_state.width);
    try std.testing.expectEqual(@as(u16, 720), display_state.height);

    const active_plan = try app_runtime.activePlanInfoAlloc(std.testing.allocator, "persisted", 256);
    defer std.testing.allocator.free(active_plan);
    try std.testing.expect(std.mem.indexOf(u8, active_plan, "active_plan=boot") != null);
}

test "workspace runtime persists autorun registry and clears stale entries" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    framebuffer_console.resetForTest();

    try package_store.installScriptPackage("demo", "echo demo-workspace", 1);
    try package_store.installScriptPackage("aux", "echo aux-workspace", 2);
    try app_runtime.savePlan("demo", "boot", "", "", abi.display_connector_virtual, 1024, 768, false, 3);
    try app_runtime.savePlan("aux", "sidecar", "", "", abi.display_connector_virtual, 800, 600, false, 4);
    try app_runtime.saveSuite("demo-suite", "demo:boot", 5);
    try app_runtime.saveSuite("aux-suite", "aux:sidecar", 6);
    try saveWorkspace("ops", "demo-suite", "", 1024, 768, "", 7);
    try saveWorkspace("sidecar", "aux-suite", "", 800, 600, "", 8);

    try addAutorun("ops", 9);
    try addAutorun("sidecar", 10);

    const autorun = try autorunListAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(autorun);
    try std.testing.expectEqualStrings("ops\nsidecar\n", autorun);

    try deleteWorkspace("ops", 11);
    const updated = try autorunListAlloc(std.testing.allocator, 128);
    defer std.testing.allocator.free(updated);
    try std.testing.expectEqualStrings("sidecar\n", updated);
}

test "workspace runtime snapshots activates deletes and prunes workspace releases" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    framebuffer_console.resetForTest();

    try trust_store.installBundle("root-a", "root-a-cert", 1);
    try trust_store.installBundle("root-b", "root-b-cert", 2);
    try package_store.installScriptPackage("demo", "echo release-r1", 3);
    try package_store.snapshotPackageRelease("demo", "r1", 4);
    try package_store.installScriptPackage("demo", "echo release-r2", 5);
    try package_store.snapshotPackageRelease("demo", "r2", 6);
    try package_store.installScriptPackage("demo", "echo release-r3", 7);
    try package_store.snapshotPackageRelease("demo", "r3", 8);
    try package_store.setPackageReleaseChannel("demo", "stable", "r1", 9);
    try package_store.activatePackageReleaseChannel("demo", "stable", 10);
    try app_runtime.savePlan("demo", "boot", "", "root-a", abi.display_connector_virtual, 1024, 768, false, 11);
    try app_runtime.saveSuite("demo-suite", "demo:boot", 12);
    try saveWorkspace("ops", "demo-suite", "root-a", 1024, 768, "demo:stable:r1", 13);

    try snapshotWorkspaceRelease("ops", "golden", 14);

    const initial_list = try releaseListAlloc(std.testing.allocator, "ops", 64);
    defer std.testing.allocator.free(initial_list);
    try std.testing.expectEqualStrings("golden\n", initial_list);

    try saveWorkspace("ops", "demo-suite", "root-b", 640, 400, "demo:stable:r3", 15);
    try snapshotWorkspaceRelease("ops", "staging", 16);

    const info = try releaseInfoAlloc(std.testing.allocator, "ops", "staging", 512);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "release=staging") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "saved_seq=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "trust_bundle=root-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "display=640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "channel=demo:stable:r3") != null);

    try activateWorkspaceRelease("ops", "golden", 17);
    const restored = try infoAlloc(std.testing.allocator, "ops", 512);
    defer std.testing.allocator.free(restored);
    try std.testing.expect(std.mem.indexOf(u8, restored, "trust_bundle=root-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored, "display=1024x768") != null);
    try std.testing.expect(std.mem.indexOf(u8, restored, "channel=demo:stable:r1") != null);

    try deleteWorkspaceRelease("ops", "staging", 18);
    const list_after_delete = try releaseListAlloc(std.testing.allocator, "ops", 64);
    defer std.testing.allocator.free(list_after_delete);
    try std.testing.expectEqualStrings("golden\n", list_after_delete);

    try saveWorkspace("ops", "demo-suite", "root-b", 1280, 720, "demo:stable:r2", 19);
    try snapshotWorkspaceRelease("ops", "fallback", 20);
    const prune_result = try pruneWorkspaceReleases("ops", 1, 21);
    try std.testing.expectEqual(@as(u32, 1), prune_result.kept_count);
    try std.testing.expectEqual(@as(u32, 1), prune_result.deleted_count);

    const final_list = try releaseListAlloc(std.testing.allocator, "ops", 64);
    defer std.testing.allocator.free(final_list);
    try std.testing.expectEqualStrings("fallback\n", final_list);

    try deleteWorkspace("ops", 22);
    try std.testing.expectError(error.WorkspaceNotFound, releaseListAlloc(std.testing.allocator, "ops", 64));
}
