// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi.zig");
const acpi = @import("acpi.zig");
const lapic = @import("lapic.zig");

const lapic_icr_low_offset: usize = 0x300;
const lapic_icr_high_offset: usize = 0x310;
const lapic_error_status_offset: usize = 0x280;
const lapic_spurious_offset: usize = 0x0F0;
const lapic_delivery_pending_bit: u32 = 1 << 12;
const lapic_software_enable_bit: u32 = 1 << 8;
const lapic_delivery_mode_init: u32 = 0x00000500;
const lapic_delivery_mode_startup: u32 = 0x00000600;
const lapic_level_assert: u32 = 0x00004000;
const lapic_trigger_level: u32 = 0x00008000;
const cmos_index_port: u16 = 0x70;
const cmos_data_port: u16 = 0x71;
const cmos_shutdown_status_register: u8 = 0x0F;
const cmos_shutdown_warm_reset: u8 = 0x0A;
const warm_reset_vector_offset_phys: usize = 0x467;
const warm_reset_vector_segment_phys: usize = 0x469;
const ap_command_ping: u32 = 1;
const ap_command_halt: u32 = 2;
const startup_timeout_iterations: usize = 120_000_000;
const delivery_timeout_iterations: usize = 2_000_000;
const init_settle_delay_iterations: usize = 24_000_000;
const startup_retry_delay_iterations: usize = 1_000_000;
const first_startup_timeout_iterations: usize = 8_000_000;
const command_timeout_iterations: usize = 20_000_000;
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
    ApNotStarted,
    CommandTimeout,
};

var state: abi.BaremetalApStartupState = zeroState();
const DiagnosticsState = struct {
    warm_reset_programmed: u8 = 0,
    warm_reset_vector_segment: u16 = 0,
    warm_reset_vector_offset: u16 = 0,
    init_ipi_count: u32 = 0,
    startup_ipi_count: u32 = 0,
    last_delivery_status: u32 = 0,
    last_accept_status: u32 = 0,
};

var diagnostics = DiagnosticsState{};
const SharedStorage = struct {
    var stage: u32 = 0;
    var started: u32 = 0;
    var halted: u32 = 0;
    var startup_count: u32 = 0;
    var reported_apic_id: u32 = 0;
    var target_apic_id: u32 = 0;
    var bsp_apic_id: u32 = 0;
    var local_apic_addr: u32 = 0;
    var command_kind: u32 = 0;
    var command_seq: u32 = 0;
    var response_seq: u32 = 0;
    var heartbeat: u32 = 0;
    var ping_count: u32 = 0;
};

var test_cmos_shutdown_value_ptr: ?*u8 = null;
var test_warm_reset_offset_ptr: ?*u16 = null;
var test_warm_reset_segment_ptr: ?*u16 = null;

const SharedExtern = struct {
    extern var oc_i386_ap_shared_stage: u32;
    extern var oc_i386_ap_shared_started: u32;
    extern var oc_i386_ap_shared_halted: u32;
    extern var oc_i386_ap_shared_startup_count: u32;
    extern var oc_i386_ap_shared_reported_apic_id: u32;
    extern var oc_i386_ap_shared_target_apic_id: u32;
    extern var oc_i386_ap_shared_bsp_apic_id: u32;
    extern var oc_i386_ap_shared_local_apic_addr: u32;
    extern var oc_i386_ap_shared_command_kind: u32;
    extern var oc_i386_ap_shared_command_seq: u32;
    extern var oc_i386_ap_shared_response_seq: u32;
    extern var oc_i386_ap_shared_heartbeat: u32;
    extern var oc_i386_ap_shared_ping_count: u32;
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

fn sharedCommandKindPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_command_kind else &SharedStorage.command_kind;
}

fn sharedCommandSeqPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_command_seq else &SharedStorage.command_seq;
}

fn sharedResponseSeqPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_response_seq else &SharedStorage.response_seq;
}

fn sharedHeartbeatPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_heartbeat else &SharedStorage.heartbeat;
}

