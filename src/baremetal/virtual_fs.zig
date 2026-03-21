// SPDX-License-Identifier: GPL-2.0-only
const builtin = @import("builtin");
const std = @import("std");
const abi = @import("abi.zig");
const display_output = @import("display_output.zig");
const runtime_bridge = @import("runtime_bridge.zig");
const storage_backend = @import("storage_backend.zig");
const pal_net = @import("../pal/net.zig");

pub const Error = std.mem.Allocator.Error || error{
    FileNotFound,
    FileTooBig,
    NotDirectory,
    IsDirectory,
    ResponseTooLarge,
};

pub const SimpleStat = struct {
    kind: std.Io.File.Kind,
    size: u64,
    checksum: u32,
    modified_tick: u64,
    entry_id: u64,
};

const max_stat_render_bytes: usize = 16 * 1024;

const proc_version_path = "/proc/version";
const proc_runtime_path = "/proc/runtime";
const proc_runtime_snapshot_path = "/proc/runtime/snapshot";
const proc_runtime_sessions_path = "/proc/runtime/sessions";
const sys_kernel_version_path = "/sys/kernel/version";
const sys_kernel_machine_path = "/sys/kernel/machine";
const sys_storage_state_path = "/sys/storage/state";
const sys_display_state_path = "/sys/display/state";
const sys_display_outputs_path = "/sys/display/outputs";
const sys_net_state_path = "/sys/net/state";
const sys_net_route_path = "/sys/net/route";

pub fn handles(path: []const u8) bool {
    return std.mem.eql(u8, path, "/proc") or
        std.mem.startsWith(u8, path, "/proc/") or
        std.mem.eql(u8, path, "/sys") or
        std.mem.startsWith(u8, path, "/sys/");
}

pub fn isReadOnlyTree(path: []const u8) bool {
    return handles(path);
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
    if (isDirectoryPath(path)) return error.IsDirectory;
    const rendered = try renderFileAlloc(allocator, path);
    errdefer allocator.free(rendered);
    if (rendered.len > max_bytes) return error.FileTooBig;
    return rendered;
}

pub fn listDirectoryAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
    if (isFilePath(path)) return error.NotDirectory;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    if (std.mem.eql(u8, path, "/")) {
        try appendDirectoryLine(allocator, &out, "proc", max_bytes);
        try appendDirectoryLine(allocator, &out, "sys", max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, "/proc")) {
        try appendDirectoryLine(allocator, &out, "runtime", max_bytes);
        try appendFileLine(allocator, &out, "version", proc_version_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, proc_runtime_path)) {
        try appendFileLine(allocator, &out, "snapshot", proc_runtime_snapshot_path, max_bytes);
        try appendDirectoryLine(allocator, &out, "sessions", max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, proc_runtime_sessions_path)) {
        try appendRuntimeSessionDirectory(allocator, &out, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, "/sys")) {
        try appendDirectoryLine(allocator, &out, "kernel", max_bytes);
        try appendDirectoryLine(allocator, &out, "storage", max_bytes);
        try appendDirectoryLine(allocator, &out, "display", max_bytes);
        try appendDirectoryLine(allocator, &out, "net", max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, "/sys/kernel")) {
        try appendFileLine(allocator, &out, "version", sys_kernel_version_path, max_bytes);
        try appendFileLine(allocator, &out, "machine", sys_kernel_machine_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, "/sys/storage")) {
        try appendFileLine(allocator, &out, "state", sys_storage_state_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, "/sys/display")) {
        try appendFileLine(allocator, &out, "state", sys_display_state_path, max_bytes);
        try appendDirectoryLine(allocator, &out, "outputs", max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, sys_display_outputs_path)) {
        var index: u16 = 0;
        while (index < display_output.outputCount()) : (index += 1) {
            const name = try std.fmt.allocPrint(allocator, "{d}", .{index});
            defer allocator.free(name);
            try appendDirectoryLine(allocator, &out, name, max_bytes);
        }
        return out.toOwnedSlice(allocator);
    }
    if (parseOutputDirectory(path)) |output_index| {
        const entry = display_output.outputEntry(output_index);
        if (entry.connected == 0) return error.FileNotFound;
        try appendFileLineForPath(allocator, &out, "detail", try outputDetailPath(allocator, output_index), max_bytes);
        try appendFileLineForPath(allocator, &out, "modes", try outputModesPath(allocator, output_index), max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, "/sys/net")) {
        try appendFileLine(allocator, &out, "state", sys_net_state_path, max_bytes);
        try appendFileLine(allocator, &out, "route", sys_net_route_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }

    return error.FileNotFound;
}

