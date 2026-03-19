// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const abi = @import("abi.zig");
const display_output = @import("display_output.zig");
const filesystem = @import("filesystem.zig");
const framebuffer_console = @import("framebuffer_console.zig");
const storage_backend = @import("storage_backend.zig");
const ata_pio_disk = @import("ata_pio_disk.zig");
const package_store = @import("package_store.zig");
const virtio_gpu = @import("virtio_gpu.zig");

pub const max_name_len: usize = 32;

const root_dir = "/runtime/display-profiles";
const profiles_dir = "/runtime/display-profiles/profiles";
const active_profile_path = "/runtime/display-profiles/active.txt";

pub const Error = filesystem.Error || std.mem.Allocator.Error || error{
    InvalidProfileName,
    InvalidProfileMetadata,
    DisplayProfileNotFound,
    ActiveProfileNotSet,
    DisplayOutputNotFound,
    DisplayOutputUnsupportedMode,
    ResponseTooLarge,
};

const LoadedProfile = struct {
    name_len: usize = 0,
    name_storage: [max_name_len]u8 = [_]u8{0} ** max_name_len,
    backend: u8 = abi.display_backend_none,
    controller: u8 = abi.display_controller_none,
    connector_type: u8 = abi.display_connector_none,
    output_index: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,

    fn name(self: *const @This()) []const u8 {
        return self.name_storage[0..self.name_len];
    }
};

pub fn profilePath(name: []const u8, buffer: *[filesystem.max_path_len]u8) Error![]const u8 {
    try validateProfileName(name);
    return std.fmt.bufPrint(buffer, "{s}/{s}.txt", .{ profiles_dir, name }) catch error.InvalidPath;
}

pub fn saveCurrentProfile(name: []const u8, tick: u64) Error!void {
    try validateProfileName(name);
    try ensureLayout();
    ensureDisplayReady();

    const state = display_output.statePtr();
    if (display_output.outputCount() == 0) return error.InvalidProfileMetadata;

    const output_index: u16 = if (state.active_scanout < display_output.outputCount())
        @as(u16, state.active_scanout)
    else
        0;
    const entry = display_output.outputEntry(output_index);
    const width: u16 = if (entry.current_width != 0) entry.current_width else state.current_width;
    const height: u16 = if (entry.current_height != 0) entry.current_height else state.current_height;
    const connector_type: u8 = if (entry.connector_type != abi.display_connector_none) entry.connector_type else state.connector_type;

    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try profilePath(name, &path_buffer);

    var rendered: [256]u8 = undefined;
    const content = std.fmt.bufPrint(
        &rendered,
        "name={s}\nbackend={s}\ncontroller={s}\nconnector={s}\noutput_index={d}\nwidth={d}\nheight={d}\n",
        .{
            name,
            backendName(state.backend),
            controllerName(state.controller),
            package_store.connectorNameFromType(connector_type),
            output_index,
            width,
            height,
        },
    ) catch return error.ResponseTooLarge;
    try filesystem.writeFile(path, content, tick);
}

pub fn listProfilesAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    try filesystem.init();

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var idx: u32 = 0;
    while (idx < filesystem.max_entries) : (idx += 1) {
        const record = filesystem.entry(idx);
        if (record.kind == 0) continue;
        const path = record.path[0..record.path_len];
        const name = profileNameFromPath(path) orelse continue;

        const line = try std.fmt.allocPrint(allocator, "{s}\n", .{name});
        defer allocator.free(line);
        if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

pub fn infoAlloc(allocator: std.mem.Allocator, name: []const u8, max_bytes: usize) Error![]u8 {
    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try profilePath(name, &path_buffer);
    const profile = try loadProfile(name);
    const selected = try isActiveProfile(name);

    const response = try std.fmt.allocPrint(
        allocator,
        "name={s}\npath={s}\nbackend={s}\ncontroller={s}\nconnector={s}\noutput_index={d}\nwidth={d}\nheight={d}\nselected={d}\n",
        .{
            profile.name(),
            path,
            backendName(profile.backend),
            controllerName(profile.controller),
            package_store.connectorNameFromType(profile.connector_type),
            profile.output_index,
            profile.width,
            profile.height,
            @intFromBool(selected),
        },
    );
    errdefer allocator.free(response);
    if (response.len > max_bytes) return error.ResponseTooLarge;
    return response;
}

pub fn applyProfile(name: []const u8, tick: u64) Error!void {
    const profile = try loadProfile(name);
    ensureDisplayReady();
    const display_state = display_output.statePtr();
    if (display_state.controller == abi.display_controller_virtio_gpu) {
        if (display_state.hardware_backed != 0) {
            _ = virtio_gpu.probeAndPresentPatternForOutputIndexMode(@intCast(profile.output_index), profile.width, profile.height) catch |err| switch (err) {
                error.NoConnectedScanout => return error.DisplayOutputNotFound,
                error.UnsupportedMode, error.FramebufferTooLarge => return error.DisplayOutputUnsupportedMode,
                else => return error.DisplayOutputNotFound,
            };
        } else {
            const entry = display_output.outputEntry(profile.output_index);
            if (profile.output_index >= display_output.outputCount() or entry.connected == 0) return error.DisplayOutputNotFound;
            if (!display_output.setOutputMode(profile.output_index, profile.width, profile.height)) {
                return error.DisplayOutputUnsupportedMode;
            }
        }
    } else {
        if (profile.output_index != 0) return error.DisplayOutputNotFound;
        framebuffer_console.setMode(profile.width, profile.height) catch return error.DisplayOutputUnsupportedMode;
    }
    try filesystem.writeFile(active_profile_path, profile.name(), tick);
}

pub fn deleteProfile(name: []const u8, tick: u64) Error!void {
    try validateProfileName(name);
    try ensureLayout();

    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try profilePath(name, &path_buffer);
    filesystem.deleteFile(path, tick) catch |err| switch (err) {
        error.FileNotFound => return error.DisplayProfileNotFound,
        else => return err,
    };

    if (try isActiveProfile(name)) {
        clearActiveProfile(tick) catch |err| switch (err) {
            error.ActiveProfileNotSet => {},
            else => return err,
        };
    }
}

pub fn activeProfileNameAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const name = filesystem.readFileAlloc(allocator, active_profile_path, max_bytes) catch |err| switch (err) {
        error.FileNotFound => return error.ActiveProfileNotSet,
        else => return err,
    };
    errdefer allocator.free(name);
    try validateProfileName(name);
    return name;
}

