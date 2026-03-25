// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const acpi = @import("acpi.zig");
const lapic = @import("lapic.zig");

const lapic_icr_low_offset: usize = 0x300;
const lapic_icr_high_offset: usize = 0x310;
const lapic_spurious_offset: usize = 0x0F0;
const lapic_delivery_pending_bit: u32 = 1 << 12;
const lapic_software_enable_bit: u32 = 1 << 8;
const lapic_delivery_mode_init: u32 = 0x00000500;
const lapic_delivery_mode_startup: u32 = 0x00000600;
const lapic_level_assert: u32 = 0x00004000;
const lapic_trigger_level: u32 = 0x00008000;
const startup_timeout_iterations: usize = 20_000_000;
const delivery_timeout_iterations: usize = 2_000_000;
const inter_ipi_delay_iterations: usize = 1_000_000;
pub const trampoline_phys: u32 = 0x00080000;
pub const startup_vector: u8 = @as(u8, @intCast(trampoline_phys >> 12));
const use_extern_shared = builtin.os.tag == .freestanding and builtin.cpu.arch == .x86 and !builtin.is_test;

pub const Error = error{
    UnsupportedPlatform,
    CpuTopologyMissing,
    NoSecondaryCpu,
    LapicUnavailable,
    DeliveryTimeout,
    StartupTimeout,
    WrongCpuStarted,
};

var state: abi.BaremetalApStartupState = zeroState();
const SharedStorage = struct {
    var stage: u32 = 0;
    var started: u32 = 0;
    var halted: u32 = 0;
    var startup_count: u32 = 0;
    var reported_apic_id: u32 = 0;
    var target_apic_id: u32 = 0;
    var bsp_apic_id: u32 = 0;
    var local_apic_addr: u32 = 0;
};

const SharedExtern = struct {
    extern var oc_i386_ap_shared_stage: u32;
    extern var oc_i386_ap_shared_started: u32;
    extern var oc_i386_ap_shared_halted: u32;
    extern var oc_i386_ap_shared_startup_count: u32;
    extern var oc_i386_ap_shared_reported_apic_id: u32;
    extern var oc_i386_ap_shared_target_apic_id: u32;
    extern var oc_i386_ap_shared_bsp_apic_id: u32;
    extern var oc_i386_ap_shared_local_apic_addr: u32;
};

fn sharedStagePtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_stage else &SharedStorage.stage;
}

fn sharedStartedPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_started else &SharedStorage.started;
}

fn sharedHaltedPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_halted else &SharedStorage.halted;
}

fn sharedStartupCountPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_startup_count else &SharedStorage.startup_count;
}

fn sharedReportedApicIdPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_reported_apic_id else &SharedStorage.reported_apic_id;
}

fn sharedTargetApicIdPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_target_apic_id else &SharedStorage.target_apic_id;
}

fn sharedBspApicIdPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_bsp_apic_id else &SharedStorage.bsp_apic_id;
}

fn sharedLocalApicAddrPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_local_apic_addr else &SharedStorage.local_apic_addr;
}

fn zeroState() abi.BaremetalApStartupState {
    return .{
        .magic = abi.ap_startup_magic,
        .api_version = abi.api_version,
        .supported = 0,
        .attempted = 0,
        .started = 0,
        .halted = 0,
        .last_stage = 0,
        .reserved0 = .{ 0, 0 },
        .startup_vector = startup_vector,
        .reserved1 = .{ 0, 0, 0 },
        .trampoline_phys = trampoline_phys,
        .bsp_apic_id = 0,
        .target_apic_id = 0,
        .reported_apic_id = 0,
        .startup_count = 0,
        .lapic_addr = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
    };
}

pub fn resetForTest() void {
    state = zeroState();
    writeStateVar(sharedStagePtr(), 0);
    writeStateVar(sharedStartedPtr(), 0);
    writeStateVar(sharedHaltedPtr(), 0);
    writeStateVar(sharedStartupCountPtr(), 0);
    writeStateVar(sharedReportedApicIdPtr(), 0);
    writeStateVar(sharedTargetApicIdPtr(), 0);
    writeStateVar(sharedBspApicIdPtr(), 0);
    writeStateVar(sharedLocalApicAddrPtr(), 0);
}

pub fn init() void {
    resetForTest();
}

