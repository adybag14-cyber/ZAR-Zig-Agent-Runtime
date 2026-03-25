// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const acpi = @import("acpi.zig");

const apic_base_msr_index: u32 = 0x1B;
const apic_base_bsp_bit: u64 = 1 << 8;
const apic_base_enable_bit: u64 = 1 << 11;
const cpuid_apic_bit: u32 = 1 << 9;
const cpuid_htt_bit: u32 = 1 << 28;
const cpuid_x2apic_bit: u32 = 1 << 21;

const lapic_id_offset: usize = 0x20;
const lapic_version_offset: usize = 0x30;
const lapic_spurious_offset: usize = 0xF0;
const lapic_lvt_timer_offset: usize = 0x320;
const lapic_lvt_error_offset: usize = 0x370;

pub const Error = error{
    UnsupportedPlatform,
    ApicUnsupported,
    LocalApicDisabled,
    MmioUnavailable,
};

const CpuidLeaf1 = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

var state: abi.BaremetalLapicState = zeroState();

const test_mmio_words_len: usize = 256;
var test_leaf1_override: ?CpuidLeaf1 = null;
var test_apic_base_override: ?u64 = null;
var test_mmio_words: ?[]volatile u32 = null;

fn zeroState() abi.BaremetalLapicState {
    return .{
        .magic = abi.lapic_magic,
        .api_version = abi.api_version,
        .present = 0,
        .apic_supported = 0,
        .enabled = 0,
        .x2apic_supported = 0,
        .bootstrap_processor = 0,
        .topology_present = 0,
        .supports_smp = 0,
        .reserved0 = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .current_apic_id = 0,
        .cpuid_apic_id = 0,
        .version = 0,
        .spurious_vector = 0,
        .timer_lvt = 0,
        .error_lvt = 0,
        .apic_base_msr = 0,
        .local_apic_addr = 0,
    };
}

pub fn resetForTest() void {
    state = zeroState();
    test_leaf1_override = null;
    test_apic_base_override = null;
    test_mmio_words = null;
}

pub fn statePtr() *const abi.BaremetalLapicState {
    return &state;
}

pub fn init() void {
    state = zeroState();
    probe() catch {};
}

pub fn probe() Error!void {
    state = zeroState();
    if (!runtimeCanProbe()) return error.UnsupportedPlatform;

    const topology = acpi.cpuTopologyStatePtr().*;
    state.topology_present = topology.present;
    state.supports_smp = topology.supports_smp;
    state.requested_cpu_count = topology.enabled_count;

    const leaf1 = cpuidLeaf1();
    state.apic_supported = if ((leaf1.edx & cpuid_apic_bit) != 0) 1 else 0;
    state.present = state.apic_supported;
    if (state.apic_supported == 0) return error.ApicUnsupported;

    state.x2apic_supported = if ((leaf1.ecx & cpuid_x2apic_bit) != 0) 1 else 0;
    state.cpuid_apic_id = (leaf1.ebx >> 24) & 0xFF;
    const logical_processor_count = @as(u16, @intCast((leaf1.ebx >> 16) & 0xFF));
    state.logical_processor_count = if ((leaf1.edx & cpuid_htt_bit) != 0 and logical_processor_count != 0) logical_processor_count else 1;

    const apic_base_msr = readApicBaseMsr();
    state.apic_base_msr = apic_base_msr;
    state.bootstrap_processor = if ((apic_base_msr & apic_base_bsp_bit) != 0) 1 else 0;
    state.enabled = if ((apic_base_msr & apic_base_enable_bit) != 0) 1 else 0;
    state.local_apic_addr = apic_base_msr & 0xFFFFF000;
    if (state.enabled == 0) return error.LocalApicDisabled;

    const mmio_words = resolveMmioWords(state.local_apic_addr) orelse return error.MmioUnavailable;
    state.current_apic_id = (readReg(mmio_words, lapic_id_offset) >> 24) & 0xFF;
    state.version = readReg(mmio_words, lapic_version_offset);
    state.spurious_vector = readReg(mmio_words, lapic_spurious_offset);
    state.timer_lvt = readReg(mmio_words, lapic_lvt_timer_offset);
    state.error_lvt = readReg(mmio_words, lapic_lvt_error_offset);
}

pub fn renderAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "present={d}\napic_supported={d}\nenabled={d}\nx2apic_supported={d}\nbootstrap_processor={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\ncpuid_apic_id={d}\ncurrent_apic_id={d}\nversion=0x{x}\nspurious_vector=0x{x}\ntimer_lvt=0x{x}\nerror_lvt=0x{x}\napic_base_msr=0x{x}\nlocal_apic_addr=0x{x}\n",
        .{
            state.present,
            state.apic_supported,
            state.enabled,
            state.x2apic_supported,
            state.bootstrap_processor,
            state.requested_cpu_count,
            state.logical_processor_count,
            state.cpuid_apic_id,
            state.current_apic_id,
            state.version,
            state.spurious_vector,
            state.timer_lvt,
            state.error_lvt,
            state.apic_base_msr,
            state.local_apic_addr,
        },
    );
}