pub fn activeProfileInfoAlloc(allocator: std.mem.Allocator, max_bytes: usize) Error![]u8 {
    const active_name = try activeProfileNameAlloc(allocator, max_name_len);
    defer allocator.free(active_name);
    return infoAlloc(allocator, active_name, max_bytes);
}

fn ensureLayout() Error!void {
    try filesystem.init();
    try filesystem.createDirPath(root_dir);
    try filesystem.createDirPath(profiles_dir);
}

fn ensureDisplayReady() void {
    if (display_output.statePtr().backend == abi.display_backend_none) {
        _ = framebuffer_console.init();
    }
}

fn validateProfileName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > max_name_len) return error.InvalidProfileName;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.') continue;
        return error.InvalidProfileName;
    }
}

fn profileNameFromPath(path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, profiles_dir ++ "/")) return null;
    if (!std.mem.endsWith(u8, path, ".txt")) return null;

    const name = path[(profiles_dir ++ "/").len .. path.len - ".txt".len];
    if (name.len == 0 or std.mem.indexOfScalar(u8, name, '/') != null) return null;
    return name;
}

fn loadProfile(name: []const u8) Error!LoadedProfile {
    try validateProfileName(name);

    var path_buffer: [filesystem.max_path_len]u8 = undefined;
    const path = try profilePath(name, &path_buffer);

    var scratch: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&scratch);
    const raw = filesystem.readFileAlloc(fba.allocator(), path, scratch.len) catch |err| switch (err) {
        error.FileNotFound => return error.DisplayProfileNotFound,
        else => return err,
    };
    return parseProfile(raw);
}

fn parseProfile(raw: []const u8) Error!LoadedProfile {
    var profile = LoadedProfile{};
    var saw_name = false;
    var saw_backend = false;
    var saw_controller = false;
    var saw_connector = false;
    var saw_output = false;
    var saw_width = false;
    var saw_height = false;

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "name=")) {
            const value = line["name=".len..];
            try validateProfileName(value);
            profile.name_len = value.len;
            @memset(&profile.name_storage, 0);
            @memcpy(profile.name_storage[0..value.len], value);
            saw_name = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "backend=")) {
            profile.backend = parseBackend(line["backend=".len..]) catch return error.InvalidProfileMetadata;
            saw_backend = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "controller=")) {
            profile.controller = parseController(line["controller=".len..]) catch return error.InvalidProfileMetadata;
            saw_controller = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "connector=")) {
            profile.connector_type = package_store.parseConnectorType(line["connector=".len..]) catch return error.InvalidProfileMetadata;
            saw_connector = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "output_index=")) {
            profile.output_index = std.fmt.parseInt(u16, line["output_index=".len..], 10) catch return error.InvalidProfileMetadata;
            saw_output = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "width=")) {
            profile.width = std.fmt.parseInt(u16, line["width=".len..], 10) catch return error.InvalidProfileMetadata;
            saw_width = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, "height=")) {
            profile.height = std.fmt.parseInt(u16, line["height=".len..], 10) catch return error.InvalidProfileMetadata;
            saw_height = true;
            continue;
        }
    }

    if (!saw_name or !saw_backend or !saw_controller or !saw_connector or !saw_output or !saw_width or !saw_height) {
        return error.InvalidProfileMetadata;
    }
    if (profile.width == 0 or profile.height == 0) return error.InvalidProfileMetadata;
    return profile;
}