pub fn statSummary(path: []const u8) Error!SimpleStat {
    if (isDirectoryPath(path)) {
        return .{
            .kind = .directory,
            .size = 0,
            .checksum = 0,
            .modified_tick = 0,
            .entry_id = checksumBytes(path),
        };
    }
    if (!isFilePath(path)) return error.FileNotFound;

    var scratch = [_]u8{0} ** max_stat_render_bytes;
    var fba = std.heap.FixedBufferAllocator.init(&scratch);
    const bytes = try readFileAlloc(fba.allocator(), path, scratch.len);
    return .{
        .kind = .file,
        .size = bytes.len,
        .checksum = checksumBytes(bytes),
        .modified_tick = 0,
        .entry_id = checksumBytes(path),
    };
}

fn isDirectoryPath(path: []const u8) bool {
    if (std.mem.eql(u8, path, "/")) return true;
    if (std.mem.eql(u8, path, "/proc")) return true;
    if (std.mem.eql(u8, path, proc_runtime_path)) return true;
    if (std.mem.eql(u8, path, proc_runtime_sessions_path)) return true;
    if (std.mem.eql(u8, path, "/sys")) return true;
    if (std.mem.eql(u8, path, "/sys/kernel")) return true;
    if (std.mem.eql(u8, path, "/sys/storage")) return true;
    if (std.mem.eql(u8, path, "/sys/display")) return true;
    if (std.mem.eql(u8, path, sys_display_outputs_path)) return true;
    if (std.mem.eql(u8, path, "/sys/net")) return true;
    return parseOutputDirectory(path) != null;
}

fn isFilePath(path: []const u8) bool {
    if (std.mem.eql(u8, path, proc_version_path)) return true;
    if (std.mem.eql(u8, path, proc_runtime_snapshot_path)) return true;
    if (parseRuntimeSessionPath(path) != null) return true;
    if (std.mem.eql(u8, path, sys_kernel_version_path)) return true;
    if (std.mem.eql(u8, path, sys_kernel_machine_path)) return true;
    if (std.mem.eql(u8, path, sys_storage_state_path)) return true;
    if (std.mem.eql(u8, path, sys_display_state_path)) return true;
    if (std.mem.eql(u8, path, sys_net_state_path)) return true;
    if (std.mem.eql(u8, path, sys_net_route_path)) return true;
    if (parseOutputFilePath(path) != null) return true;
    return false;
}