pub fn renderSmpAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "topology_present={d}\nsupports_smp={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbootstrap_processor={d}\ncurrent_apic_id={d}\n",
        .{
            state.topology_present,
            state.supports_smp,
            state.requested_cpu_count,
            state.logical_processor_count,
            state.bootstrap_processor,
            state.current_apic_id,
        },
    );
}

fn runtimeCanProbe() bool {
    if (builtin.is_test and (test_leaf1_override != null or test_apic_base_override != null or test_mmio_words != null)) return true;
    return builtin.os.tag == .freestanding and (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64);
}

fn cpuidLeaf1() CpuidLeaf1 {
    if (builtin.is_test) {
        if (test_leaf1_override) |leaf1| return leaf1;
    }
    if (builtin.cpu.arch != .x86 and builtin.cpu.arch != .x86_64) return .{ .eax = 0, .ebx = 0, .ecx = 0, .edx = 0 };

    var eax: u32 = 1;
    var ebx: u32 = 0;
    var ecx: u32 = 0;
    var edx: u32 = 0;
    asm volatile (
        \\cpuid
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [leaf] "{eax}" (eax),
          [subleaf] "{ecx}" (ecx),
        : .{ .memory = true }
    );
    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

fn readApicBaseMsr() u64 {
    if (builtin.is_test) {
        if (test_apic_base_override) |value| return value;
    }
    if (builtin.cpu.arch != .x86 and builtin.cpu.arch != .x86_64) return 0;
    var low: u32 = 0;
    var high: u32 = 0;
    asm volatile (
        \\rdmsr
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
        : [msr] "{ecx}" (apic_base_msr_index),
        : .{ .memory = true }
    );
    return (@as(u64, high) << 32) | low;
}

fn resolveMmioWords(local_apic_addr: u64) ?[]volatile u32 {
    if (builtin.is_test) {
        if (test_mmio_words) |words| return words;
    }
    if (local_apic_addr == 0) return null;
    const ptr = @as([*]volatile u32, @ptrFromInt(@as(usize, @intCast(local_apic_addr))));
    return ptr[0..test_mmio_words_len];
}

fn readReg(mmio_words: []volatile u32, offset: usize) u32 {
    const index = offset / @sizeOf(u32);
    if (index >= mmio_words.len) return 0;
    return mmio_words[index];
}

test "lapic probe exports bounded register state with synthetic overrides" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    var mmio_words = [_]u32{0} ** test_mmio_words_len;
    mmio_words[lapic_id_offset / 4] = 0x01000000;
    mmio_words[lapic_version_offset / 4] = 0x00050014;
    mmio_words[lapic_spurious_offset / 4] = 0x000001FF;
    mmio_words[lapic_lvt_timer_offset / 4] = 0x00010040;
    mmio_words[lapic_lvt_error_offset / 4] = 0x000100FE;

    test_leaf1_override = .{
        .eax = 0,
        .ebx = (@as(u32, 1) << 24) | (@as(u32, 2) << 16),
        .ecx = 0,
        .edx = cpuid_apic_bit | cpuid_htt_bit,
    };
    test_apic_base_override = 0xFEE00000 | apic_base_bsp_bit | apic_base_enable_bit;
    test_mmio_words = mmio_words[0..];

    try probe();

    const snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u32, abi.lapic_magic), snapshot.magic);
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, 1), snapshot.apic_supported);
    try std.testing.expectEqual(@as(u8, 1), snapshot.enabled);
    try std.testing.expectEqual(@as(u8, 1), snapshot.bootstrap_processor);
    try std.testing.expectEqual(@as(u8, 1), snapshot.topology_present);
    try std.testing.expectEqual(@as(u8, 1), snapshot.supports_smp);
    try std.testing.expectEqual(@as(u16, 2), snapshot.requested_cpu_count);
    try std.testing.expectEqual(@as(u16, 2), snapshot.logical_processor_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.cpuid_apic_id);
    try std.testing.expectEqual(@as(u32, 1), snapshot.current_apic_id);
    try std.testing.expectEqual(@as(u32, 0x00050014), snapshot.version);
    try std.testing.expectEqual(@as(u32, 0x000001FF), snapshot.spurious_vector);

    const lapic_render = try renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(lapic_render);
    try std.testing.expect(std.mem.indexOf(u8, lapic_render, "logical_processor_count=2") != null);

    const smp_render = try renderSmpAlloc(std.testing.allocator);
    defer std.testing.allocator.free(smp_render);
    try std.testing.expect(std.mem.indexOf(u8, smp_render, "supports_smp=1") != null);
}
