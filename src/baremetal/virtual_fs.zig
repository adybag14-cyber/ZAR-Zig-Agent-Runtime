// SPDX-License-Identifier: GPL-2.0-only
const builtin = @import("builtin");
const std = @import("std");
const abi = @import("abi.zig");
const acpi = @import("acpi.zig");
const acpi_pm_timer = @import("acpi_pm_timer.zig");
const boot_memory = @import("boot_memory.zig");
const physical_memory = @import("physical_memory.zig");
const i386_ap_startup = @import("i386_ap_startup.zig");
const ioapic = @import("ioapic.zig");
const lapic = @import("lapic.zig");
const pic = @import("pic.zig");
const pit = @import("pit.zig");
const display_output = @import("display_output.zig");
const runtime_bridge = @import("runtime_bridge.zig");
const storage_backend = @import("storage_backend.zig");
const storage_backend_registry = @import("storage_backend_registry.zig");
const storage_registry = @import("storage_registry.zig");
const tty_runtime = @import("tty_runtime.zig");
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
const dev_null_path = "/dev/null";
const dev_storage_path = "/dev/storage";
const dev_storage_state_path = "/dev/storage/state";
const dev_storage_backends_path = "/dev/storage/backends";
const dev_storage_filesystems_path = "/dev/storage/filesystems";
const dev_storage_registry_path = "/dev/storage/registry";
const dev_tty_path = "/dev/tty";
const dev_tty_state_path = "/dev/tty/state";
const dev_tty_sessions_path = "/dev/tty/sessions";
const dev_display_path = "/dev/display";
const dev_display_state_path = "/dev/display/state";
const dev_display_outputs_path = "/dev/display/outputs";
const dev_memory_path = "/dev/memory";
const dev_memory_state_path = "/dev/memory/state";
const dev_memory_map_path = "/dev/memory/map";
const dev_cpu_path = "/dev/cpu";
const dev_cpu_state_path = "/dev/cpu/state";
const dev_cpu_topology_path = "/dev/cpu/topology";
const dev_cpu_lapic_path = "/dev/cpu/lapic";
const dev_cpu_ioapic_path = "/dev/cpu/ioapic";
const dev_cpu_pic_path = "/dev/cpu/pic";
const dev_cpu_pit_path = "/dev/cpu/pit";
const dev_cpu_smp_path = "/dev/cpu/smp";
const dev_cpu_ap_startup_path = "/dev/cpu/ap-startup";
const dev_cpu_ap_work_path = "/dev/cpu/ap-work";
const dev_cpu_ap_tasks_path = "/dev/cpu/ap-tasks";
const dev_cpu_ap_multi_path = "/dev/cpu/ap-multi";
const dev_cpu_ap_slots_path = "/dev/cpu/ap-slots";
const dev_cpu_ap_ownership_path = "/dev/cpu/ap-ownership";
const dev_cpu_ap_redistribution_path = "/dev/cpu/ap-redistribution";
const dev_cpu_ap_failover_path = "/dev/cpu/ap-failover";
const dev_cpu_ap_backfill_path = "/dev/cpu/ap-backfill";
const dev_cpu_ap_window_path = "/dev/cpu/ap-window";
const dev_net_path = "/dev/net";
const dev_net_state_path = "/dev/net/state";
const dev_net_route_path = "/dev/net/route";
const sys_kernel_version_path = "/sys/kernel/version";
const sys_kernel_machine_path = "/sys/kernel/machine";
const sys_acpi_path = "/sys/acpi";
const sys_acpi_state_path = "/sys/acpi/state";
const sys_acpi_pm_timer_path = "/sys/acpi/pm-timer";
const sys_memory_path = "/sys/memory";
const sys_memory_state_path = "/sys/memory/state";
const sys_memory_map_path = "/sys/memory/map";
const sys_cpu_path = "/sys/cpu";
const sys_cpu_state_path = "/sys/cpu/state";
const sys_cpu_topology_path = "/sys/cpu/topology";
const sys_cpu_lapic_path = "/sys/cpu/lapic";
const sys_cpu_ioapic_path = "/sys/cpu/ioapic";
const sys_cpu_pic_path = "/sys/cpu/pic";
const sys_cpu_pit_path = "/sys/cpu/pit";
const sys_cpu_smp_path = "/sys/cpu/smp";
const sys_cpu_ap_startup_path = "/sys/cpu/ap-startup";
const sys_cpu_ap_work_path = "/sys/cpu/ap-work";
const sys_cpu_ap_tasks_path = "/sys/cpu/ap-tasks";
const sys_cpu_ap_multi_path = "/sys/cpu/ap-multi";
const sys_cpu_ap_slots_path = "/sys/cpu/ap-slots";
const sys_cpu_ap_ownership_path = "/sys/cpu/ap-ownership";
const sys_cpu_ap_redistribution_path = "/sys/cpu/ap-redistribution";
const sys_cpu_ap_failover_path = "/sys/cpu/ap-failover";
const sys_cpu_ap_backfill_path = "/sys/cpu/ap-backfill";
const sys_cpu_ap_window_path = "/sys/cpu/ap-window";
const sys_storage_state_path = "/sys/storage/state";
const sys_storage_backends_path = "/sys/storage/backends";
const sys_storage_filesystems_path = "/sys/storage/filesystems";
const sys_storage_registry_path = "/sys/storage/registry";
const sys_tty_path = "/sys/tty";
const sys_tty_state_path = "/sys/tty/state";
const sys_tty_sessions_path = "/sys/tty/sessions";
const sys_display_state_path = "/sys/display/state";
const sys_display_outputs_path = "/sys/display/outputs";
const sys_net_state_path = "/sys/net/state";
const sys_net_route_path = "/sys/net/route";