fn renderFileAlloc(allocator: std.mem.Allocator, path: []const u8) Error![]u8 {
    if (std.mem.eql(u8, path, proc_version_path)) {
        return std.fmt.allocPrint(
            allocator,
            "project=ZAR-Zig-Agent-Runtime\napi_version={d}\narch={s}\nos={s}\n",
            .{ abi.api_version, @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) },
        );
    }
    if (std.mem.eql(u8, path, proc_runtime_snapshot_path)) {
        return runtime_bridge.snapshotAlloc(allocator) catch error.FileNotFound;
    }
    if (parseRuntimeSessionPath(path)) |session_id| {
        return runtime_bridge.sessionInfoAlloc(allocator, session_id) catch |err| switch (err) {
            error.SessionNotFound => error.FileNotFound,
            else => error.FileNotFound,
        };
    }
    if (std.mem.eql(u8, path, sys_kernel_version_path)) {
        return std.fmt.allocPrint(
            allocator,
            "project=ZAR-Zig-Agent-Runtime\napi_version={d}\n",
            .{abi.api_version},
        );
    }
    if (std.mem.eql(u8, path, sys_kernel_machine_path)) {
        return std.fmt.allocPrint(
            allocator,
            "arch={s}\nos={s}\n",
            .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) },
        );
    }
    if (std.mem.eql(u8, path, sys_storage_state_path)) {
        return renderStorageStateAlloc(allocator);
    }
    if (std.mem.eql(u8, path, sys_display_state_path)) {
        return renderDisplayStateAlloc(allocator);
    }
    if (std.mem.eql(u8, path, sys_net_state_path)) {
        return renderNetStateAlloc(allocator);
    }
    if (std.mem.eql(u8, path, sys_net_route_path)) {
        return renderNetRouteAlloc(allocator);
    }
    if (parseOutputFilePath(path)) |request| {
        return switch (request.kind) {
            .detail => renderDisplayOutputDetailAlloc(allocator, request.index),
            .modes => renderDisplayOutputModesAlloc(allocator, request.index),
        };
    }
    return error.FileNotFound;
}

fn appendDirectoryLine(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, max_bytes: usize) Error!void {
    const line = try std.fmt.allocPrint(allocator, "dir {s}\n", .{name});
    defer allocator.free(line);
    if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
    try out.appendSlice(allocator, line);
}

fn appendFileLine(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, path: []const u8, max_bytes: usize) Error!void {
    const content = try renderFileAlloc(allocator, path);
    defer allocator.free(content);
    const line = try std.fmt.allocPrint(allocator, "file {s} {d}\n", .{ name, content.len });
    defer allocator.free(line);
    if (out.items.len + line.len > max_bytes) return error.ResponseTooLarge;
    try out.appendSlice(allocator, line);
}

fn appendFileLineForPath(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, owned_path: []u8, max_bytes: usize) Error!void {
    defer allocator.free(owned_path);
    try appendFileLine(allocator, out, name, owned_path, max_bytes);
}

fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) Error!void {
    const line = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(line);
    try out.appendSlice(allocator, line);
}

fn appendRuntimeSessionDirectory(allocator: std.mem.Allocator, out: *std.ArrayList(u8), max_bytes: usize) Error!void {
    const listing = runtime_bridge.sessionListAlloc(allocator) catch return error.FileNotFound;
    defer allocator.free(listing);
    var iterator = std.mem.splitScalar(u8, listing, '\n');
    while (iterator.next()) |session_id| {
        if (session_id.len == 0) continue;
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ proc_runtime_sessions_path, session_id });
        defer allocator.free(path);
        try appendFileLine(allocator, out, session_id, path, max_bytes);
    }
}

fn renderStorageStateAlloc(allocator: std.mem.Allocator) Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const state = storage_backend.statePtr();
    const selected_partition = storage_backend.selectedPartitionIndex();
    const selected_partition_text = if (selected_partition) |index|
        try std.fmt.allocPrint(allocator, "{d}", .{index})
    else
        try allocator.dupe(u8, "none");
    defer allocator.free(selected_partition_text);
    try appendFmt(
        allocator,
        &out,
        "backend={s}\nblock_size={d}\nblock_count={d}\nmounted={d}\nlogical_base_lba={d}\nselected_partition={s}\npartition_count={d}\n",
        .{
            storageBackendName(storage_backend.activeBackend()),
            state.block_size,
            state.block_count,
            state.mounted,
            storage_backend.logicalBaseLba(),
            selected_partition_text,
            storage_backend.partitionCount(),
        },
    );
    var index: u8 = 0;
    while (index < storage_backend.partitionCount()) : (index += 1) {
        const info = storage_backend.partitionInfo(index) orelse continue;
        try appendFmt(
            allocator,
            &out,
            "partition[{d}].scheme={s}\npartition[{d}].start_lba={d}\npartition[{d}].sector_count={d}\n",
            .{
                index,
                switch (info.scheme) {
                    .mbr => "mbr",
                    .gpt => "gpt",
                },
                index,
                info.start_lba,
                index,
                info.sector_count,
            },
        );
    }
    return out.toOwnedSlice(allocator);
}

