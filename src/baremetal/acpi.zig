// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");

const rsdp_signature = "RSD PTR ";
const rsdt_signature = "RSDT";
const xsdt_signature = "XSDT";
const fadt_signature = "FACP";
const madt_signature = "APIC";
const low_memory_scan_limit: usize = 0x100000;
const rsdp_v1_length: usize = 20;
const rsdp_v2_length: usize = 36;
const sdt_header_length: usize = 36;
const madt_header_length: usize = 44;
const madt_entry_local_apic: u8 = 0;
const madt_entry_io_apic: u8 = 1;
const madt_entry_local_apic_addr_override: u8 = 5;
const acpi_flag_has_xsdt: u32 = 1 << 0;
const acpi_flag_has_fadt: u32 = 1 << 1;
const acpi_flag_has_madt: u32 = 1 << 2;
const cpu_topology_capacity: usize = 16;

pub const Error = error{
    UnsupportedPlatform,
    MemoryWindowUnavailable,
    RsdpNotFound,
    RsdpChecksumMismatch,
    RsdpLengthInvalid,
    SdtHeaderUnavailable,
    TableLengthInvalid,
    TableChecksumMismatch,
    RootTableMissing,
};

var state: abi.BaremetalAcpiState = zeroState();
var cpu_topology_state: abi.BaremetalCpuTopologyState = zeroCpuTopologyState();
var cpu_topology_entries: [cpu_topology_capacity]abi.BaremetalCpuTopologyEntry = std.mem.zeroes([cpu_topology_capacity]abi.BaremetalCpuTopologyEntry);
var synthetic_image: [low_memory_scan_limit]u8 = undefined;

fn zeroState() abi.BaremetalAcpiState {
    return .{
        .magic = abi.acpi_magic,
        .api_version = abi.api_version,
        .present = 0,
        .revision = 0,
        .oem_id = .{ 0, 0, 0, 0, 0, 0 },
        .table_count = 0,
        .lapic_count = 0,
        .ioapic_count = 0,
        .sci_interrupt = 0,
        .pm_timer_block = 0,
        .flags = 0,
        .rsdp_addr = 0,
        .rsdt_addr = 0,
        .xsdt_addr = 0,
        .fadt_addr = 0,
        .madt_addr = 0,
    };
}

fn zeroCpuTopologyState() abi.BaremetalCpuTopologyState {
    return .{
        .magic = abi.cpu_magic,
        .api_version = abi.api_version,
        .present = 0,
        .supports_smp = 0,
        .cpu_count = 0,
        .exported_count = 0,
        .enabled_count = 0,
        .ioapic_count = 0,
        .lapic_addr_override_count = 0,
        .reserved0 = 0,
        .madt_flags = 0,
        .local_apic_addr = 0,
        .madt_addr = 0,
    };
}

pub fn resetForTest() void {
    state = zeroState();
    cpu_topology_state = zeroCpuTopologyState();
    @memset(&cpu_topology_entries, std.mem.zeroes(abi.BaremetalCpuTopologyEntry));
}

pub fn statePtr() *const abi.BaremetalAcpiState {
    return &state;
}

pub fn cpuTopologyStatePtr() *const abi.BaremetalCpuTopologyState {
    return &cpu_topology_state;
}

pub fn cpuTopologyEntryCount() u16 {
    return cpu_topology_state.exported_count;
}

pub fn cpuTopologyEntry(index: u16) abi.BaremetalCpuTopologyEntry {
    if (index >= cpu_topology_state.exported_count) return std.mem.zeroes(abi.BaremetalCpuTopologyEntry);
    return cpu_topology_entries[index];
}

pub fn init() void {
    state = zeroState();
    if (builtin.os.tag != .freestanding) return;
    if (builtin.cpu.arch != .x86 and builtin.cpu.arch != .x86_64) return;
    probeLive() catch {};
}

pub fn probeLive() Error!void {
    if (builtin.os.tag != .freestanding) return error.UnsupportedPlatform;
    if (builtin.cpu.arch != .x86 and builtin.cpu.arch != .x86_64) return error.UnsupportedPlatform;
    const low_mem = @as([*]allowzero const u8, @ptrFromInt(0))[0..low_memory_scan_limit];
    try probeImage(low_mem, 0);
}