pub fn handles(path: []const u8) bool {
    return std.mem.eql(u8, path, "/proc") or
        std.mem.startsWith(u8, path, "/proc/") or
        std.mem.eql(u8, path, "/dev") or
        std.mem.startsWith(u8, path, "/dev/") or
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

pub fn readFile(path: []const u8, buffer: []u8) Error![]const u8 {
    if (isDirectoryPath(path)) return error.IsDirectory;
    var fba = std.heap.FixedBufferAllocator.init(buffer);
    const rendered = try renderFileAlloc(fba.allocator(), path);
    if (rendered.len > buffer.len) return error.FileTooBig;
    return rendered;
}

pub fn listDirectoryAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
    if (isFilePath(path)) return error.NotDirectory;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    if (std.mem.eql(u8, path, "/")) {
        try appendDirectoryLine(allocator, &out, "dev", max_bytes);
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
    if (std.mem.eql(u8, path, "/dev")) {
        try appendDirectoryLine(allocator, &out, "storage", max_bytes);
        try appendDirectoryLine(allocator, &out, "tty", max_bytes);
        try appendDirectoryLine(allocator, &out, "display", max_bytes);
        try appendDirectoryLine(allocator, &out, "memory", max_bytes);
        try appendDirectoryLine(allocator, &out, "cpu", max_bytes);
        try appendDirectoryLine(allocator, &out, "net", max_bytes);
        try appendFileLine(allocator, &out, "null", dev_null_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, dev_storage_path)) {
        try appendFileLine(allocator, &out, "state", dev_storage_state_path, max_bytes);
        try appendFileLine(allocator, &out, "backends", dev_storage_backends_path, max_bytes);
        try appendFileLine(allocator, &out, "filesystems", dev_storage_filesystems_path, max_bytes);
        try appendFileLine(allocator, &out, "registry", dev_storage_registry_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, dev_tty_path)) {
        try appendFileLine(allocator, &out, "state", dev_tty_state_path, max_bytes);
        try appendDirectoryLine(allocator, &out, "sessions", max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, dev_tty_sessions_path)) {
        try appendTtySessionDirectory(allocator, &out, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (parseDevTtySessionDirectory(path)) |session_name| {
        try appendFileLineForPath(allocator, &out, "info", try ttySessionFilePathForBase(allocator, dev_tty_sessions_path, session_name, "info"), max_bytes);
        try appendFileLineForPath(allocator, &out, "input", try ttySessionFilePathForBase(allocator, dev_tty_sessions_path, session_name, "input"), max_bytes);
        try appendFileLineForPath(allocator, &out, "pending", try ttySessionFilePathForBase(allocator, dev_tty_sessions_path, session_name, "pending"), max_bytes);
        try appendFileLineForPath(allocator, &out, "stdout", try ttySessionFilePathForBase(allocator, dev_tty_sessions_path, session_name, "stdout"), max_bytes);
        try appendFileLineForPath(allocator, &out, "stderr", try ttySessionFilePathForBase(allocator, dev_tty_sessions_path, session_name, "stderr"), max_bytes);
        try appendFileLineForPath(allocator, &out, "events", try ttySessionFilePathForBase(allocator, dev_tty_sessions_path, session_name, "events"), max_bytes);
        try appendFileLineForPath(allocator, &out, "transcript", try ttySessionFilePathForBase(allocator, dev_tty_sessions_path, session_name, "transcript"), max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, dev_display_path)) {
        try appendFileLine(allocator, &out, "state", dev_display_state_path, max_bytes);
        try appendDirectoryLine(allocator, &out, "outputs", max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, dev_memory_path)) {
        try appendFileLine(allocator, &out, "state", dev_memory_state_path, max_bytes);
        try appendFileLine(allocator, &out, "map", dev_memory_map_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_path)) {
        try appendFileLine(allocator, &out, "state", dev_cpu_state_path, max_bytes);
        try appendFileLine(allocator, &out, "topology", dev_cpu_topology_path, max_bytes);
        try appendFileLine(allocator, &out, "lapic", dev_cpu_lapic_path, max_bytes);
        try appendFileLine(allocator, &out, "ioapic", dev_cpu_ioapic_path, max_bytes);
        try appendFileLine(allocator, &out, "pic", dev_cpu_pic_path, max_bytes);
        try appendFileLine(allocator, &out, "pit", dev_cpu_pit_path, max_bytes);
        try appendFileLine(allocator, &out, "smp", dev_cpu_smp_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-startup", dev_cpu_ap_startup_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-work", dev_cpu_ap_work_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-tasks", dev_cpu_ap_tasks_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-multi", dev_cpu_ap_multi_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-slots", dev_cpu_ap_slots_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-ownership", dev_cpu_ap_ownership_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-redistribution", dev_cpu_ap_redistribution_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-failover", dev_cpu_ap_failover_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-backfill", dev_cpu_ap_backfill_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-window", dev_cpu_ap_window_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, dev_display_outputs_path)) {
        var dev_index: u16 = 0;
        while (dev_index < display_output.outputCount()) : (dev_index += 1) {
            const name = try std.fmt.allocPrint(allocator, "{d}", .{dev_index});
            defer allocator.free(name);
            try appendDirectoryLine(allocator, &out, name, max_bytes);
        }
        return out.toOwnedSlice(allocator);
    }
    if (parseDevOutputDirectory(path)) |output_index| {
        const entry = display_output.outputEntry(output_index);
        if (entry.connected == 0) return error.FileNotFound;
        try appendFileLineForPath(allocator, &out, "detail", try outputDetailPathForBase(allocator, dev_display_outputs_path, output_index), max_bytes);
        try appendFileLineForPath(allocator, &out, "modes", try outputModesPathForBase(allocator, dev_display_outputs_path, output_index), max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, dev_net_path)) {
        try appendFileLine(allocator, &out, "state", dev_net_state_path, max_bytes);
        try appendFileLine(allocator, &out, "route", dev_net_route_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, "/sys")) {
        try appendDirectoryLine(allocator, &out, "kernel", max_bytes);
        try appendDirectoryLine(allocator, &out, "acpi", max_bytes);
        try appendDirectoryLine(allocator, &out, "memory", max_bytes);
        try appendDirectoryLine(allocator, &out, "cpu", max_bytes);
        try appendDirectoryLine(allocator, &out, "storage", max_bytes);
        try appendDirectoryLine(allocator, &out, "tty", max_bytes);
        try appendDirectoryLine(allocator, &out, "display", max_bytes);
        try appendDirectoryLine(allocator, &out, "net", max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, "/sys/kernel")) {
        try appendFileLine(allocator, &out, "version", sys_kernel_version_path, max_bytes);
        try appendFileLine(allocator, &out, "machine", sys_kernel_machine_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, sys_acpi_path)) {
        try appendFileLine(allocator, &out, "state", sys_acpi_state_path, max_bytes);
        try appendFileLine(allocator, &out, "pm-timer", sys_acpi_pm_timer_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, sys_memory_path)) {
        try appendFileLine(allocator, &out, "state", sys_memory_state_path, max_bytes);
        try appendFileLine(allocator, &out, "map", sys_memory_map_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, sys_cpu_path)) {
        try appendFileLine(allocator, &out, "state", sys_cpu_state_path, max_bytes);
        try appendFileLine(allocator, &out, "topology", sys_cpu_topology_path, max_bytes);
        try appendFileLine(allocator, &out, "lapic", sys_cpu_lapic_path, max_bytes);
        try appendFileLine(allocator, &out, "ioapic", sys_cpu_ioapic_path, max_bytes);
        try appendFileLine(allocator, &out, "pic", sys_cpu_pic_path, max_bytes);
        try appendFileLine(allocator, &out, "pit", sys_cpu_pit_path, max_bytes);
        try appendFileLine(allocator, &out, "smp", sys_cpu_smp_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-startup", sys_cpu_ap_startup_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-work", sys_cpu_ap_work_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-tasks", sys_cpu_ap_tasks_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-multi", sys_cpu_ap_multi_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-slots", sys_cpu_ap_slots_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-ownership", sys_cpu_ap_ownership_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-redistribution", sys_cpu_ap_redistribution_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-failover", sys_cpu_ap_failover_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-backfill", sys_cpu_ap_backfill_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-window", sys_cpu_ap_window_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, "/sys/storage")) {
        try appendFileLine(allocator, &out, "state", sys_storage_state_path, max_bytes);
        try appendFileLine(allocator, &out, "backends", sys_storage_backends_path, max_bytes);
        try appendFileLine(allocator, &out, "filesystems", sys_storage_filesystems_path, max_bytes);
        try appendFileLine(allocator, &out, "registry", sys_storage_registry_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, sys_tty_path)) {
        try appendFileLine(allocator, &out, "state", sys_tty_state_path, max_bytes);
        try appendDirectoryLine(allocator, &out, "sessions", max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, sys_tty_sessions_path)) {
        try appendTtySessionDirectory(allocator, &out, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (parseSysTtySessionDirectory(path)) |session_name| {
        try appendFileLineForPath(allocator, &out, "info", try ttySessionFilePathForBase(allocator, sys_tty_sessions_path, session_name, "info"), max_bytes);
        try appendFileLineForPath(allocator, &out, "input", try ttySessionFilePathForBase(allocator, sys_tty_sessions_path, session_name, "input"), max_bytes);
        try appendFileLineForPath(allocator, &out, "pending", try ttySessionFilePathForBase(allocator, sys_tty_sessions_path, session_name, "pending"), max_bytes);
        try appendFileLineForPath(allocator, &out, "stdout", try ttySessionFilePathForBase(allocator, sys_tty_sessions_path, session_name, "stdout"), max_bytes);
        try appendFileLineForPath(allocator, &out, "stderr", try ttySessionFilePathForBase(allocator, sys_tty_sessions_path, session_name, "stderr"), max_bytes);
        try appendFileLineForPath(allocator, &out, "events", try ttySessionFilePathForBase(allocator, sys_tty_sessions_path, session_name, "events"), max_bytes);
        try appendFileLineForPath(allocator, &out, "transcript", try ttySessionFilePathForBase(allocator, sys_tty_sessions_path, session_name, "transcript"), max_bytes);
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
    if (std.mem.eql(u8, path, "/dev")) return true;
    if (std.mem.eql(u8, path, dev_storage_path)) return true;
    if (std.mem.eql(u8, path, dev_tty_path)) return true;
    if (std.mem.eql(u8, path, dev_tty_sessions_path)) return true;
    if (std.mem.eql(u8, path, dev_display_path)) return true;
    if (std.mem.eql(u8, path, dev_memory_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_path)) return true;
    if (std.mem.eql(u8, path, dev_display_outputs_path)) return true;
    if (std.mem.eql(u8, path, dev_net_path)) return true;
    if (std.mem.eql(u8, path, "/sys")) return true;
    if (std.mem.eql(u8, path, "/sys/kernel")) return true;
    if (std.mem.eql(u8, path, sys_acpi_path)) return true;
    if (std.mem.eql(u8, path, sys_memory_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_path)) return true;
    if (std.mem.eql(u8, path, "/sys/storage")) return true;
    if (std.mem.eql(u8, path, sys_tty_path)) return true;
    if (std.mem.eql(u8, path, sys_tty_sessions_path)) return true;
    if (std.mem.eql(u8, path, "/sys/display")) return true;
    if (std.mem.eql(u8, path, sys_display_outputs_path)) return true;
    if (std.mem.eql(u8, path, "/sys/net")) return true;
    if (parseDevOutputDirectory(path)) |_| return true;
    if (parseDevTtySessionDirectory(path) != null) return true;
    if (parseSysTtySessionDirectory(path) != null) return true;
    return parseOutputDirectory(path) != null;
}

fn isFilePath(path: []const u8) bool {
    if (std.mem.eql(u8, path, proc_version_path)) return true;
    if (std.mem.eql(u8, path, proc_runtime_snapshot_path)) return true;
    if (parseRuntimeSessionPath(path) != null) return true;
    if (std.mem.eql(u8, path, dev_null_path)) return true;
    if (std.mem.eql(u8, path, dev_storage_state_path)) return true;
    if (std.mem.eql(u8, path, dev_storage_backends_path)) return true;
    if (std.mem.eql(u8, path, dev_storage_filesystems_path)) return true;
    if (std.mem.eql(u8, path, dev_storage_registry_path)) return true;
    if (std.mem.eql(u8, path, dev_tty_state_path)) return true;
    if (std.mem.eql(u8, path, dev_display_state_path)) return true;
    if (std.mem.eql(u8, path, dev_memory_state_path)) return true;
    if (std.mem.eql(u8, path, dev_memory_map_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_state_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_topology_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_lapic_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ioapic_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_pic_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_pit_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_smp_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_startup_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_work_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_tasks_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_multi_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_slots_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_ownership_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_redistribution_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_backfill_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_window_path)) return true;
    if (std.mem.eql(u8, path, dev_net_state_path)) return true;
    if (std.mem.eql(u8, path, dev_net_route_path)) return true;
    if (std.mem.eql(u8, path, sys_kernel_version_path)) return true;
    if (std.mem.eql(u8, path, sys_kernel_machine_path)) return true;
    if (std.mem.eql(u8, path, sys_acpi_state_path)) return true;
    if (std.mem.eql(u8, path, sys_acpi_pm_timer_path)) return true;
    if (std.mem.eql(u8, path, sys_memory_state_path)) return true;
    if (std.mem.eql(u8, path, sys_memory_map_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_state_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_topology_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_lapic_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ioapic_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_pic_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_pit_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_smp_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_startup_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_work_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_tasks_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_multi_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_slots_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_ownership_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_redistribution_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_backfill_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_window_path)) return true;
    if (std.mem.eql(u8, path, sys_storage_state_path)) return true;
    if (std.mem.eql(u8, path, sys_storage_backends_path)) return true;
    if (std.mem.eql(u8, path, sys_storage_filesystems_path)) return true;
    if (std.mem.eql(u8, path, sys_storage_registry_path)) return true;
    if (std.mem.eql(u8, path, sys_tty_state_path)) return true;
    if (std.mem.eql(u8, path, sys_display_state_path)) return true;
    if (std.mem.eql(u8, path, sys_net_state_path)) return true;
    if (std.mem.eql(u8, path, sys_net_route_path)) return true;
    if (parseDevOutputFilePath(path) != null) return true;
    if (parseTtySessionFilePath(path) != null) return true;
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
    if (std.mem.eql(u8, path, dev_null_path)) {
        return allocator.dupe(u8, "");
    }
    if (std.mem.eql(u8, path, dev_storage_state_path)) {
        return renderStorageStateAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_storage_backends_path)) {
        return storage_backend_registry.renderAlloc(allocator, max_stat_render_bytes);
    }
    if (std.mem.eql(u8, path, dev_storage_filesystems_path)) {
        return storage_backend_registry.renderFilesystemSupportAlloc(allocator, max_stat_render_bytes);
    }
    if (std.mem.eql(u8, path, dev_storage_registry_path)) {
        return storage_registry.renderAlloc(allocator, max_stat_render_bytes);
    }
    if (std.mem.eql(u8, path, dev_memory_state_path) or std.mem.eql(u8, path, sys_memory_state_path)) {
        return renderMemoryStateAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_memory_map_path) or std.mem.eql(u8, path, sys_memory_map_path)) {
        return boot_memory.renderMapAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_tty_state_path) or std.mem.eql(u8, path, sys_tty_state_path)) {
        return renderTtyStateAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_display_state_path)) {
        return renderDisplayStateAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_state_path) or std.mem.eql(u8, path, sys_cpu_state_path)) {
        return acpi.renderCpuStateAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_topology_path) or std.mem.eql(u8, path, sys_cpu_topology_path)) {
        return acpi.renderCpuTopologyAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_lapic_path) or std.mem.eql(u8, path, sys_cpu_lapic_path)) {
        return lapic.renderAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ioapic_path) or std.mem.eql(u8, path, sys_cpu_ioapic_path)) {
        return ioapic.renderAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_pic_path) or std.mem.eql(u8, path, sys_cpu_pic_path)) {
        return pic.renderAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_pit_path) or std.mem.eql(u8, path, sys_cpu_pit_path)) {
        return pit.renderAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_smp_path) or std.mem.eql(u8, path, sys_cpu_smp_path)) {
        return lapic.renderSmpAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_startup_path) or std.mem.eql(u8, path, sys_cpu_ap_startup_path)) {
        return i386_ap_startup.renderAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_work_path) or std.mem.eql(u8, path, sys_cpu_ap_work_path)) {
        return i386_ap_startup.renderWorkAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_tasks_path) or std.mem.eql(u8, path, sys_cpu_ap_tasks_path)) {
        return i386_ap_startup.renderTasksAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_multi_path) or std.mem.eql(u8, path, sys_cpu_ap_multi_path)) {
        return i386_ap_startup.renderMultiAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_slots_path) or std.mem.eql(u8, path, sys_cpu_ap_slots_path)) {
        return i386_ap_startup.renderSlotsAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_ownership_path) or
        std.mem.eql(u8, path, sys_cpu_ap_ownership_path) or
        std.mem.eql(u8, path, dev_cpu_ap_redistribution_path) or
        std.mem.eql(u8, path, sys_cpu_ap_redistribution_path))
    {
        return i386_ap_startup.renderOwnershipAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_failover_path) or std.mem.eql(u8, path, sys_cpu_ap_failover_path)) {
        return i386_ap_startup.renderFailoverAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_backfill_path) or std.mem.eql(u8, path, sys_cpu_ap_backfill_path)) {
        return i386_ap_startup.renderBackfillAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_window_path) or std.mem.eql(u8, path, sys_cpu_ap_window_path)) {
        return i386_ap_startup.renderWindowAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_net_state_path)) {
        return renderNetStateAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_net_route_path)) {
        return renderNetRouteAlloc(allocator);
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
    if (std.mem.eql(u8, path, sys_acpi_state_path)) {
        return acpi.renderAlloc(allocator);
    }
    if (std.mem.eql(u8, path, sys_acpi_pm_timer_path)) {
        return acpi_pm_timer.renderAlloc(allocator);
    }
    if (std.mem.eql(u8, path, sys_storage_state_path)) {
        return renderStorageStateAlloc(allocator);
    }
    if (std.mem.eql(u8, path, sys_storage_backends_path)) {
        return storage_backend_registry.renderAlloc(allocator, max_stat_render_bytes);
    }
    if (std.mem.eql(u8, path, sys_storage_filesystems_path)) {
        return storage_backend_registry.renderFilesystemSupportAlloc(allocator, max_stat_render_bytes);
    }
    if (std.mem.eql(u8, path, sys_storage_registry_path)) {
        return storage_registry.renderAlloc(allocator, max_stat_render_bytes);
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
    if (parseDevOutputFilePath(path)) |request| {
        return switch (request.kind) {
            .detail => renderDisplayOutputDetailAlloc(allocator, request.index),
            .modes => renderDisplayOutputModesAlloc(allocator, request.index),
        };
    }
    if (parseTtySessionFilePath(path)) |request| {
        return switch (request.kind) {
            .info => renderTtySessionFileAlloc(allocator, request.session_name, .info),
            .input => renderTtySessionFileAlloc(allocator, request.session_name, .input),
            .pending => renderTtySessionFileAlloc(allocator, request.session_name, .pending),
            .stdout => renderTtySessionFileAlloc(allocator, request.session_name, .stdout),
            .stderr => renderTtySessionFileAlloc(allocator, request.session_name, .stderr),
            .events => renderTtySessionFileAlloc(allocator, request.session_name, .events),
            .transcript => renderTtySessionFileAlloc(allocator, request.session_name, .transcript),
        };
    }
    return error.FileNotFound;
}

fn renderMemoryStateAlloc(allocator: std.mem.Allocator) Error![]u8 {
    const boot_render = try boot_memory.renderAlloc(allocator);
    defer allocator.free(boot_render);
    const physical_render = try physical_memory.renderAlloc(allocator);
    defer allocator.free(physical_render);
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ boot_render, physical_render });
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