pub fn statePtr() *const abi.BaremetalApStartupState {
    refreshState();
    return &state;
}

pub fn startupSingleAp() Error!void {
    resetForTest();
    if (builtin.os.tag != .freestanding or builtin.cpu.arch != .x86) return error.UnsupportedPlatform;

    const topology = acpi.cpuTopologyStatePtr().*;
    const lapic_state = lapic.statePtr().*;
    if (topology.present == 0 or topology.supports_smp == 0 or topology.enabled_count < 2) return error.CpuTopologyMissing;
    if (lapic_state.present == 0 or lapic_state.enabled == 0 or lapic_state.local_apic_addr == 0) return error.LapicUnavailable;

    const target_apic_id = findSecondaryApicId(lapic_state.current_apic_id) orelse return error.NoSecondaryCpu;
    const lapic_addr_u32 = @as(u32, @intCast(lapic_state.local_apic_addr & 0xFFFF_FFFF));
    writeStateVar(sharedBspApicIdPtr(), lapic_state.current_apic_id);
    writeStateVar(sharedTargetApicIdPtr(), target_apic_id);
    writeStateVar(sharedLocalApicAddrPtr(), lapic_addr_u32);
    refreshState();
    state.supported = 1;
    state.attempted = 1;

    const regs = lapicRegs(lapic_addr_u32);
    writeStateVar(sharedStagePtr(), 0x10);
    enableLocalApic(regs);
    sendInitIpi(regs, target_apic_id) catch return error.DeliveryTimeout;
    writeStateVar(sharedStagePtr(), 0x11);
    spinDelay(inter_ipi_delay_iterations);
    sendInitDeassertIpi(regs, target_apic_id) catch return error.DeliveryTimeout;
    writeStateVar(sharedStagePtr(), 0x12);
    spinDelay(inter_ipi_delay_iterations);
    sendStartupIpi(regs, target_apic_id, startup_vector) catch return error.DeliveryTimeout;
    writeStateVar(sharedStagePtr(), 0x13);
    spinDelay(inter_ipi_delay_iterations);
    sendStartupIpi(regs, target_apic_id, startup_vector) catch return error.DeliveryTimeout;
    writeStateVar(sharedStagePtr(), 0x14);

    var remaining = startup_timeout_iterations;
    while (remaining > 0) : (remaining -= 1) {
        refreshState();
        if (state.started == 1) break;
        std.atomic.spinLoopHint();
    }
    refreshState();
    if (state.started == 0) return error.StartupTimeout;
    if (state.reported_apic_id != state.target_apic_id) return error.WrongCpuStarted;
}

pub fn renderAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    return std.fmt.allocPrint(
        allocator,
        "supported={d}\nattempted={d}\nstarted={d}\nhalted={d}\nlast_stage={d}\nstartup_vector=0x{x}\ntrampoline_phys=0x{x}\nbsp_apic_id={d}\ntarget_apic_id={d}\nreported_apic_id={d}\nstartup_count={d}\nlapic_addr=0x{x}\nrequested_cpu_count={d}\nlogical_processor_count={d}\n",
        .{
            state.supported,
            state.attempted,
            state.started,
            state.halted,
            state.last_stage,
            state.startup_vector,
            state.trampoline_phys,
            state.bsp_apic_id,
            state.target_apic_id,
            state.reported_apic_id,
            state.startup_count,
            state.lapic_addr,
            state.requested_cpu_count,
            state.logical_processor_count,
        },
    );
}

fn refreshState() void {
    const topology = acpi.cpuTopologyStatePtr().*;
    const lapic_state = lapic.statePtr().*;
    state = zeroState();
    state.supported = if (builtin.os.tag == .freestanding and builtin.cpu.arch == .x86 and topology.present == 1 and topology.supports_smp == 1 and topology.enabled_count >= 2 and lapic_state.present == 1 and lapic_state.enabled == 1) 1 else 0;
    state.attempted = if (readStateVar(sharedTargetApicIdPtr()) != 0 or readStateVar(sharedStartedPtr()) != 0) 1 else 0;
    state.started = if (readStateVar(sharedStartedPtr()) != 0) 1 else 0;
    state.halted = if (readStateVar(sharedHaltedPtr()) != 0) 1 else 0;
    state.last_stage = @as(u8, @truncate(readStateVar(sharedStagePtr())));
    state.trampoline_phys = trampoline_phys;
    state.startup_vector = startup_vector;
    state.bsp_apic_id = readStateVar(sharedBspApicIdPtr());
    state.target_apic_id = readStateVar(sharedTargetApicIdPtr());
    state.reported_apic_id = readStateVar(sharedReportedApicIdPtr());
    state.startup_count = readStateVar(sharedStartupCountPtr());
    state.lapic_addr = readStateVar(sharedLocalApicAddrPtr());
    state.requested_cpu_count = topology.enabled_count;
    state.logical_processor_count = lapic_state.logical_processor_count;
}

