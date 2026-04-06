// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const x86_bootstrap = @import("x86_bootstrap.zig");

const master_command_port: u16 = 0x20;
const master_data_port: u16 = 0x21;
const slave_command_port: u16 = 0xA0;
const slave_data_port: u16 = 0xA1;

const master_offset: u8 = 0x20;
const slave_offset: u8 = 0x28;

const icw1_init: u8 = 0x10;
const icw1_expect_icw4: u8 = 0x01;
const icw4_8086: u8 = 0x01;
const ocw3_read_irr: u8 = 0x0A;
const ocw3_read_isr: u8 = 0x0B;

pub const Error = error{
    UnsupportedPlatform,
};

const ReadSelect = enum {
    none,
    irr,
    isr,
};

var state: abi.BaremetalPicState = zeroState();

var test_enabled = false;
var test_master_mask: u8 = 0;
var test_slave_mask: u8 = 0;
var test_master_irr: u8 = 0;
var test_slave_irr: u8 = 0;
var test_master_isr: u8 = 0;
var test_slave_isr: u8 = 0;
var test_master_select: ReadSelect = .none;
var test_slave_select: ReadSelect = .none;
var test_writes: [32]PortWrite = undefined;
var test_write_count: usize = 0;

const PortWrite = struct {
    port: u16,
    value: u8,
};

fn zeroState() abi.BaremetalPicState {
    return .{
        .magic = abi.pic_magic,
        .api_version = abi.api_version,
        .present = 0,
        .remapped = 0,
        .slave_present = 0,
        .auto_eoi = 0,
        .master_offset = 0,
        .slave_offset = 0,
        .master_mask = 0,
        .slave_mask = 0,
        .master_irr = 0,
        .slave_irr = 0,
        .master_isr = 0,
        .slave_isr = 0,
        .control_mask_profile = abi.interrupt_mask_profile_none,
        .last_masked_vector = 0,
        .reserved0 = .{ 0, 0 },
        .hardware_masked_irq_count = 0,
        .reserved1 = 0,
        .control_masked_count = 0,
        .control_ignored_count = 0,
    };
}

pub fn resetForTest() void {
    state = zeroState();
    test_enabled = false;
    test_master_mask = 0;
    test_slave_mask = 0;
    test_master_irr = 0;
    test_slave_irr = 0;
    test_master_isr = 0;
    test_slave_isr = 0;
    test_master_select = .none;
    test_slave_select = .none;
    test_write_count = 0;
}

pub fn statePtr() *const abi.BaremetalPicState {
    return &state;
}

pub fn init() void {
    state = zeroState();
    probe() catch {};
}

pub fn probe() Error!void {
    state = zeroState();
    if (!runtimeCanProbe()) return error.UnsupportedPlatform;

    const preserved_master_mask = readPort(master_data_port);
    const preserved_slave_mask = readPort(slave_data_port);
    remap(preserved_master_mask, preserved_slave_mask);

    state.present = 1;
    state.remapped = 1;
    state.slave_present = 1;
    state.auto_eoi = 0;
    state.master_offset = master_offset;
    state.slave_offset = slave_offset;
    state.master_mask = readPort(master_data_port);
    state.slave_mask = readPort(slave_data_port);
    state.master_irr = readRegister(master_command_port, ocw3_read_irr);
    state.slave_irr = readRegister(slave_command_port, ocw3_read_irr);
    state.master_isr = readRegister(master_command_port, ocw3_read_isr);
    state.slave_isr = readRegister(slave_command_port, ocw3_read_isr);
    state.hardware_masked_irq_count = @as(u16, @popCount(state.master_mask) + @popCount(state.slave_mask));
    state.control_mask_profile = x86_bootstrap.oc_interrupt_mask_profile();
    state.last_masked_vector = x86_bootstrap.oc_interrupt_last_masked_vector();
    state.control_masked_count = x86_bootstrap.oc_interrupt_masked_count();
    state.control_ignored_count = x86_bootstrap.oc_interrupt_mask_ignored_count();
}

pub fn renderAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "present={d}\nremapped={d}\nslave_present={d}\nauto_eoi={d}\nmaster_offset=0x{x}\nslave_offset=0x{x}\nmaster_mask=0x{x}\nslave_mask=0x{x}\nmaster_irr=0x{x}\nslave_irr=0x{x}\nmaster_isr=0x{x}\nslave_isr=0x{x}\nhardware_masked_irq_count={d}\ncontrol_mask_profile={d}\ncontrol_masked_count={d}\ncontrol_ignored_count={d}\nlast_masked_vector={d}\n",
        .{
            state.present,
            state.remapped,
            state.slave_present,
            state.auto_eoi,
            state.master_offset,
            state.slave_offset,
            state.master_mask,
            state.slave_mask,
            state.master_irr,
            state.slave_irr,
            state.master_isr,
            state.slave_isr,
            state.hardware_masked_irq_count,
            state.control_mask_profile,
            state.control_masked_count,
            state.control_ignored_count,
            state.last_masked_vector,
        },
    );
}