fn sharedPingCountPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_ping_count else &SharedStorage.ping_count;
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
        .command_seq = 0,
        .response_seq = 0,
        .heartbeat_count = 0,
        .ping_count = 0,
        .warm_reset_programmed = 0,
        .reserved2 = .{ 0, 0, 0 },
        .warm_reset_vector_segment = 0,
        .warm_reset_vector_offset = 0,
        .init_ipi_count = 0,
        .startup_ipi_count = 0,
        .last_delivery_status = 0,
        .last_accept_status = 0,
    };
}

pub fn resetForTest() void {
    state = zeroState();
    diagnostics = .{};
    writeStateVar(sharedStagePtr(), 0);
    writeStateVar(sharedStartedPtr(), 0);
    writeStateVar(sharedHaltedPtr(), 0);
    writeStateVar(sharedStartupCountPtr(), 0);
    writeStateVar(sharedReportedApicIdPtr(), 0);
    writeStateVar(sharedTargetApicIdPtr(), 0);
    writeStateVar(sharedBspApicIdPtr(), 0);
    writeStateVar(sharedLocalApicAddrPtr(), 0);
    writeStateVar(sharedCommandKindPtr(), 0);
    writeStateVar(sharedCommandSeqPtr(), 0);
    writeStateVar(sharedResponseSeqPtr(), 0);
    writeStateVar(sharedHeartbeatPtr(), 0);
    writeStateVar(sharedPingCountPtr(), 0);
    test_cmos_shutdown_value_ptr = null;
    test_warm_reset_offset_ptr = null;
    test_warm_reset_segment_ptr = null;
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
    programWarmResetVector(trampoline_phys);
    defer clearWarmResetVector();
    refreshState();
    state.supported = 1;
    state.attempted = 1;

    const regs = lapicRegs(lapic_addr_u32);
    writeStateVar(sharedStagePtr(), 0x10);
    diagnostics.init_ipi_count += 1;
    enableLocalApic(regs);
    sendInitIpi(regs, target_apic_id) catch return error.DeliveryTimeout;
    writeStateVar(sharedStagePtr(), 0x11);
    spinDelay(init_settle_delay_iterations);
    diagnostics.init_ipi_count += 1;
    sendInitDeassertIpi(regs, target_apic_id) catch return error.DeliveryTimeout;
    writeStateVar(sharedStagePtr(), 0x12);
    spinDelay(startup_retry_delay_iterations);
    clearErrorStatus(regs);
    diagnostics.startup_ipi_count += 1;
    sendStartupIpi(regs, target_apic_id, startup_vector) catch return error.DeliveryTimeout;
    diagnostics.last_accept_status = readAcceptStatus(regs);
    writeStateVar(sharedStagePtr(), 0x13);
    if (waitForStartedTarget(first_startup_timeout_iterations)) return;

    spinDelay(startup_retry_delay_iterations);
    clearErrorStatus(regs);
    diagnostics.startup_ipi_count += 1;
    sendStartupIpi(regs, target_apic_id, startup_vector) catch return error.DeliveryTimeout;
    diagnostics.last_accept_status = readAcceptStatus(regs);
    writeStateVar(sharedStagePtr(), 0x14);

    if (waitForStartedTarget(startup_timeout_iterations)) return;
    refreshState();
    if (state.started == 0) return error.StartupTimeout;
    if (state.reported_apic_id != state.target_apic_id) return error.WrongCpuStarted;
    return error.StartupTimeout;
}

fn waitForStartedTarget(iterations: usize) bool {
    var remaining = iterations;
    while (remaining > 0) : (remaining -= 1) {
        refreshState();
        if (state.started == 1 and
            state.reported_apic_id == state.target_apic_id and
            state.last_stage >= 4 and
            state.heartbeat_count != 0)
        {
            return true;
        }
        std.atomic.spinLoopHint();
    }
    return false;
}

pub fn pingStartedAp() Error!void {
    refreshState();
    if (state.started == 0 or state.halted == 1) return error.ApNotStarted;
    try issueCommand(ap_command_ping);
    refreshState();
    if (state.ping_count == 0 or state.last_stage != 5) return error.CommandTimeout;
}

