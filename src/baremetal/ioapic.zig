// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const acpi = @import("acpi.zig");

pub const Error = error{
    UnsupportedPlatform,
    IoApicMissing,
    MmioUnavailable,
};

var state: abi.BaremetalIoApicState = zeroState();
var test_register_values: ?[]const u32 = null;

fn zeroState() abi.BaremetalIoApicState {
    return .{
        .magic = abi.ioapic_magic,
        .api_version = abi.api_version,
        .present = 0,
        .acpi_present = 0,
        .enabled = 0,
        .reserved0 = .{ 0, 0, 0 },
        .ioapic_count = 0,
        .selected_index = 0,
        .redirection_entry_count = 0,
        .reserved1 = 0,
        .ioapic_id = 0,
        .version = 0,
        .arbitration_id = 0,
        .gsi_base = 0,
        .reserved2 = .{ 0, 0, 0, 0 },
        .mmio_addr = 0,
    };
}

pub fn resetForTest() void {
    state = zeroState();
    test_register_values = null;
}

pub fn init() void {
    state = zeroState();
    probe() catch {};
}

pub fn statePtr() *const abi.BaremetalIoApicState {
    return &state;
}

pub fn probe() Error!void {
    state = zeroState();
    if (!runtimeCanProbe()) return error.UnsupportedPlatform;

    const acpi_state = acpi.statePtr().*;
    state.acpi_present = acpi_state.present;
    state.ioapic_count = acpi_state.ioapic_count;
    if (acpi_state.present == 0 or acpi_state.ioapic_count == 0) return error.IoApicMissing;

    const entry = acpi.ioApicEntry(0) orelse return error.IoApicMissing;
    if (entry.mmio_addr == 0) return error.MmioUnavailable;

    state.present = 1;
    state.selected_index = 0;
    state.gsi_base = entry.gsi_base;
    state.mmio_addr = entry.mmio_addr;

    const id_reg = readReg(entry.mmio_addr, 0x00);
    const version_reg = readReg(entry.mmio_addr, 0x01);
    const arbitration_reg = readReg(entry.mmio_addr, 0x02);

    state.ioapic_id = (id_reg >> 24) & 0x0F;
    state.version = version_reg;
    state.arbitration_id = (arbitration_reg >> 24) & 0x0F;
    state.redirection_entry_count = @as(u16, @intCast(((version_reg >> 16) & 0xFF) + 1));
    state.enabled = if (state.redirection_entry_count != 0) 1 else 0;
}

pub fn renderAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "present={d}\nacpi_present={d}\nenabled={d}\nioapic_count={d}\nselected_index={d}\nredirection_entry_count={d}\nioapic_id={d}\nversion=0x{x}\narbitration_id={d}\ngsi_base={d}\nmmio_addr=0x{x}\n",
        .{
            state.present,
            state.acpi_present,
            state.enabled,
            state.ioapic_count,
            state.selected_index,
            state.redirection_entry_count,
            state.ioapic_id,
            state.version,
            state.arbitration_id,
            state.gsi_base,
            state.mmio_addr,
        },
    );
}

fn runtimeCanProbe() bool {
    if (builtin.is_test and test_register_values != null) return true;
    return builtin.os.tag == .freestanding and (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64);
}

fn readReg(mmio_addr: u64, register_index: u8) u32 {
    if (builtin.is_test) {
        if (test_register_values) |values| {
            if (register_index < values.len) return values[register_index];
            return 0;
        }
    }
    const select = @as(*volatile u32, @ptrFromInt(@as(usize, @intCast(mmio_addr))));
    const window = @as(*volatile u32, @ptrFromInt(@as(usize, @intCast(mmio_addr + 0x10))));
    select.* = register_index;
    return window.*;
}

test "ioapic probe exports bounded state with synthetic acpi and register overrides" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    const registers = [_]u32{
        0x01000000,
        0x00170011,
        0x02000000,
    };
    test_register_values = registers[0..];

    try probe();

    const snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u32, abi.ioapic_magic), snapshot.magic);
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, 1), snapshot.acpi_present);
    try std.testing.expectEqual(@as(u8, 1), snapshot.enabled);
    try std.testing.expectEqual(@as(u16, 1), snapshot.ioapic_count);
    try std.testing.expectEqual(@as(u16, 24), snapshot.redirection_entry_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.ioapic_id);
    try std.testing.expectEqual(@as(u32, 0x00170011), snapshot.version);
    try std.testing.expectEqual(@as(u32, 2), snapshot.arbitration_id);
    try std.testing.expectEqual(@as(u32, 0), snapshot.gsi_base);
    try std.testing.expectEqual(@as(u64, 0xFEC00000), snapshot.mmio_addr);

    const render = try renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "redirection_entry_count=24") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "mmio_addr=0xfec00000") != null);
}