fn renderDisplayStateAlloc(allocator: std.mem.Allocator) Error![]u8 {
    const state = display_output.statePtr();
    return std.fmt.allocPrint(
        allocator,
        "backend={d}\ncontroller={d}\nconnected={d}\ncurrent_width={d}\ncurrent_height={d}\npreferred_width={d}\npreferred_height={d}\noutputs={d}\ninterface={s}\n",
        .{
            state.backend,
            state.controller,
            state.connected,
            state.current_width,
            state.current_height,
            state.preferred_width,
            state.preferred_height,
            display_output.outputCount(),
            interfaceName(display_output.stateInterfaceType()),
        },
    );
}

fn renderDisplayOutputDetailAlloc(allocator: std.mem.Allocator, index: u16) Error![]u8 {
    const entry = display_output.outputEntry(index);
    if (entry.connected == 0) return error.FileNotFound;
    return std.fmt.allocPrint(
        allocator,
        "index={d}\nconnected={d}\nscanout_index={d}\nconnector_type={d}\ninterface={s}\ndeclared_interface={s}\ncurrent_width={d}\ncurrent_height={d}\npreferred_width={d}\npreferred_height={d}\nphysical_width_mm={d}\nphysical_height_mm={d}\nmanufacturer={s}\nmanufacture_week={d}\nmanufacture_year={d}\nedid_version={d}\nedid_revision={d}\nextensions={d}\ndisplay_name={s}\ncapability_flags={d}\n",
        .{
            index,
            entry.connected,
            entry.scanout_index,
            entry.connector_type,
            interfaceName(display_output.outputInterfaceType(index)),
            interfaceName(display_output.outputDeclaredInterfaceType(index)),
            entry.current_width,
            entry.current_height,
            entry.preferred_width,
            entry.preferred_height,
            entry.physical_width_mm,
            entry.physical_height_mm,
            display_output.outputManufacturerName(index),
            display_output.outputManufactureWeek(index),
            display_output.outputManufactureYear(index),
            display_output.outputEdidVersion(index),
            display_output.outputEdidRevision(index),
            display_output.outputExtensionCount(index),
            display_output.outputDisplayName(index),
            entry.capability_flags,
        },
    );
}

fn renderDisplayOutputModesAlloc(allocator: std.mem.Allocator, index: u16) Error![]u8 {
    const entry = display_output.outputEntry(index);
    if (entry.connected == 0) return error.FileNotFound;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var mode_index: u16 = 0;
    while (mode_index < display_output.outputModeCount(index)) : (mode_index += 1) {
        const mode = display_output.outputMode(index, mode_index) orelse continue;
        try appendFmt(
            allocator,
            &out,
            "mode[{d}]={d}x{d}@{d}\n",
            .{ mode_index, mode.width, mode.height, mode.refresh_hz },
        );
    }
    return out.toOwnedSlice(allocator);
}

fn renderNetStateAlloc(allocator: std.mem.Allocator) Error![]u8 {
    const route = pal_net.routeStatePtr();
    return std.fmt.allocPrint(
        allocator,
        "backend={s}\nconfigured={d}\nlocal_ip={d}.{d}.{d}.{d}\nsubnet_mask_valid={d}\ngateway_valid={d}\npending_resolution={d}\ncache_entries={d}\n",
        .{
            networkBackendName(pal_net.currentBackend()),
            @intFromBool(route.configured),
            route.local_ip[0],
            route.local_ip[1],
            route.local_ip[2],
            route.local_ip[3],
            @intFromBool(route.subnet_mask_valid),
            @intFromBool(route.gateway_valid),
            @intFromBool(route.pending_resolution),
            route.cache_entry_count,
        },
    );
}