fn appendTtySessionDirectory(allocator: std.mem.Allocator, out: *std.ArrayList(u8), max_bytes: usize) Error!void {
    const listing = tty_runtime.listSessionsAlloc(allocator, max_stat_render_bytes) catch |err| switch (err) {
        error.ResponseTooLarge => return error.ResponseTooLarge,
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.FileNotFound,
    };
    defer allocator.free(listing);

    var iterator = std.mem.splitScalar(u8, listing, '\n');
    while (iterator.next()) |session_name| {
        const trimmed = std.mem.trim(u8, session_name, " \t\r");
        if (trimmed.len == 0) continue;
        try appendDirectoryLine(allocator, out, trimmed, max_bytes);
    }
}

fn renderTtyStateAlloc(allocator: std.mem.Allocator) Error![]u8 {
    return tty_runtime.renderStateAlloc(allocator, max_stat_render_bytes) catch |err| switch (err) {
        error.ResponseTooLarge => error.ResponseTooLarge,
        error.OutOfMemory => error.OutOfMemory,
        else => error.FileNotFound,
    };
}

fn renderTtySessionFileAlloc(
    allocator: std.mem.Allocator,
    session_name: []const u8,
    kind: TtySessionFileKind,
) Error![]u8 {
    return switch (kind) {
        .info => tty_runtime.infoAlloc(allocator, session_name, max_stat_render_bytes) catch |err| switch (err) {
            error.ResponseTooLarge => error.ResponseTooLarge,
            error.OutOfMemory => error.OutOfMemory,
            else => error.FileNotFound,
        },
        .input => tty_runtime.inputAlloc(allocator, session_name, max_stat_render_bytes) catch |err| switch (err) {
            error.ResponseTooLarge => error.ResponseTooLarge,
            error.OutOfMemory => error.OutOfMemory,
            else => error.FileNotFound,
        },
        .pending => tty_runtime.pendingAlloc(allocator, session_name, max_stat_render_bytes) catch |err| switch (err) {
            error.ResponseTooLarge => error.ResponseTooLarge,
            error.OutOfMemory => error.OutOfMemory,
            else => error.FileNotFound,
        },
        .stdout => tty_runtime.stdoutAlloc(allocator, session_name, max_stat_render_bytes) catch |err| switch (err) {
            error.ResponseTooLarge => error.ResponseTooLarge,
            error.OutOfMemory => error.OutOfMemory,
            else => error.FileNotFound,
        },
        .stderr => tty_runtime.stderrAlloc(allocator, session_name, max_stat_render_bytes) catch |err| switch (err) {
            error.ResponseTooLarge => error.ResponseTooLarge,
            error.OutOfMemory => error.OutOfMemory,
            else => error.FileNotFound,
        },
        .events => tty_runtime.eventsAlloc(allocator, session_name, max_stat_render_bytes) catch |err| switch (err) {
            error.ResponseTooLarge => error.ResponseTooLarge,
            error.OutOfMemory => error.OutOfMemory,
            else => error.FileNotFound,
        },
        .transcript => tty_runtime.transcriptAlloc(allocator, session_name, max_stat_render_bytes) catch |err| switch (err) {
            error.ResponseTooLarge => error.ResponseTooLarge,
            error.OutOfMemory => error.OutOfMemory,
            else => error.FileNotFound,
        },
    };
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
    try appendFmt(
        allocator,
        &out,
        "detected_filesystem={s}\nsupported_filesystem_probes=zarfs,ext2,fat32\n",
        .{storage_registry.filesystemKindName(storage_registry.detectPersistentFilesystemKind())},
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

const TtySessionFileKind = enum {
    info,
    input,
    pending,
    stdout,
    stderr,
    events,
    transcript,
};

const TtySessionFileRequest = struct {
    session_name: []const u8,
    kind: TtySessionFileKind,
};

fn parseRuntimeSessionPath(path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, proc_runtime_sessions_path)) return null;
    if (path.len <= proc_runtime_sessions_path.len or path[proc_runtime_sessions_path.len] != '/') return null;
    const session_id = path[proc_runtime_sessions_path.len + 1 ..];
    if (session_id.len == 0) return null;
    if (std.mem.indexOfScalar(u8, session_id, '/')) |_| return null;
    return session_id;
}