pub fn haltStartedAp() Error!void {
    refreshState();
    if (state.started == 0 or state.halted == 1) return error.ApNotStarted;
    try issueCommand(ap_command_halt);
    var remaining = command_timeout_iterations;
    while (remaining > 0) : (remaining -= 1) {
        refreshState();
        if (state.halted == 1 and state.last_stage == 6) return;
        std.atomic.spinLoopHint();
    }
    return error.CommandTimeout;
}

pub fn renderAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    return std.fmt.allocPrint(
        allocator,
        "supported={d}\nattempted={d}\nstarted={d}\nhalted={d}\nlast_stage={d}\nstartup_vector=0x{x}\ntrampoline_phys=0x{x}\nbsp_apic_id={d}\ntarget_apic_id={d}\nreported_apic_id={d}\nstartup_count={d}\nlapic_addr=0x{x}\nrequested_cpu_count={d}\nlogical_processor_count={d}\ncommand_seq={d}\nresponse_seq={d}\nheartbeat_count={d}\nping_count={d}\nwarm_reset_programmed={d}\nwarm_reset_vector_segment=0x{x}\nwarm_reset_vector_offset=0x{x}\ninit_ipi_count={d}\nstartup_ipi_count={d}\nlast_delivery_status=0x{x}\nlast_accept_status=0x{x}\n",
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
            state.command_seq,
            state.response_seq,
            state.heartbeat_count,
            state.ping_count,
            state.warm_reset_programmed,
            state.warm_reset_vector_segment,
            state.warm_reset_vector_offset,
            state.init_ipi_count,
            state.startup_ipi_count,
            state.last_delivery_status,
            state.last_accept_status,
        },
    );
}