fn renderNetRouteAlloc(allocator: std.mem.Allocator) Error![]u8 {
    const route = pal_net.routeStatePtr();
    return std.fmt.allocPrint(
        allocator,
        "gateway={d}.{d}.{d}.{d}\nlast_next_hop={d}.{d}.{d}.{d}\nlast_used_gateway={d}\nlast_cache_hit={d}\npending_ip={d}.{d}.{d}.{d}\n",
        .{
            route.gateway[0],
            route.gateway[1],
            route.gateway[2],
            route.gateway[3],
            route.last_next_hop[0],
            route.last_next_hop[1],
            route.last_next_hop[2],
            route.last_next_hop[3],
            @intFromBool(route.last_used_gateway),
            @intFromBool(route.last_cache_hit),
            route.pending_ip[0],
            route.pending_ip[1],
            route.pending_ip[2],
            route.pending_ip[3],
        },
    );
}

const OutputFileKind = enum {
    detail,
    modes,
};

const OutputFileRequest = struct {
    index: u16,
    kind: OutputFileKind,
};

fn parseRuntimeSessionPath(path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, proc_runtime_sessions_path)) return null;
    if (path.len <= proc_runtime_sessions_path.len or path[proc_runtime_sessions_path.len] != '/') return null;
    const session_id = path[proc_runtime_sessions_path.len + 1 ..];
    if (session_id.len == 0) return null;
    if (std.mem.indexOfScalar(u8, session_id, '/')) |_| return null;
    return session_id;
}

fn parseOutputDirectory(path: []const u8) ?u16 {
    if (!std.mem.startsWith(u8, path, sys_display_outputs_path)) return null;
    if (path.len <= sys_display_outputs_path.len or path[sys_display_outputs_path.len] != '/') return null;
    const tail = path[sys_display_outputs_path.len + 1 ..];
    if (tail.len == 0) return null;
    if (std.mem.indexOfScalar(u8, tail, '/')) |_| return null;
    return std.fmt.parseUnsigned(u16, tail, 10) catch null;
}

fn parseOutputFilePath(path: []const u8) ?OutputFileRequest {
    if (!std.mem.startsWith(u8, path, sys_display_outputs_path)) return null;
    if (path.len <= sys_display_outputs_path.len or path[sys_display_outputs_path.len] != '/') return null;
    const tail = path[sys_display_outputs_path.len + 1 ..];
    const slash = std.mem.indexOfScalar(u8, tail, '/') orelse return null;
    const index_text = tail[0..slash];
    const file_name = tail[slash + 1 ..];
    if (file_name.len == 0) return null;
    if (std.mem.indexOfScalar(u8, file_name, '/')) |_| return null;
    const index = std.fmt.parseUnsigned(u16, index_text, 10) catch return null;
    if (std.mem.eql(u8, file_name, "detail")) return .{ .index = index, .kind = .detail };
    if (std.mem.eql(u8, file_name, "modes")) return .{ .index = index, .kind = .modes };
    return null;
}

fn outputDetailPath(allocator: std.mem.Allocator, index: u16) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{d}/detail", .{ sys_display_outputs_path, index });
}

fn outputModesPath(allocator: std.mem.Allocator, index: u16) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{d}/modes", .{ sys_display_outputs_path, index });
}

fn checksumBytes(bytes: []const u8) u32 {
    var total: u32 = 0;
    for (bytes) |byte| total +%= byte;
    return total;
}

fn storageBackendName(backend: u8) []const u8 {
    return switch (backend) {
        abi.storage_backend_ram_disk => "ram_disk",
        abi.storage_backend_ata_pio => "ata_pio",
        else => "unknown",
    };
}

fn networkBackendName(backend: pal_net.Backend) []const u8 {
    return switch (backend) {
        .rtl8139 => "rtl8139",
        .e1000 => "e1000",
    };
}

fn interfaceName(interface_type: u8) []const u8 {
    return switch (interface_type) {
        abi.display_interface_dvi => "dvi",
        abi.display_interface_hdmi_a => "hdmi-a",
        abi.display_interface_hdmi_b => "hdmi-b",
        abi.display_interface_mddi => "mddi",
        abi.display_interface_displayport => "displayport",
        abi.display_interface_undefined => "undefined",
        else => "none",
    };
}