pub fn probeSyntheticImage(use_xsdt: bool) Error!void {
    buildSyntheticAcpiImage(&synthetic_image, use_xsdt);
    try probeImage(&synthetic_image, 0);
}

pub fn probeImage(image: []const u8, base_phys: u64) Error!void {
    state = zeroState();
    cpu_topology_state = zeroCpuTopologyState();
    @memset(&cpu_topology_entries, std.mem.zeroes(abi.BaremetalCpuTopologyEntry));

    const rsdp_phys = findRsdp(image, base_phys) orelse return error.RsdpNotFound;
    const rsdp_v1 = sliceAt(image, base_phys, rsdp_phys, rsdp_v1_length) orelse return error.RsdpChecksumMismatch;
    if (!checksumValid(rsdp_v1)) return error.RsdpChecksumMismatch;

    const revision = rsdp_v1[15];
    var rsdp_length: usize = rsdp_v1_length;
    var xsdt_addr: u64 = 0;
    if (revision >= 2) {
        const rsdp_v2 = sliceAt(image, base_phys, rsdp_phys, rsdp_v2_length) orelse return error.RsdpLengthInvalid;
        rsdp_length = @as(usize, readU32(rsdp_v2, 20));
        if (rsdp_length < rsdp_v2_length) return error.RsdpLengthInvalid;
        const rsdp_full = sliceAt(image, base_phys, rsdp_phys, rsdp_length) orelse return error.RsdpLengthInvalid;
        if (!checksumValid(rsdp_full)) return error.RsdpChecksumMismatch;
        xsdt_addr = readU64(rsdp_v2, 24);
    }

    const rsdp_full = sliceAt(image, base_phys, rsdp_phys, rsdp_length) orelse return error.RsdpLengthInvalid;
    const rsdt_addr = @as(u64, readU32(rsdp_v1, 16));
    var table_count: u16 = 0;
    var active_root_addr: u64 = 0;
    var use_xsdt = false;

    if (xsdt_addr != 0) {
        if (validateTable(image, base_phys, xsdt_addr, xsdt_signature)) |xsdt| {
            table_count = countRootEntries(xsdt, true);
            active_root_addr = xsdt_addr;
            use_xsdt = true;
            state.flags |= acpi_flag_has_xsdt;
        }
    }
    if (active_root_addr == 0 and rsdt_addr != 0) {
        if (validateTable(image, base_phys, rsdt_addr, rsdt_signature)) |rsdt| {
            table_count = countRootEntries(rsdt, false);
            active_root_addr = rsdt_addr;
        }
    }
    if (active_root_addr == 0) {
        return error.RootTableMissing;
    }

    const fadt_addr = findTable(image, base_phys, active_root_addr, use_xsdt, fadt_signature);
    const madt_addr = findTable(image, base_phys, active_root_addr, use_xsdt, madt_signature);

    var sci_interrupt: u16 = 0;
    var pm_timer_block: u32 = 0;
    if (fadt_addr != 0) {
        if (validateTable(image, base_phys, fadt_addr, fadt_signature)) |fadt| {
            if (fadt.len >= 48) sci_interrupt = readU16(fadt, 46);
            if (fadt.len >= 80) pm_timer_block = readU32(fadt, 76);
            state.flags |= acpi_flag_has_fadt;
        }
    }

    var lapic_count: u16 = 0;
    var ioapic_count: u16 = 0;
    var enabled_cpu_count: u16 = 0;
    var lapic_addr_override_count: u16 = 0;
    var madt_flags: u32 = 0;
    var local_apic_addr: u64 = 0;
    if (madt_addr != 0) {
        if (validateTable(image, base_phys, madt_addr, madt_signature)) |madt| {
            if (madt.len >= madt_header_length) {
                local_apic_addr = @as(u64, readU32(madt, 36));
                madt_flags = readU32(madt, 40);
            }
            parseMadt(madt, &lapic_count, &ioapic_count, &enabled_cpu_count, &lapic_addr_override_count, &local_apic_addr);
            state.flags |= acpi_flag_has_madt;
        }
    }

    state.present = 1;
    state.revision = revision;
    @memcpy(state.oem_id[0..6], rsdp_full[9..15]);
    state.table_count = table_count;
    state.lapic_count = lapic_count;
    state.ioapic_count = ioapic_count;
    state.sci_interrupt = sci_interrupt;
    state.pm_timer_block = pm_timer_block;
    state.rsdp_addr = rsdp_phys;
    state.rsdt_addr = rsdt_addr;
    state.xsdt_addr = xsdt_addr;
    state.fadt_addr = fadt_addr;
    state.madt_addr = madt_addr;

    cpu_topology_state.present = if (madt_addr != 0 and lapic_count > 0) 1 else 0;
    cpu_topology_state.supports_smp = if (enabled_cpu_count > 1) 1 else 0;
    cpu_topology_state.cpu_count = lapic_count;
    cpu_topology_state.exported_count = @as(u16, @intCast(@min(@as(usize, lapic_count), cpu_topology_capacity)));
    cpu_topology_state.enabled_count = enabled_cpu_count;
    cpu_topology_state.ioapic_count = ioapic_count;
    cpu_topology_state.lapic_addr_override_count = lapic_addr_override_count;
    cpu_topology_state.madt_flags = madt_flags;
    cpu_topology_state.local_apic_addr = local_apic_addr;
    cpu_topology_state.madt_addr = madt_addr;
}