fn refreshState() void {
    const topology = acpi.cpuTopologyStatePtr().*;
    const lapic_state = lapic.statePtr().*;
    state = zeroState();
    state.supported = if (builtin.os.tag == .freestanding and builtin.cpu.arch == .x86 and topology.present == 1 and topology.supports_smp == 1 and topology.enabled_count >= 2 and lapic_state.present == 1 and lapic_state.enabled == 1) 1 else 0;
    state.attempted = if (readStateVar(sharedTargetApicIdPtr()) != 0 or readStateVar(sharedStartedPtr()) != 0 or readStateVar(sharedCommandSeqPtr()) != 0) 1 else 0;
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
    state.command_seq = readStateVar(sharedCommandSeqPtr());
    state.response_seq = readStateVar(sharedResponseSeqPtr());
    state.heartbeat_count = readStateVar(sharedHeartbeatPtr());
    state.ping_count = readStateVar(sharedPingCountPtr());
    state.warm_reset_programmed = diagnostics.warm_reset_programmed;
    state.warm_reset_vector_segment = diagnostics.warm_reset_vector_segment;
    state.warm_reset_vector_offset = diagnostics.warm_reset_vector_offset;
    state.init_ipi_count = diagnostics.init_ipi_count;
    state.startup_ipi_count = diagnostics.startup_ipi_count;
    state.last_delivery_status = diagnostics.last_delivery_status;
    state.last_accept_status = diagnostics.last_accept_status;
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

fn programWarmResetVector(start_eip: u32) void {
    const vector_segment = @as(u16, @truncate(start_eip >> 4));
    const vector_offset = @as(u16, @truncate(start_eip & 0x0F));
    diagnostics.warm_reset_programmed = 1;
    diagnostics.warm_reset_vector_segment = vector_segment;
    diagnostics.warm_reset_vector_offset = vector_offset;
    writeWarmResetOffset(vector_offset);
    writeWarmResetSegment(vector_segment);
    writeCmosShutdown(cmos_shutdown_warm_reset);
}

fn clearWarmResetVector() void {
    writeCmosShutdown(0);
    writeWarmResetOffset(0);
    writeWarmResetSegment(0);
}

fn writeCmosShutdown(value: u8) void {
    if (builtin.is_test) {
        if (test_cmos_shutdown_value_ptr) |ptr| {
            ptr.* = value;
            return;
        }
    }
    if (builtin.cpu.arch != .x86 and builtin.cpu.arch != .x86_64) return;
    writePort8(cmos_index_port, cmos_shutdown_status_register);
    writePort8(cmos_data_port, value);
}

fn writeWarmResetOffset(value: u16) void {
    if (builtin.is_test) {
        if (test_warm_reset_offset_ptr) |ptr| {
            ptr.* = value;
            return;
        }
    }
    const ptr = @as(*align(1) volatile u16, @ptrFromInt(warm_reset_vector_offset_phys));
    ptr.* = value;
}

fn writeWarmResetSegment(value: u16) void {
    if (builtin.is_test) {
        if (test_warm_reset_segment_ptr) |ptr| {
            ptr.* = value;
            return;
        }
    }
    const ptr = @as(*align(1) volatile u16, @ptrFromInt(warm_reset_vector_segment_phys));
    ptr.* = value;
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

fn readAcceptStatus(regs: [*]volatile u32) u32 {
    return readReg(regs, lapic_error_status_offset) & 0xEF;
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
        if ((readReg(regs, lapic_icr_low_offset) & lapic_delivery_pending_bit) == 0) {
            diagnostics.last_delivery_status = 0;
            return;
        }
        std.atomic.spinLoopHint();
    }
    diagnostics.last_delivery_status = readReg(regs, lapic_icr_low_offset);
    return error.DeliveryTimeout;
}

fn readPort8(port: u16) u8 {
    if (builtin.cpu.arch != .x86 and builtin.cpu.arch != .x86_64) return 0;
    return asm volatile ("inb %[dx], %[al]"
        : [al] "={al}" (-> u8),
        : [dx] "{dx}" (port),
    );
}

fn writePort8(port: u16, value: u8) void {
    if (builtin.cpu.arch != .x86 and builtin.cpu.arch != .x86_64) return;
    asm volatile ("outb %[al], %[dx]"
        :
        : [al] "{al}" (value),
          [dx] "{dx}" (port),
    );
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

fn clearErrorStatus(regs: [*]volatile u32) void {
    writeReg(regs, lapic_error_status_offset, 0);
    writeReg(regs, lapic_error_status_offset, 0);
}

fn issueCommand(command_kind: u32) Error!void {
    const next_seq = readStateVar(sharedCommandSeqPtr()) + 1;
    writeStateVar(sharedCommandKindPtr(), command_kind);
    writeStateVar(sharedCommandSeqPtr(), next_seq);

    var remaining = command_timeout_iterations;
    while (remaining > 0) : (remaining -= 1) {
        if (readStateVar(sharedResponseSeqPtr()) == next_seq) return;
        std.atomic.spinLoopHint();
    }
    return error.CommandTimeout;
}

fn readStateVar(ptr: *u32) u32 {
    return @as(*volatile u32, @ptrCast(ptr)).*;
}

fn writeStateVar(ptr: *u32, value: u32) void {
    @as(*volatile u32, @ptrCast(ptr)).* = value;
}

fn testApResponder() void {
    while (true) {
        const command_seq = readStateVar(sharedCommandSeqPtr());
        if (command_seq == 1 and readStateVar(sharedResponseSeqPtr()) == 0) {
            writeStateVar(sharedHeartbeatPtr(), 2);
            writeStateVar(sharedPingCountPtr(), 1);
            writeStateVar(sharedStagePtr(), 5);
            writeStateVar(sharedResponseSeqPtr(), 1);
        } else if (command_seq == 2 and readStateVar(sharedResponseSeqPtr()) == 1) {
            writeStateVar(sharedHeartbeatPtr(), 3);
            writeStateVar(sharedStagePtr(), 6);
            writeStateVar(sharedHaltedPtr(), 1);
            writeStateVar(sharedResponseSeqPtr(), 2);
            return;
        }
        std.atomic.spinLoopHint();
    }
}

test "i386 ap startup render reflects bounded exported state" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);
    diagnostics.warm_reset_programmed = 1;
    diagnostics.warm_reset_vector_segment = 0x8000;
    diagnostics.warm_reset_vector_offset = 0;
    diagnostics.init_ipi_count = 2;
    diagnostics.startup_ipi_count = 2;
    diagnostics.last_delivery_status = 0;
    diagnostics.last_accept_status = 0;
    writeStateVar(sharedBspApicIdPtr(), 0);
    writeStateVar(sharedTargetApicIdPtr(), 1);
    writeStateVar(sharedLocalApicAddrPtr(), 0xFEE00000);
    writeStateVar(sharedStagePtr(), 4);
    writeStateVar(sharedStartedPtr(), 1);
    writeStateVar(sharedHaltedPtr(), 1);
    writeStateVar(sharedStartupCountPtr(), 1);
    writeStateVar(sharedReportedApicIdPtr(), 1);
    writeStateVar(sharedCommandSeqPtr(), 2);
    writeStateVar(sharedResponseSeqPtr(), 2);
    writeStateVar(sharedHeartbeatPtr(), 16);
    writeStateVar(sharedPingCountPtr(), 1);
    writeStateVar(sharedStagePtr(), 6);

    const render = try renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "started=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "response_seq=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "ping_count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "target_apic_id=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "trampoline_phys=0x80000") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "warm_reset_programmed=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "startup_ipi_count=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "warm_reset_vector_segment=0x8000") != null);
}