fn runtimeCanProbe() bool {
    if (builtin.is_test and test_enabled) return true;
    return hardwareBacked();
}

fn hardwareBacked() bool {
    return builtin.os.tag == .freestanding and (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64);
}

fn remap(preserved_master_mask: u8, preserved_slave_mask: u8) void {
    writePort(master_command_port, icw1_init | icw1_expect_icw4);
    ioWait();
    writePort(slave_command_port, icw1_init | icw1_expect_icw4);
    ioWait();

    writePort(master_data_port, master_offset);
    ioWait();
    writePort(slave_data_port, slave_offset);
    ioWait();

    writePort(master_data_port, 0x04);
    ioWait();
    writePort(slave_data_port, 0x02);
    ioWait();

    writePort(master_data_port, icw4_8086);
    ioWait();
    writePort(slave_data_port, icw4_8086);
    ioWait();

    writePort(master_data_port, preserved_master_mask);
    ioWait();
    writePort(slave_data_port, preserved_slave_mask);
    ioWait();
}

fn readRegister(command_port: u16, register_select: u8) u8 {
    writePort(command_port, register_select);
    ioWait();
    return readPort(command_port);
}

fn ioWait() void {
    if (!hardwareBacked()) return;
    var idx: usize = 0;
    while (idx < 16) : (idx += 1) {
        std.atomic.spinLoopHint();
    }
}

fn readPort(port: u16) u8 {
    if (builtin.is_test and test_enabled) {
        return switch (port) {
            master_data_port => test_master_mask,
            slave_data_port => test_slave_mask,
            master_command_port => switch (test_master_select) {
                .irr => test_master_irr,
                .isr => test_master_isr,
                .none => 0,
            },
            slave_command_port => switch (test_slave_select) {
                .irr => test_slave_irr,
                .isr => test_slave_isr,
                .none => 0,
            },
            else => 0,
        };
    }
    if (!hardwareBacked()) return 0;
    return asm volatile ("inb %[dx], %[al]"
        : [al] "={al}" (-> u8),
        : [dx] "{dx}" (port),
        : .{ .memory = true });
}

fn writePort(port: u16, value: u8) void {
    if (builtin.is_test and test_enabled) {
        if (test_write_count < test_writes.len) {
            test_writes[test_write_count] = .{ .port = port, .value = value };
            test_write_count += 1;
        }
        switch (port) {
            master_data_port => test_master_mask = value,
            slave_data_port => test_slave_mask = value,
            master_command_port => test_master_select = switch (value) {
                ocw3_read_irr => .irr,
                ocw3_read_isr => .isr,
                else => .none,
            },
            slave_command_port => test_slave_select = switch (value) {
                ocw3_read_irr => .irr,
                ocw3_read_isr => .isr,
                else => .none,
            },
            else => {},
        }
        return;
    }
    if (!hardwareBacked()) return;
    asm volatile ("outb %[al], %[dx]"
        :
        : [dx] "{dx}" (port),
          [al] "{al}" (value),
        : .{ .memory = true });
}

test "pic probe exports bounded remap and control state with synthetic overrides" {
    resetForTest();
    x86_bootstrap.init();
    try std.testing.expect(x86_bootstrap.oc_interrupt_mask_apply_profile(abi.interrupt_mask_profile_external_all));
    test_enabled = true;
    test_master_mask = 0xFB;
    test_slave_mask = 0xFF;
    test_master_irr = 0x04;
    test_slave_irr = 0x00;
    test_master_isr = 0x02;
    test_slave_isr = 0x00;

    try probe();

    const snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u32, abi.pic_magic), snapshot.magic);
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, 1), snapshot.remapped);
    try std.testing.expectEqual(@as(u8, 1), snapshot.slave_present);
    try std.testing.expectEqual(@as(u8, 0), snapshot.auto_eoi);
    try std.testing.expectEqual(@as(u8, master_offset), snapshot.master_offset);
    try std.testing.expectEqual(@as(u8, slave_offset), snapshot.slave_offset);
    try std.testing.expectEqual(@as(u8, 0xFB), snapshot.master_mask);
    try std.testing.expectEqual(@as(u8, 0xFF), snapshot.slave_mask);
    try std.testing.expectEqual(@as(u8, 0x04), snapshot.master_irr);
    try std.testing.expectEqual(@as(u8, 0x02), snapshot.master_isr);
    try std.testing.expectEqual(@as(u16, 15), snapshot.hardware_masked_irq_count);
    try std.testing.expectEqual(abi.interrupt_mask_profile_external_all, snapshot.control_mask_profile);
    try std.testing.expectEqual(@as(u32, 224), snapshot.control_masked_count);
    try std.testing.expectEqual(@as(u64, 0), snapshot.control_ignored_count);
    try std.testing.expectEqual(@as(u8, 0), snapshot.last_masked_vector);
    try std.testing.expect(test_write_count >= 12);

    const render = try renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "remapped=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "master_offset=0x20") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "slave_offset=0x28") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "control_mask_profile=1") != null);
}
