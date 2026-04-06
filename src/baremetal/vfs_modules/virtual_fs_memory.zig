const boot_memory = @import("boot_memory.zig");
const physical_memory = @import("physical_memory.zig");
const i386_ap_startup = @import("i386_ap_startup.zig");
const ioapic = @import("ioapic.zig");
const lapic = @import("lapic.zig");
const pic = @import("pic.zig");
const pit = @import("pit.zig");
const display_output = @import("display_output.zig");
const runtime_bridge = @import("runtime_bridge.zig");
const sys_memory_path = "/sys/memory";
const sys_memory_state_path = "/sys/memory/state";
const sys_memory_map_path = "/sys/memory/map";
        try appendDirectoryLine(allocator, &out, "memory", max_bytes);
        try appendDirectoryLine(allocator, &out, "cpu", max_bytes);
        try appendDirectoryLine(allocator, &out, "net", max_bytes);
        try appendFileLine(allocator, &out, "null", dev_null_path, max_bytes);
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
        try appendFileLine(allocator, &out, "ap-fairness", dev_cpu_ap_fairness_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-rebalance", dev_cpu_ap_rebalance_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-debt", dev_cpu_ap_debt_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-admission", dev_cpu_ap_admission_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-aging", dev_cpu_ap_aging_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-fairshare", dev_cpu_ap_fairshare_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-quota", dev_cpu_ap_quota_path, max_bytes);
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
        try appendFileLine(allocator, &out, "ap-fairness", sys_cpu_ap_fairness_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-rebalance", sys_cpu_ap_rebalance_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-debt", sys_cpu_ap_debt_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-admission", sys_cpu_ap_admission_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-aging", sys_cpu_ap_aging_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-fairshare", sys_cpu_ap_fairshare_path, max_bytes);
        try appendFileLine(allocator, &out, "ap-quota", sys_cpu_ap_quota_path, max_bytes);
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, path, dev_memory_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_path)) return true;
    if (std.mem.eql(u8, path, dev_display_outputs_path)) return true;
    if (std.mem.eql(u8, path, dev_net_path)) return true;
    if (std.mem.eql(u8, path, "/sys")) return true;
    if (std.mem.eql(u8, path, "/sys/kernel")) return true;
    if (std.mem.eql(u8, path, sys_acpi_path)) return true;
    if (std.mem.eql(u8, path, sys_memory_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_path)) return true;
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
    if (std.mem.eql(u8, path, dev_cpu_ap_fairness_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_rebalance_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_debt_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_admission_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_aging_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_fairshare_path)) return true;
    if (std.mem.eql(u8, path, dev_cpu_ap_quota_path)) return true;
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
    if (std.mem.eql(u8, path, sys_cpu_ap_fairness_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_rebalance_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_debt_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_admission_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_aging_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_fairshare_path)) return true;
    if (std.mem.eql(u8, path, sys_cpu_ap_quota_path)) return true;
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
    if (std.mem.eql(u8, path, dev_cpu_ap_fairness_path) or std.mem.eql(u8, path, sys_cpu_ap_fairness_path)) {
        return i386_ap_startup.renderFairnessAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_rebalance_path) or std.mem.eql(u8, path, sys_cpu_ap_rebalance_path)) {
        return i386_ap_startup.renderRebalanceAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_debt_path) or std.mem.eql(u8, path, sys_cpu_ap_debt_path)) {
        return i386_ap_startup.renderDebtAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_admission_path) or std.mem.eql(u8, path, sys_cpu_ap_admission_path)) {
        return i386_ap_startup.renderAdmissionAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_aging_path) or std.mem.eql(u8, path, sys_cpu_ap_aging_path)) {
        return i386_ap_startup.renderAgingAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_fairshare_path) or std.mem.eql(u8, path, sys_cpu_ap_fairshare_path)) {
        return i386_ap_startup.renderFairshareAlloc(allocator);
    }
    if (std.mem.eql(u8, path, dev_cpu_ap_quota_path) or std.mem.eql(u8, path, sys_cpu_ap_quota_path)) {
        return i386_ap_startup.renderQuotaAlloc(allocator);
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