pub fn renderAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "present={d}\nrevision={d}\nflags=0x{x}\nrsdp=0x{x}\nrsdt=0x{x}\nxsdt=0x{x}\nfadt=0x{x}\nmadt=0x{x}\noem={s}\ntable_count={d}\nlapic_count={d}\nioapic_count={d}\nsci_interrupt={d}\npm_timer_block=0x{x}\n",
        .{
            state.present,
            state.revision,
            state.flags,
            state.rsdp_addr,
            state.rsdt_addr,
            state.xsdt_addr,
            state.fadt_addr,
            state.madt_addr,
            state.oem_id[0..],
            state.table_count,
            state.lapic_count,
            state.ioapic_count,
            state.sci_interrupt,
            state.pm_timer_block,
        },
    );
}

pub fn renderCpuStateAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "present={d}\nsupports_smp={d}\ncpu_count={d}\nexported_count={d}\nenabled_count={d}\nioapic_count={d}\nlapic_addr_override_count={d}\nmadt_flags=0x{x}\nlocal_apic_addr=0x{x}\nmadt=0x{x}\n",
        .{
            cpu_topology_state.present,
            cpu_topology_state.supports_smp,
            cpu_topology_state.cpu_count,
            cpu_topology_state.exported_count,
            cpu_topology_state.enabled_count,
            cpu_topology_state.ioapic_count,
            cpu_topology_state.lapic_addr_override_count,
            cpu_topology_state.madt_flags,
            cpu_topology_state.local_apic_addr,
            cpu_topology_state.madt_addr,
        },
    );
}

pub fn renderCpuTopologyAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var index: u16 = 0;
    while (index < cpu_topology_state.exported_count) : (index += 1) {
        const entry = cpu_topology_entries[index];
        const line = try std.fmt.allocPrint(
            allocator,
            "cpu[{d}].uid={d}\ncpu[{d}].apic_id={d}\ncpu[{d}].enabled={d}\ncpu[{d}].flags=0x{x}\n",
            .{ index, entry.processor_uid, index, entry.apic_id, index, entry.enabled, index, entry.flags },
        );
        defer allocator.free(line);
        try out.appendSlice(allocator, line);
    }
    return out.toOwnedSlice(allocator);
}

fn checksumValid(bytes: []const u8) bool {
    var sum: u8 = 0;
    for (bytes) |byte| sum +%= byte;
    return sum == 0;
}