fn findSecondaryApicId(current_apic_id: u32) ?u32 {
    var index: u16 = 0;
    while (index < acpi.cpuTopologyEntryCount()) : (index += 1) {
        const entry = acpi.cpuTopologyEntry(index);
        if (entry.enabled == 0) continue;
        if (entry.apic_id == @as(u8, @truncate(current_apic_id))) continue;
        return entry.apic_id;
    }
    return null;
}

fn lapicRegs(lapic_addr: u32) [*]volatile u32 {
    return @as([*]volatile u32, @ptrFromInt(@as(usize, lapic_addr)));
}

fn readReg(regs: [*]volatile u32, offset: usize) u32 {
    return regs[offset / @sizeOf(u32)];
}

fn writeReg(regs: [*]volatile u32, offset: usize, value: u32) void {
    regs[offset / @sizeOf(u32)] = value;
    _ = regs[offset / @sizeOf(u32)];
}

fn sendInitIpi(regs: [*]volatile u32, target_apic_id: u32) !void {
    writeReg(regs, lapic_icr_high_offset, target_apic_id << 24);
    writeReg(regs, lapic_icr_low_offset, lapic_delivery_mode_init | lapic_level_assert | lapic_trigger_level);
    try waitForDeliveryClear(regs);
}

fn sendInitDeassertIpi(regs: [*]volatile u32, target_apic_id: u32) !void {
    writeReg(regs, lapic_icr_high_offset, target_apic_id << 24);
    writeReg(regs, lapic_icr_low_offset, lapic_delivery_mode_init | lapic_trigger_level);
    try waitForDeliveryClear(regs);
}

fn sendStartupIpi(regs: [*]volatile u32, target_apic_id: u32, vector: u8) !void {
    writeReg(regs, lapic_icr_high_offset, target_apic_id << 24);
    writeReg(regs, lapic_icr_low_offset, lapic_delivery_mode_startup | vector);
    try waitForDeliveryClear(regs);
}

fn waitForDeliveryClear(regs: [*]volatile u32) !void {
    var remaining = delivery_timeout_iterations;
    while (remaining > 0) : (remaining -= 1) {
        if ((readReg(regs, lapic_icr_low_offset) & lapic_delivery_pending_bit) == 0) return;
        std.atomic.spinLoopHint();
    }
    return error.DeliveryTimeout;
}

fn spinDelay(iterations: usize) void {
    var remaining = iterations;
    while (remaining > 0) : (remaining -= 1) std.atomic.spinLoopHint();
}

fn enableLocalApic(regs: [*]volatile u32) void {
    const current = readReg(regs, lapic_spurious_offset);
    if ((current & lapic_software_enable_bit) != 0) return;
    writeReg(regs, lapic_spurious_offset, current | lapic_software_enable_bit);
}

fn readStateVar(ptr: *u32) u32 {
    return @as(*volatile u32, @ptrCast(ptr)).*;
}

fn writeStateVar(ptr: *u32, value: u32) void {
    @as(*volatile u32, @ptrCast(ptr)).* = value;
}

test "i386 ap startup render reflects bounded exported state" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);
    writeStateVar(sharedBspApicIdPtr(), 0);
    writeStateVar(sharedTargetApicIdPtr(), 1);
    writeStateVar(sharedLocalApicAddrPtr(), 0xFEE00000);
    writeStateVar(sharedStagePtr(), 4);
    writeStateVar(sharedStartedPtr(), 1);
    writeStateVar(sharedHaltedPtr(), 1);
    writeStateVar(sharedStartupCountPtr(), 1);
    writeStateVar(sharedReportedApicIdPtr(), 1);

    const render = try renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "started=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "target_apic_id=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "trampoline_phys=0x80000") != null);
}