fn parseDevTtySessionDirectory(path: []const u8) ?[]const u8 {
    return parseTtySessionDirectoryForBase(dev_tty_sessions_path, path);
}

fn parseSysTtySessionDirectory(path: []const u8) ?[]const u8 {
    return parseTtySessionDirectoryForBase(sys_tty_sessions_path, path);
}

fn parseTtySessionDirectoryForBase(base_path: []const u8, path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, base_path)) return null;
    if (path.len <= base_path.len or path[base_path.len] != '/') return null;
    const tail = path[base_path.len + 1 ..];
    if (tail.len == 0) return null;
    if (std.mem.indexOfScalar(u8, tail, '/')) |_| return null;
    return tail;
}

fn parseTtySessionFilePath(path: []const u8) ?TtySessionFileRequest {
    if (parseTtySessionFilePathForBase(dev_tty_sessions_path, path)) |request| return request;
    return parseTtySessionFilePathForBase(sys_tty_sessions_path, path);
}

fn parseTtySessionFilePathForBase(base_path: []const u8, path: []const u8) ?TtySessionFileRequest {
    if (!std.mem.startsWith(u8, path, base_path)) return null;
    if (path.len <= base_path.len or path[base_path.len] != '/') return null;
    const tail = path[base_path.len + 1 ..];
    const slash = std.mem.indexOfScalar(u8, tail, '/') orelse return null;
    const session_name = tail[0..slash];
    const file_name = tail[slash + 1 ..];
    if (session_name.len == 0 or file_name.len == 0) return null;
    if (std.mem.indexOfScalar(u8, file_name, '/')) |_| return null;
    if (std.mem.eql(u8, file_name, "info")) return .{ .session_name = session_name, .kind = .info };
    if (std.mem.eql(u8, file_name, "input")) return .{ .session_name = session_name, .kind = .input };
    if (std.mem.eql(u8, file_name, "pending")) return .{ .session_name = session_name, .kind = .pending };
    if (std.mem.eql(u8, file_name, "stdout")) return .{ .session_name = session_name, .kind = .stdout };
    if (std.mem.eql(u8, file_name, "stderr")) return .{ .session_name = session_name, .kind = .stderr };
    if (std.mem.eql(u8, file_name, "events")) return .{ .session_name = session_name, .kind = .events };
    if (std.mem.eql(u8, file_name, "transcript")) return .{ .session_name = session_name, .kind = .transcript };
    return null;
}