fn sliceAt(image: []const u8, base_phys: u64, phys: u64, len: usize) ?[]const u8 {
    if (phys < base_phys) return null;
    const rel = phys - base_phys;
    const start = std.math.cast(usize, rel) orelse return null;
    if (start > image.len or len > image.len - start) return null;
    return image[start .. start + len];
}

fn readU16(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .little);
}

fn readU32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}

fn readU64(bytes: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, bytes[offset..][0..8], .little);
}

fn findRsdp(image: []const u8, base_phys: u64) ?u64 {
    if (base_phys == 0 and image.len >= 0x1000) {
        const ebda_segment = readU16(image, 0x40E);
        if (ebda_segment != 0) {
            const ebda_phys = @as(u64, ebda_segment) << 4;
            if (scanForRsdp(image, base_phys, ebda_phys, 1024)) |addr| return addr;
        }
    }
    return scanForRsdp(image, base_phys, 0xE0000, 0x20000);
}

fn scanForRsdp(image: []const u8, base_phys: u64, start_phys: u64, length: usize) ?u64 {
    const region = sliceAt(image, base_phys, start_phys, length) orelse return null;
    var offset: usize = 0;
    while (offset + rsdp_signature.len <= region.len) : (offset += 16) {
        if (std.mem.eql(u8, region[offset .. offset + rsdp_signature.len], rsdp_signature)) {
            return start_phys + offset;
        }
    }
    return null;
}

fn validateTable(image: []const u8, base_phys: u64, phys: u64, expected_sig: []const u8) ?[]const u8 {
    const header = sliceAt(image, base_phys, phys, sdt_header_length) orelse return null;
    if (!std.mem.eql(u8, header[0..4], expected_sig)) return null;
    const length = @as(usize, readU32(header, 4));
    if (length < sdt_header_length) return null;
    const table = sliceAt(image, base_phys, phys, length) orelse return null;
    if (!checksumValid(table)) return null;
    return table;
}

fn countRootEntries(table: []const u8, is_xsdt: bool) u16 {
    const entry_size: usize = if (is_xsdt) 8 else 4;
    if (table.len < sdt_header_length) return 0;
    const entry_bytes = table.len - sdt_header_length;
    return @as(u16, @intCast(entry_bytes / entry_size));
}

fn findTable(image: []const u8, base_phys: u64, root_phys: u64, is_xsdt: bool, signature: []const u8) u64 {
    const expected_root_sig = if (is_xsdt) xsdt_signature else rsdt_signature;
    const root = validateTable(image, base_phys, root_phys, expected_root_sig) orelse return 0;
    const entry_size: usize = if (is_xsdt) 8 else 4;
    var offset: usize = sdt_header_length;
    while (offset + entry_size <= root.len) : (offset += entry_size) {
        const table_phys = if (is_xsdt) readU64(root, offset) else @as(u64, readU32(root, offset));
        if (table_phys == 0) continue;
        const header = sliceAt(image, base_phys, table_phys, sdt_header_length) orelse continue;
        if (!std.mem.eql(u8, header[0..4], signature)) continue;
        const length = @as(usize, readU32(header, 4));
        if (length < sdt_header_length) continue;
        const table = sliceAt(image, base_phys, table_phys, length) orelse continue;
        if (!checksumValid(table)) continue;
        return table_phys;
    }
    return 0;
}