test "i386 ap startup command helpers drive bounded ping and halt telemetry" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);
    writeStateVar(sharedStartedPtr(), 1);
    writeStateVar(sharedStagePtr(), 4);
    writeStateVar(sharedReportedApicIdPtr(), 1);
    writeStateVar(sharedTargetApicIdPtr(), 1);
    writeStateVar(sharedHeartbeatPtr(), 1);

    const responder = try std.Thread.spawn(.{}, testApResponder, .{});
    defer responder.join();

    try pingStartedAp();
    var snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u32, 1), snapshot.command_seq);
    try std.testing.expectEqual(@as(u32, 1), snapshot.response_seq);
    try std.testing.expectEqual(@as(u32, 1), snapshot.ping_count);
    try std.testing.expectEqual(@as(u8, 0), snapshot.halted);

    try haltStartedAp();
    snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u32, 2), snapshot.command_seq);
    try std.testing.expectEqual(@as(u32, 2), snapshot.response_seq);
    try std.testing.expectEqual(@as(u8, 1), snapshot.halted);
    try std.testing.expectEqual(@as(u8, 6), snapshot.last_stage);
}

test "i386 ap startup warm reset programming records bounded diagnostics" {
    resetForTest();
    var cmos_shutdown: u8 = 0;
    var warm_reset_offset: u16 = 0xFFFF;
    var warm_reset_segment: u16 = 0xFFFF;
    test_cmos_shutdown_value_ptr = &cmos_shutdown;
    test_warm_reset_offset_ptr = &warm_reset_offset;
    test_warm_reset_segment_ptr = &warm_reset_segment;

    programWarmResetVector(trampoline_phys);
    try std.testing.expectEqual(@as(u8, cmos_shutdown_warm_reset), cmos_shutdown);
    try std.testing.expectEqual(@as(u16, 0), warm_reset_offset);
    try std.testing.expectEqual(@as(u16, 0x8000), warm_reset_segment);
    try std.testing.expectEqual(@as(u8, 1), diagnostics.warm_reset_programmed);
    try std.testing.expectEqual(@as(u16, 0), diagnostics.warm_reset_vector_offset);
    try std.testing.expectEqual(@as(u16, 0x8000), diagnostics.warm_reset_vector_segment);

    clearWarmResetVector();
    try std.testing.expectEqual(@as(u8, 0), cmos_shutdown);
    try std.testing.expectEqual(@as(u16, 0), warm_reset_offset);
    try std.testing.expectEqual(@as(u16, 0), warm_reset_segment);
}