fn parseOutputDirectory(path: []const u8) ?u16 {
    return parseOutputDirectoryForBase(sys_display_outputs_path, path);
}

fn parseDevOutputDirectory(path: []const u8) ?u16 {
    return parseOutputDirectoryForBase(dev_display_outputs_path, path);
}

fn parseOutputDirectoryForBase(base_path: []const u8, path: []const u8) ?u16 {
    if (!std.mem.startsWith(u8, path, base_path)) return null;
    if (path.len <= base_path.len or path[base_path.len] != '/') return null;
    const tail = path[base_path.len + 1 ..];
    if (tail.len == 0) return null;
    if (std.mem.indexOfScalar(u8, tail, '/')) |_| return null;
    return std.fmt.parseUnsigned(u16, tail, 10) catch null;
}

fn parseOutputFilePath(path: []const u8) ?OutputFileRequest {
    return parseOutputFilePathForBase(sys_display_outputs_path, path);
}

fn parseDevOutputFilePath(path: []const u8) ?OutputFileRequest {
    return parseOutputFilePathForBase(dev_display_outputs_path, path);
}

fn parseOutputFilePathForBase(base_path: []const u8, path: []const u8) ?OutputFileRequest {
    if (!std.mem.startsWith(u8, path, base_path)) return null;
    if (path.len <= base_path.len or path[base_path.len] != '/') return null;
    const tail = path[base_path.len + 1 ..];
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
    return outputDetailPathForBase(allocator, sys_display_outputs_path, index);
}

fn outputModesPath(allocator: std.mem.Allocator, index: u16) ![]u8 {
    return outputModesPathForBase(allocator, sys_display_outputs_path, index);
}

fn outputDetailPathForBase(allocator: std.mem.Allocator, base_path: []const u8, index: u16) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{d}/detail", .{ base_path, index });
}

fn outputModesPathForBase(allocator: std.mem.Allocator, base_path: []const u8, index: u16) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{d}/modes", .{ base_path, index });
}

fn ttySessionFilePathForBase(
    allocator: std.mem.Allocator,
    base_path: []const u8,
    session_name: []const u8,
    file_name: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ base_path, session_name, file_name });
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
        abi.storage_backend_virtio_block => "virtio_block",
        else => "unknown",
    };
}

fn networkBackendName(backend: pal_net.Backend) []const u8 {
    return switch (backend) {
        .rtl8139 => "rtl8139",
        .e1000 => "e1000",
        .virtio_net => "virtio_net",
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