fn parseMadt(
    madt: []const u8,
    lapic_count: *u16,
    ioapic_count: *u16,
    enabled_cpu_count: *u16,
    lapic_addr_override_count: *u16,
    local_apic_addr: *u64,
) void {
    lapic_count.* = 0;
    ioapic_count.* = 0;
    enabled_cpu_count.* = 0;
    lapic_addr_override_count.* = 0;
    if (madt.len < madt_header_length) return;
    var offset: usize = madt_header_length;
    while (offset + 2 <= madt.len) {
        const entry_type = madt[offset];
        const entry_len = madt[offset + 1];
        if (entry_len < 2 or offset + entry_len > madt.len) break;
        switch (entry_type) {
            madt_entry_local_apic => {
                lapic_count.* +%= 1;
                const flags = if (entry_len >= 8) readU32(madt, offset + 4) else 0;
                const enabled: u8 = if ((flags & 1) != 0) 1 else 0;
                if (enabled != 0) enabled_cpu_count.* +%= 1;
                const export_index = @as(usize, lapic_count.*) - 1;
                if (export_index < cpu_topology_capacity and entry_len >= 8) {
                    cpu_topology_entries[export_index] = .{
                        .processor_uid = madt[offset + 2],
                        .apic_id = madt[offset + 3],
                        .enabled = enabled,
                        .reserved0 = 0,
                        .flags = flags,
                    };
                }
            },
            madt_entry_io_apic => ioapic_count.* +%= 1,
            madt_entry_local_apic_addr_override => {
                if (entry_len >= 12) {
                    local_apic_addr.* = readU64(madt, offset + 4);
                    lapic_addr_override_count.* +%= 1;
                }
            },
            else => {},
        }
        offset += entry_len;
    }
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .little);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
}

fn writeU64(bytes: []u8, offset: usize, value: u64) void {
    std.mem.writeInt(u64, bytes[offset..][0..8], value, .little);
}

fn finalizeChecksum(bytes: []u8, checksum_offset: usize) void {
    bytes[checksum_offset] = 0;
    var sum: u8 = 0;
    for (bytes) |byte| sum +%= byte;
    bytes[checksum_offset] = @as(u8, 0 -% sum);
}

fn buildSyntheticAcpiImage(image: []u8, use_xsdt: bool) void {
    @memset(image, 0);

    const rsdp_addr: usize = 0x9FC00;
    const rsdt_addr: usize = 0xF0100;
    const xsdt_addr: usize = 0xF0180;
    const fadt_addr: usize = 0xF0200;
    const madt_addr: usize = 0xF0300;

    writeU16(image, 0x40E, @as(u16, @intCast(rsdp_addr >> 4)));

    var fadt = image[fadt_addr .. fadt_addr + 80];
    @memcpy(fadt[0..4], fadt_signature);
    writeU32(fadt, 4, @as(u32, @intCast(fadt.len)));
    fadt[8] = 3;
    @memcpy(fadt[10..16], "ZAROS ");
    writeU16(fadt, 46, 9);
    writeU32(fadt, 76, 0x608);
    finalizeChecksum(fadt, 9);

    var madt = image[madt_addr .. madt_addr + 72];
    @memcpy(madt[0..4], madt_signature);
    writeU32(madt, 4, @as(u32, @intCast(madt.len)));
    madt[8] = 1;
    @memcpy(madt[10..16], "ZAROS ");
    writeU32(madt, 36, 0xFEE00000);
    writeU32(madt, 40, 1);
    madt[44] = 0;
    madt[45] = 8;
    madt[46] = 0;
    madt[47] = 0;
    writeU32(madt, 48, 1);
    madt[52] = 0;
    madt[53] = 8;
    madt[54] = 1;
    madt[55] = 1;
    writeU32(madt, 56, 1);
    madt[60] = 1;
    madt[61] = 12;
    madt[62] = 1;
    madt[63] = 0;
    writeU32(madt, 64, 0xFEC00000);
    finalizeChecksum(madt, 9);

    if (use_xsdt) {
        var xsdt = image[xsdt_addr .. xsdt_addr + 52];
        @memcpy(xsdt[0..4], xsdt_signature);
        writeU32(xsdt, 4, @as(u32, @intCast(xsdt.len)));
        xsdt[8] = 1;
        @memcpy(xsdt[10..16], "ZAROS ");
        writeU64(xsdt, 36, fadt_addr);
        writeU64(xsdt, 44, madt_addr);
        finalizeChecksum(xsdt, 9);
    }

    var rsdt = image[rsdt_addr .. rsdt_addr + 44];
    @memcpy(rsdt[0..4], rsdt_signature);
    writeU32(rsdt, 4, @as(u32, @intCast(rsdt.len)));
    rsdt[8] = 1;
    @memcpy(rsdt[10..16], "ZAROS ");
    writeU32(rsdt, 36, fadt_addr);
    writeU32(rsdt, 40, madt_addr);
    finalizeChecksum(rsdt, 9);

    const rsdp_len: usize = if (use_xsdt) rsdp_v2_length else rsdp_v1_length;
    var rsdp = image[rsdp_addr .. rsdp_addr + rsdp_len];
    @memcpy(rsdp[0..8], rsdp_signature);
    @memcpy(rsdp[9..15], "ZAROS ");
    rsdp[15] = if (use_xsdt) 2 else 1;
    writeU32(rsdp, 16, rsdt_addr);
    if (use_xsdt) {
        writeU32(rsdp, 20, @as(u32, @intCast(rsdp.len)));
        writeU64(rsdp, 24, xsdt_addr);
        finalizeChecksum(rsdp[0..20], 8);
        finalizeChecksum(rsdp, 32);
    } else {
        finalizeChecksum(rsdp, 8);
    }
}