fn parseBackend(name: []const u8) error{InvalidProfileMetadata}!u8 {
    if (std.ascii.eqlIgnoreCase(name, "bga")) return abi.display_backend_bga;
    if (std.ascii.eqlIgnoreCase(name, "virtio-gpu")) return abi.display_backend_virtio_gpu;
    if (std.ascii.eqlIgnoreCase(name, "none")) return abi.display_backend_none;
    return error.InvalidProfileMetadata;
}

fn parseController(name: []const u8) error{InvalidProfileMetadata}!u8 {
    if (std.ascii.eqlIgnoreCase(name, "bochs-bga")) return abi.display_controller_bochs_bga;
    if (std.ascii.eqlIgnoreCase(name, "virtio-gpu")) return abi.display_controller_virtio_gpu;
    if (std.ascii.eqlIgnoreCase(name, "none")) return abi.display_controller_none;
    return error.InvalidProfileMetadata;
}

fn backendName(value: u8) []const u8 {
    return switch (value) {
        abi.display_backend_bga => "bga",
        abi.display_backend_virtio_gpu => "virtio-gpu",
        else => "none",
    };
}

fn controllerName(value: u8) []const u8 {
    return switch (value) {
        abi.display_controller_bochs_bga => "bochs-bga",
        abi.display_controller_virtio_gpu => "virtio-gpu",
        else => "none",
    };
}

fn isActiveProfile(name: []const u8) Error!bool {
    var scratch: [max_name_len]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&scratch);
    const active_name = activeProfileNameAlloc(fba.allocator(), max_name_len) catch |err| switch (err) {
        error.ActiveProfileNotSet => return false,
        else => return err,
    };
    return std.mem.eql(u8, active_name, name);
}

fn clearActiveProfile(tick: u64) Error!void {
    try ensureLayout();
    filesystem.deleteFile(active_profile_path, tick) catch |err| switch (err) {
        error.FileNotFound => return error.ActiveProfileNotSet,
        else => return err,
    };
}

test "display profile store persists and reapplies profiles on the ram disk" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    framebuffer_console.resetForTest();
    display_output.resetForTest();

    try std.testing.expect(framebuffer_console.initMode(1024, 768));
    try saveCurrentProfile("golden", 3);

    const listing = try listProfilesAlloc(std.testing.allocator, 64);
    defer std.testing.allocator.free(listing);
    try std.testing.expectEqualStrings("golden\n", listing);

    const info = try infoAlloc(std.testing.allocator, "golden", 256);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "backend=bga") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "width=1024") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "height=768") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "selected=0") != null);

    try framebuffer_console.setMode(800, 600);
    try applyProfile("golden", 4);

    const state = display_output.statePtr();
    try std.testing.expectEqual(@as(u16, 1024), state.current_width);
    try std.testing.expectEqual(@as(u16, 768), state.current_height);

    const active_name = try activeProfileNameAlloc(std.testing.allocator, max_name_len);
    defer std.testing.allocator.free(active_name);
    try std.testing.expectEqualStrings("golden", active_name);

    const active_info = try activeProfileInfoAlloc(std.testing.allocator, 256);
    defer std.testing.allocator.free(active_info);
    try std.testing.expect(std.mem.indexOf(u8, active_info, "selected=1") != null);

    try deleteProfile("golden", 5);
    const empty_listing = try listProfilesAlloc(std.testing.allocator, 64);
    defer std.testing.allocator.free(empty_listing);
    try std.testing.expectEqualStrings("", empty_listing);
    try std.testing.expectError(error.ActiveProfileNotSet, activeProfileNameAlloc(std.testing.allocator, max_name_len));
}

test "display profile store persists on ata-backed storage" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    framebuffer_console.resetForTest();
    display_output.resetForTest();
    ata_pio_disk.testEnableMockDevice(8192);
    ata_pio_disk.testInstallMockMbrPartition(2048, 4096, 0x83);
    defer ata_pio_disk.testDisableMockDevice();

    try std.testing.expect(framebuffer_console.initMode(1280, 720));
    try saveCurrentProfile("persisted", 11);
    try framebuffer_console.setMode(800, 600);

    filesystem.resetForTest();
    framebuffer_console.resetForTest();
    display_output.resetForTest();

    try applyProfile("persisted", 12);
    try std.testing.expectEqual(@as(u32, 2048), ata_pio_disk.logicalBaseLba());

    const info = try infoAlloc(std.testing.allocator, "persisted", 256);
    defer std.testing.allocator.free(info);
    try std.testing.expect(std.mem.indexOf(u8, info, "width=1280") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "height=720") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "selected=1") != null);

    const state = display_output.statePtr();
    try std.testing.expectEqual(@as(u16, 1280), state.current_width);
    try std.testing.expectEqual(@as(u16, 720), state.current_height);
}

test "display profile store rejects unknown profiles" {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    framebuffer_console.resetForTest();
    display_output.resetForTest();

    try std.testing.expectError(error.DisplayProfileNotFound, applyProfile("missing", 1));
}
