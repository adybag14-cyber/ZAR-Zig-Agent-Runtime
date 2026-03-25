// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");

const channel0_data_port: u16 = 0x40;
const command_port: u16 = 0x43;
const latch_channel0_command: u8 = 0x00;
const base_frequency_hz: u32 = 1_193_182;
const max_sample_attempts: u16 = 16;

pub const Error = error{
    UnsupportedPlatform,
};

var state: abi.BaremetalPitState = zeroState();

var test_enabled = false;
var test_latched_counts: [8]u16 = std.mem.zeroes([8]u16);
var test_latched_count_len: usize = 0;
var test_latched_read_index: usize = 0;
var test_active_latched_count: u16 = 0;
var test_active_latched_low: bool = true;

fn zeroState() abi.BaremetalPitState {
    return .{
        .magic = abi.pit_magic,
        .api_version = abi.api_version,
        .present = 0,
        .counter_changed = 0,
        .channel = 0,
        .reserved0 = .{ 0, 0, 0 },
        .data_port = channel0_data_port,
        .command_port = command_port,
        .first_count = 0,
        .second_count = 0,
        .delta = 0,
        .sample_attempts = 0,
        .base_frequency_hz = base_frequency_hz,
        .latch_command = latch_channel0_command,
    };
}

pub fn resetForTest() void {
    state = zeroState();
    test_enabled = false;
    @memset(&test_latched_counts, 0);
    test_latched_count_len = 0;
    test_latched_read_index = 0;
    test_active_latched_count = 0;
    test_active_latched_low = true;
}

pub fn statePtr() *const abi.BaremetalPitState {
    return &state;
}

pub fn init() void {
    state = zeroState();
    probe() catch {};
}

pub fn probe() Error!void {
    state = zeroState();
    if (!runtimeCanProbe()) return error.UnsupportedPlatform;

    const first = latchChannel0Count();
    var second = first;
    var attempts: u16 = 0;
    while (attempts < max_sample_attempts) : (attempts += 1) {
        spinDelay(4096);
        second = latchChannel0Count();
        if (second != first) break;
    }

    state.present = 1;
    state.first_count = first;
    state.second_count = second;
    state.counter_changed = if (second != first) 1 else 0;
    state.sample_attempts = attempts + 1;
    state.delta = if (first >= second) first - second else second - first;
}

pub fn renderAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "present={d}\ncounter_changed={d}\nchannel={d}\ndata_port=0x{x}\ncommand_port=0x{x}\nfirst_count={d}\nsecond_count={d}\ndelta={d}\nsample_attempts={d}\nbase_frequency_hz={d}\nlatch_command=0x{x}\n",
        .{
            state.present,
            state.counter_changed,
            state.channel,
            state.data_port,
            state.command_port,
            state.first_count,
            state.second_count,
            state.delta,
            state.sample_attempts,
            state.base_frequency_hz,
            state.latch_command,
        },
    );
}

fn runtimeCanProbe() bool {
    if (builtin.is_test and test_enabled) return true;
    return builtin.os.tag == .freestanding and (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64);
}

fn spinDelay(iterations: usize) void {
    var idx: usize = 0;
    while (idx < iterations) : (idx += 1) {
        std.atomic.spinLoopHint();
    }
}

fn latchChannel0Count() u16 {
    writePort(command_port, latch_channel0_command);
    const low = readPort(channel0_data_port);
    const high = readPort(channel0_data_port);
    return (@as(u16, high) << 8) | low;
}

fn readPort(port: u16) u8 {
    if (builtin.is_test and test_enabled) {
        if (port != channel0_data_port) return 0;
        const value = if (test_active_latched_low)
            @as(u8, @truncate(test_active_latched_count))
        else
            @as(u8, @truncate(test_active_latched_count >> 8));
        test_active_latched_low = !test_active_latched_low;
        return value;
    }
    return asm volatile ("inb %[dx], %[al]"
        : [al] "={al}" (-> u8),
        : [dx] "{dx}" (port),
        : .{ .memory = true });
}

fn writePort(port: u16, value: u8) void {
    if (builtin.is_test and test_enabled) {
        if (port == command_port and value == latch_channel0_command and test_latched_read_index < test_latched_count_len) {
            test_active_latched_count = test_latched_counts[test_latched_read_index];
            test_latched_read_index += 1;
            test_active_latched_low = true;
        }
        return;
    }
    asm volatile ("outb %[al], %[dx]"
        :
        : [dx] "{dx}" (port),
          [al] "{al}" (value),
        : .{ .memory = true });
}

test "pit probe exports bounded latch state with synthetic overrides" {
    resetForTest();
    test_enabled = true;
    test_latched_counts[0] = 0x9ABC;
    test_latched_counts[1] = 0x97FE;
    test_latched_count_len = 2;

    try probe();

    const snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u32, abi.pit_magic), snapshot.magic);
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, 1), snapshot.counter_changed);
    try std.testing.expectEqual(@as(u16, channel0_data_port), snapshot.data_port);
    try std.testing.expectEqual(@as(u16, command_port), snapshot.command_port);
    try std.testing.expectEqual(@as(u16, 0x9ABC), snapshot.first_count);
    try std.testing.expectEqual(@as(u16, 0x97FE), snapshot.second_count);
    try std.testing.expect(snapshot.delta != 0);
    try std.testing.expect(snapshot.sample_attempts >= 1);
    try std.testing.expectEqual(base_frequency_hz, snapshot.base_frequency_hz);

    const rendered = try renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "present=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "counter_changed=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "data_port=0x40") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "command_port=0x43") != null);
}