test "acpi probe image discovers rsdt fadt and madt" {
    var image = [_]u8{0} ** low_memory_scan_limit;
    buildSyntheticAcpiImage(&image, false);

    resetForTest();
    try probeImage(&image, 0);

    const snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, 1), snapshot.revision);
    try std.testing.expectEqual(@as(u16, 2), snapshot.table_count);
    try std.testing.expectEqual(@as(u16, 2), snapshot.lapic_count);
    try std.testing.expectEqual(@as(u16, 1), snapshot.ioapic_count);
    try std.testing.expectEqual(@as(u16, 9), snapshot.sci_interrupt);
    try std.testing.expectEqual(@as(u32, 0x608), snapshot.pm_timer_block);
    try std.testing.expectEqual(@as(u64, 0xF0100), snapshot.rsdt_addr);
    try std.testing.expectEqual(@as(u64, 0), snapshot.xsdt_addr);
    try std.testing.expectEqual(@as(u32, acpi_flag_has_fadt | acpi_flag_has_madt), snapshot.flags);
}

test "acpi probe image prefers xsdt when revision two tables are present" {
    var image = [_]u8{0} ** low_memory_scan_limit;
    buildSyntheticAcpiImage(&image, true);

    resetForTest();
    try probeImage(&image, 0);

    const snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, 2), snapshot.revision);
    try std.testing.expectEqual(@as(u16, 2), snapshot.table_count);
    try std.testing.expectEqual(@as(u64, 0xF0180), snapshot.xsdt_addr);
    try std.testing.expectEqual(@as(u32, acpi_flag_has_xsdt | acpi_flag_has_fadt | acpi_flag_has_madt), snapshot.flags);
}

test "acpi probe image exports cpu topology from madt" {
    var image = [_]u8{0} ** low_memory_scan_limit;
    buildSyntheticAcpiImage(&image, true);

    resetForTest();
    try probeImage(&image, 0);

    const topology = cpuTopologyStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), topology.present);
    try std.testing.expectEqual(@as(u8, 1), topology.supports_smp);
    try std.testing.expectEqual(@as(u16, 2), topology.cpu_count);
    try std.testing.expectEqual(@as(u16, 2), topology.exported_count);
    try std.testing.expectEqual(@as(u16, 2), topology.enabled_count);
    try std.testing.expectEqual(@as(u16, 1), topology.ioapic_count);
    try std.testing.expectEqual(@as(u16, 0), topology.lapic_addr_override_count);
    try std.testing.expectEqual(@as(u32, 1), topology.madt_flags);
    try std.testing.expectEqual(@as(u64, 0xFEE00000), topology.local_apic_addr);

    const cpu0 = cpuTopologyEntry(0);
    try std.testing.expectEqual(@as(u8, 0), cpu0.processor_uid);
    try std.testing.expectEqual(@as(u8, 0), cpu0.apic_id);
    try std.testing.expectEqual(@as(u8, 1), cpu0.enabled);

    const cpu1 = cpuTopologyEntry(1);
    try std.testing.expectEqual(@as(u8, 1), cpu1.processor_uid);
    try std.testing.expectEqual(@as(u8, 1), cpu1.apic_id);
    try std.testing.expectEqual(@as(u8, 1), cpu1.enabled);
}
