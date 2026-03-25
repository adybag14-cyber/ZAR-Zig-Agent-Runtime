// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const acpi = @import("acpi.zig");

const default_width_bits: u8 = 24;
const sample_mask: u32 = 0x00FF_FFFF;
const max_sample_attempts: u16 = 64;

pub const Error = error{
    UnsupportedPlatform,
    TimerUnavailable,
};

var state: abi.BaremetalPmTimerState = zeroState();

var test_enabled = false;
var test_port: u32 = 0;
var test_reads: [16]u32 = std.mem.zeroes([16]u32);
var test_read_len: usize = 0;
var test_read_index: usize = 0;

fn zeroState() abi.BaremetalPmTimerState {
    return .{
        .magic = abi.pm_timer_magic,
        .api_version = abi.api_version,
        .present = 0,
        .monotonic = 0,
        .width_bits = default_width_bits,
        .reserved0 = 0,
        .port = 0,
        .first_tick = 0,
        .second_tick = 0,
        .delta = 0,
        .sample_attempts = 0,
        .reserved1 = 0,
        .mask = sample_mask,
    };
}

pub fn resetForTest() void {
    state = zeroState();
    test_enabled = false;
    test_port = 0;
    @memset(&test_reads, 0);
    test_read_len = 0;
    test_read_index = 0;
}

pub fn statePtr() *const abi.BaremetalPmTimerState {
    return &state;
}

pub fn init() void {
    state = zeroState();
    probe() catch {};
}

pub fn probe() Error!void {
    state = zeroState();
    if (!runtimeCanProbe()) return error.UnsupportedPlatform;

    const port = resolvedPort() orelse return error.TimerUnavailable;
    const first = readTimer(port) & sample_mask;
    var second = first;
    var attempts: u16 = 0;
    while (attempts < max_sample_attempts) : (attempts += 1) {
        spinDelay(1024);
        second = readTimer(port) & sample_mask;
        if (second != first) break;
    }

    state.present = 1;
    state.port = port;
    state.first_tick = first;
    state.second_tick = second;
    state.sample_attempts = attempts + 1;
    state.delta = tickDelta(first, second);
    state.monotonic = if (state.delta != 0) 1 else 0;
}

pub fn renderAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "present={d}\nmonotonic={d}\nwidth_bits={d}\nport=0x{x}\nfirst_tick={d}\nsecond_tick={d}\ndelta={d}\nsample_attempts={d}\nmask=0x{x}\n",
        .{
            state.present,
            state.monotonic,
            state.width_bits,
            state.port,
            state.first_tick,
            state.second_tick,
            state.delta,
            state.sample_attempts,
            state.mask,
        },
    );
}

fn runtimeCanProbe() bool {
    if (builtin.is_test and test_enabled) return true;
    return builtin.os.tag == .freestanding and (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64);
}

fn resolvedPort() ?u32 {
    if (builtin.is_test and test_enabled and test_port != 0) return test_port;
    const snapshot = acpi.statePtr().*;
    if (snapshot.present != 1 or snapshot.pm_timer_block == 0) return null;
    return snapshot.pm_timer_block;
}

fn spinDelay(iterations: usize) void {
    var idx: usize = 0;
    while (idx < iterations) : (idx += 1) {
        std.atomic.spinLoopHint();
    }
}

fn tickDelta(first: u32, second: u32) u32 {
    if (second >= first) return second - first;
    return (sample_mask - first) + second + 1;
}

fn readTimer(port: u32) u32 {
    if (builtin.is_test and test_enabled) {
        if (test_read_index < test_read_len) {
            const value = test_reads[test_read_index];
            test_read_index += 1;
            return value;
        }
        return test_reads[test_read_len - 1];
    }
    return asm volatile ("inl %[dx], %[eax]"
        : [eax] "={eax}" (-> u32),
        : [dx] "{dx}" (@as(u16, @truncate(port))),
        : .{ .memory = true });
}

test "acpi pm timer probe exports bounded monotonic state with synthetic overrides" {
    resetForTest();
    test_enabled = true;
    test_port = 0x608;
    test_reads[0] = 0x0012_3400;
    test_reads[1] = 0x0012_3470;
    test_read_len = 2;

    try probe();

    const snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u32, abi.pm_timer_magic), snapshot.magic);
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, 1), snapshot.monotonic);
    try std.testing.expectEqual(@as(u8, default_width_bits), snapshot.width_bits);
    try std.testing.expectEqual(@as(u32, 0x608), snapshot.port);
    try std.testing.expectEqual(@as(u32, 0x0012_3400 & sample_mask), snapshot.first_tick);
    try std.testing.expectEqual(@as(u32, 0x0012_3470 & sample_mask), snapshot.second_tick);
    try std.testing.expect(snapshot.delta != 0);
    try std.testing.expect(snapshot.sample_attempts >= 1);
    try std.testing.expectEqual(sample_mask, snapshot.mask);

    const rendered = try renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "present=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "monotonic=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "port=0x608") != null);
}
