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
const ap_command_work: u32 = 3;
const ap_command_batch_work: u32 = 4;
pub const max_task_batch_entries: usize = 8;
pub const max_ap_command_slots: usize = 4;
pub const max_multi_ap_entries: usize = 4;
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
    InvalidWorkBatch,
};

var state: abi.BaremetalApStartupState = zeroState();
var multi_state: abi.BaremetalApMultiState = zeroMultiState();
var multi_entries: [max_multi_ap_entries]abi.BaremetalApMultiEntry = std.mem.zeroes([max_multi_ap_entries]abi.BaremetalApMultiEntry);
var slot_state: abi.BaremetalApSlotState = zeroSlotState();
var slot_entries: [max_ap_command_slots]abi.BaremetalApSlotEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApSlotEntry);
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
    var boot_slot_index: u32 = 0;
    var stage: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var started: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var halted: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var startup_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var reported_apic_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var target_apic_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var bsp_apic_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var local_apic_addr: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var command_kind: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var command_value: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var command_seq: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var response_seq: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var heartbeat: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var ping_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var work_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_work_value: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var work_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var task_values: [max_ap_command_slots][max_task_batch_entries]u32 = [_][max_task_batch_entries]u32{[_]u32{0} ** max_task_batch_entries} ** max_ap_command_slots;
    var batch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_batch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_batch_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
};

var test_cmos_shutdown_value_ptr: ?*u8 = null;
var test_warm_reset_offset_ptr: ?*u16 = null;
var test_warm_reset_segment_ptr: ?*u16 = null;

const SharedExtern = struct {
    extern var oc_i386_ap_shared_boot_slot_index: u32;
    extern var oc_i386_ap_slot_stage: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_started: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_halted: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_startup_count: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_reported_apic_id: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_target_apic_id: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_bsp_apic_id: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_local_apic_addr: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_command_kind: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_command_value: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_command_seq: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_response_seq: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_heartbeat: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_ping_count: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_work_count: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_last_work_value: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_work_accumulator: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_task_count: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_task_values: [max_ap_command_slots][max_task_batch_entries]u32;
    extern var oc_i386_ap_slot_batch_count: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_last_batch_count: [max_ap_command_slots]u32;
    extern var oc_i386_ap_slot_last_batch_accumulator: [max_ap_command_slots]u32;
};

fn sharedBootSlotIndexPtr() *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_shared_boot_slot_index else &SharedStorage.boot_slot_index;
}

fn slotStagePtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_stage[slot_index] else &SharedStorage.stage[slot_index];
}

fn slotStartedPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_started[slot_index] else &SharedStorage.started[slot_index];
}

fn slotHaltedPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_halted[slot_index] else &SharedStorage.halted[slot_index];
}

fn slotStartupCountPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_startup_count[slot_index] else &SharedStorage.startup_count[slot_index];
}

fn slotReportedApicIdPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_reported_apic_id[slot_index] else &SharedStorage.reported_apic_id[slot_index];
}

fn slotTargetApicIdPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_target_apic_id[slot_index] else &SharedStorage.target_apic_id[slot_index];
}

fn slotBspApicIdPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_bsp_apic_id[slot_index] else &SharedStorage.bsp_apic_id[slot_index];
}

fn slotLocalApicAddrPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_local_apic_addr[slot_index] else &SharedStorage.local_apic_addr[slot_index];
}

fn slotCommandKindPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_command_kind[slot_index] else &SharedStorage.command_kind[slot_index];
}

fn slotCommandValuePtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_command_value[slot_index] else &SharedStorage.command_value[slot_index];
}

fn slotCommandSeqPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_command_seq[slot_index] else &SharedStorage.command_seq[slot_index];
}

fn slotResponseSeqPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_response_seq[slot_index] else &SharedStorage.response_seq[slot_index];
}

fn slotHeartbeatPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_heartbeat[slot_index] else &SharedStorage.heartbeat[slot_index];
}

fn slotPingCountPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_ping_count[slot_index] else &SharedStorage.ping_count[slot_index];
}

fn slotWorkCountPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_work_count[slot_index] else &SharedStorage.work_count[slot_index];
}

fn slotLastWorkValuePtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_last_work_value[slot_index] else &SharedStorage.last_work_value[slot_index];
}

fn slotWorkAccumulatorPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_work_accumulator[slot_index] else &SharedStorage.work_accumulator[slot_index];
}

fn slotTaskCountPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_task_count[slot_index] else &SharedStorage.task_count[slot_index];
}

fn slotTaskValuePtr(slot_index: usize, index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_task_values[slot_index][index] else &SharedStorage.task_values[slot_index][index];
}

fn slotBatchCountPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_batch_count[slot_index] else &SharedStorage.batch_count[slot_index];
}

fn slotLastBatchCountPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_last_batch_count[slot_index] else &SharedStorage.last_batch_count[slot_index];
}

fn slotLastBatchAccumulatorPtr(slot_index: usize) *u32 {
    return if (comptime use_extern_shared) &SharedExtern.oc_i386_ap_slot_last_batch_accumulator[slot_index] else &SharedStorage.last_batch_accumulator[slot_index];
}

fn sharedStagePtr() *u32 {
    return slotStagePtr(0);
}

fn sharedStartedPtr() *u32 {
    return slotStartedPtr(0);
}

fn sharedHaltedPtr() *u32 {
    return slotHaltedPtr(0);
}

fn sharedStartupCountPtr() *u32 {
    return slotStartupCountPtr(0);
}

fn sharedReportedApicIdPtr() *u32 {
    return slotReportedApicIdPtr(0);
}

fn sharedTargetApicIdPtr() *u32 {
    return slotTargetApicIdPtr(0);
}

fn sharedBspApicIdPtr() *u32 {
    return slotBspApicIdPtr(0);
}

fn sharedLocalApicAddrPtr() *u32 {
    return slotLocalApicAddrPtr(0);
}

fn sharedCommandKindPtr() *u32 {
    return slotCommandKindPtr(0);
}

fn sharedCommandValuePtr() *u32 {
    return slotCommandValuePtr(0);
}

fn sharedCommandSeqPtr() *u32 {
    return slotCommandSeqPtr(0);
}

fn sharedResponseSeqPtr() *u32 {
    return slotResponseSeqPtr(0);
}

fn sharedHeartbeatPtr() *u32 {
    return slotHeartbeatPtr(0);
}

fn sharedPingCountPtr() *u32 {
    return slotPingCountPtr(0);
}

fn sharedWorkCountPtr() *u32 {
    return slotWorkCountPtr(0);
}

fn sharedLastWorkValuePtr() *u32 {
    return slotLastWorkValuePtr(0);
}

fn sharedWorkAccumulatorPtr() *u32 {
    return slotWorkAccumulatorPtr(0);
}

fn sharedTaskCountPtr() *u32 {
    return slotTaskCountPtr(0);
}

fn sharedTaskValuePtr(index: usize) *u32 {
    return slotTaskValuePtr(0, index);
}

fn sharedBatchCountPtr() *u32 {
    return slotBatchCountPtr(0);
}

fn sharedLastBatchCountPtr() *u32 {
    return slotLastBatchCountPtr(0);
}

fn sharedLastBatchAccumulatorPtr() *u32 {
    return slotLastBatchAccumulatorPtr(0);
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
        .command_value = 0,
        .task_count = 0,
        .work_count = 0,
        .last_work_value = 0,
        .work_accumulator = 0,
        .batch_count = 0,
        .last_batch_count = 0,
        .last_batch_accumulator = 0,
    };
}

fn zeroMultiState() abi.BaremetalApMultiState {
    return .{
        .magic = abi.ap_multi_magic,
        .api_version = abi.api_version,
        .present = 0,
        .exported_count = 0,
        .run_count = 0,
        .started_count = 0,
        .halted_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .last_target_apic_id = 0,
        .last_reported_apic_id = 0,
        .total_task_count = 0,
        .total_batch_count = 0,
        .total_accumulator = 0,
    };
}

fn zeroSlotState() abi.BaremetalApSlotState {
    return .{
        .magic = abi.ap_slot_magic,
        .api_version = abi.api_version,
        .present = 0,
        .exported_count = 0,
        .active_count = 0,
        .started_count = 0,
        .halted_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .total_task_count = 0,
        .total_batch_count = 0,
        .total_accumulator = 0,
    };
}

fn resetSingleState() void {
    state = zeroState();
    diagnostics = .{};
    writeStateVar(sharedBootSlotIndexPtr(), 0);
    writeStateVar(sharedStagePtr(), 0);
    writeStateVar(sharedStartedPtr(), 0);
    writeStateVar(sharedHaltedPtr(), 0);
    writeStateVar(sharedStartupCountPtr(), 0);
    writeStateVar(sharedReportedApicIdPtr(), 0);
    writeStateVar(sharedTargetApicIdPtr(), 0);
    writeStateVar(sharedBspApicIdPtr(), 0);
    writeStateVar(sharedLocalApicAddrPtr(), 0);
    writeStateVar(sharedCommandKindPtr(), 0);
    writeStateVar(sharedCommandValuePtr(), 0);
    writeStateVar(sharedCommandSeqPtr(), 0);
    writeStateVar(sharedResponseSeqPtr(), 0);
    writeStateVar(sharedHeartbeatPtr(), 0);
    writeStateVar(sharedPingCountPtr(), 0);
    writeStateVar(sharedWorkCountPtr(), 0);
    writeStateVar(sharedLastWorkValuePtr(), 0);
    writeStateVar(sharedWorkAccumulatorPtr(), 0);
    writeStateVar(sharedTaskCountPtr(), 0);
    for (0..max_task_batch_entries) |index| writeStateVar(sharedTaskValuePtr(index), 0);
    writeStateVar(sharedBatchCountPtr(), 0);
    writeStateVar(sharedLastBatchCountPtr(), 0);
    writeStateVar(sharedLastBatchAccumulatorPtr(), 0);
}

fn resetSlotEntry(slot_index: usize) void {
    writeStateVar(slotStagePtr(slot_index), 0);
    writeStateVar(slotStartedPtr(slot_index), 0);
    writeStateVar(slotHaltedPtr(slot_index), 0);
    writeStateVar(slotStartupCountPtr(slot_index), 0);
    writeStateVar(slotReportedApicIdPtr(slot_index), 0);
    writeStateVar(slotTargetApicIdPtr(slot_index), 0);
    writeStateVar(slotBspApicIdPtr(slot_index), 0);
    writeStateVar(slotLocalApicAddrPtr(slot_index), 0);
    writeStateVar(slotCommandKindPtr(slot_index), 0);
    writeStateVar(slotCommandValuePtr(slot_index), 0);
    writeStateVar(slotCommandSeqPtr(slot_index), 0);
    writeStateVar(slotResponseSeqPtr(slot_index), 0);
    writeStateVar(slotHeartbeatPtr(slot_index), 0);
    writeStateVar(slotPingCountPtr(slot_index), 0);
    writeStateVar(slotWorkCountPtr(slot_index), 0);
    writeStateVar(slotLastWorkValuePtr(slot_index), 0);
    writeStateVar(slotWorkAccumulatorPtr(slot_index), 0);
    writeStateVar(slotTaskCountPtr(slot_index), 0);
    for (0..max_task_batch_entries) |index| writeStateVar(slotTaskValuePtr(slot_index, index), 0);
    writeStateVar(slotBatchCountPtr(slot_index), 0);
    writeStateVar(slotLastBatchCountPtr(slot_index), 0);
    writeStateVar(slotLastBatchAccumulatorPtr(slot_index), 0);
}

pub fn resetMultiState() void {
    multi_state = zeroMultiState();
    @memset(&multi_entries, std.mem.zeroes(abi.BaremetalApMultiEntry));
}

pub fn resetSlotState() void {
    slot_state = zeroSlotState();
    @memset(&slot_entries, std.mem.zeroes(abi.BaremetalApSlotEntry));
    writeStateVar(sharedBootSlotIndexPtr(), 0);
    for (0..max_ap_command_slots) |slot_index| resetSlotEntry(slot_index);
}

pub fn resetForTest() void {
    resetSingleState();
    resetMultiState();
    resetSlotState();
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

pub fn multiStatePtr() *const abi.BaremetalApMultiState {
    refreshState();
    return &multi_state;
}

pub fn multiEntryCount() u16 {
    refreshState();
    return multi_state.exported_count;
}

pub fn multiEntry(index: u16) abi.BaremetalApMultiEntry {
    refreshState();
    if (index >= multi_state.exported_count) return std.mem.zeroes(abi.BaremetalApMultiEntry);
    return multi_entries[index];
}

pub fn slotStatePtr() *const abi.BaremetalApSlotState {
    refreshState();
    return &slot_state;
}

pub fn slotEntryCount() u16 {
    refreshState();
    return slot_state.exported_count;
}

pub fn slotEntry(index: u16) abi.BaremetalApSlotEntry {
    refreshState();
    if (index >= slot_state.exported_count) return std.mem.zeroes(abi.BaremetalApSlotEntry);
    return slot_entries[index];
}

pub fn startupSingleAp() Error!void {
    if (builtin.os.tag != .freestanding or builtin.cpu.arch != .x86) return error.UnsupportedPlatform;
    const lapic_state = lapic.statePtr().*;
    const target_apic_id = findSecondaryApicId(lapic_state.current_apic_id) orelse return error.NoSecondaryCpu;
    return startupApByApicId(target_apic_id);
}

pub fn startupApByApicId(target_apic_id: u32) Error!void {
    resetSingleState();
    resetSlotEntry(0);
    return startupApInSlot(target_apic_id, 0);
}

pub fn startupApInSlot(target_apic_id: u32, slot_index: u16) Error!void {
    if (builtin.os.tag != .freestanding or builtin.cpu.arch != .x86) return error.UnsupportedPlatform;
    const slot_usize: usize = slot_index;
    if (slot_usize >= max_ap_command_slots) return error.NoSecondaryCpu;

    const topology = acpi.cpuTopologyStatePtr().*;
    const lapic_state = lapic.statePtr().*;
    if (topology.present == 0 or topology.supports_smp == 0 or topology.enabled_count < 2) return error.CpuTopologyMissing;
    if (lapic_state.present == 0 or lapic_state.enabled == 0 or lapic_state.local_apic_addr == 0) return error.LapicUnavailable;
    if (!topologyContainsTargetApicId(target_apic_id, lapic_state.current_apic_id)) return error.NoSecondaryCpu;

    const lapic_addr_u32 = @as(u32, @intCast(lapic_state.local_apic_addr & 0xFFFF_FFFF));
    resetSlotEntry(slot_usize);
    writeStateVar(sharedBootSlotIndexPtr(), slot_index);
    writeStateVar(slotBspApicIdPtr(slot_usize), lapic_state.current_apic_id);
    writeStateVar(slotTargetApicIdPtr(slot_usize), target_apic_id);
    writeStateVar(slotLocalApicAddrPtr(slot_usize), lapic_addr_u32);
    programWarmResetVector(trampoline_phys);
    defer clearWarmResetVector();
    refreshState();

    const regs = lapicRegs(lapic_addr_u32);
    writeStateVar(slotStagePtr(slot_usize), 0x10);
    diagnostics.init_ipi_count += 1;
    enableLocalApic(regs);
    sendInitIpi(regs, target_apic_id) catch return error.DeliveryTimeout;
    writeStateVar(slotStagePtr(slot_usize), 0x11);
    spinDelay(init_settle_delay_iterations);
    diagnostics.init_ipi_count += 1;
    sendInitDeassertIpi(regs, target_apic_id) catch return error.DeliveryTimeout;
    writeStateVar(slotStagePtr(slot_usize), 0x12);
    spinDelay(startup_retry_delay_iterations);
    clearErrorStatus(regs);
    diagnostics.startup_ipi_count += 1;
    sendStartupIpi(regs, target_apic_id, startup_vector) catch return error.DeliveryTimeout;
    diagnostics.last_accept_status = readAcceptStatus(regs);
    writeStateVar(slotStagePtr(slot_usize), 0x13);
    if (waitForStartedTarget(slot_usize, first_startup_timeout_iterations)) return;

    spinDelay(startup_retry_delay_iterations);
    clearErrorStatus(regs);
    diagnostics.startup_ipi_count += 1;
    sendStartupIpi(regs, target_apic_id, startup_vector) catch return error.DeliveryTimeout;
    diagnostics.last_accept_status = readAcceptStatus(regs);
    writeStateVar(slotStagePtr(slot_usize), 0x14);

    if (waitForStartedTarget(slot_usize, startup_timeout_iterations)) return;
    if (readStateVar(slotStartedPtr(slot_usize)) == 0) return error.StartupTimeout;
    if (readStateVar(slotReportedApicIdPtr(slot_usize)) != readStateVar(slotTargetApicIdPtr(slot_usize))) return error.WrongCpuStarted;
    return error.StartupTimeout;
}

fn waitForStartedTarget(slot_index: usize, iterations: usize) bool {
    var remaining = iterations;
    while (remaining > 0) : (remaining -= 1) {
        if (readStateVar(slotStartedPtr(slot_index)) == 1 and
            readStateVar(slotReportedApicIdPtr(slot_index)) == readStateVar(slotTargetApicIdPtr(slot_index)) and
            readStateVar(slotStagePtr(slot_index)) >= 4 and
            readStateVar(slotHeartbeatPtr(slot_index)) != 0)
        {
            return true;
        }
        std.atomic.spinLoopHint();
    }
    return false;
}

pub fn pingStartedAp() Error!void {
    try pingApSlot(0);
}

pub fn dispatchWorkToStartedAp(value: u32) Error!u32 {
    return dispatchWorkToApSlot(0, value);
}

fn batchAccumulator(values: []const u32) u32 {
    var accumulator: u32 = 0;
    for (values) |value| accumulator +%= value;
    return accumulator;
}

pub fn dispatchWorkBatchToStartedAp(values: []const u32) Error!u32 {
    return dispatchWorkBatchToApSlot(0, values);
}

pub fn haltStartedAp() Error!void {
    try haltApSlot(0);
}

pub fn pingApSlot(slot_index: u16) Error!void {
    const slot_usize: usize = slot_index;
    if (slot_usize >= max_ap_command_slots) return error.NoSecondaryCpu;
    if (readStateVar(slotStartedPtr(slot_usize)) == 0 or readStateVar(slotHaltedPtr(slot_usize)) == 1) return error.ApNotStarted;
    try issueSlotCommand(slot_usize, ap_command_ping);
    if (readStateVar(slotPingCountPtr(slot_usize)) == 0 or readStateVar(slotStagePtr(slot_usize)) != 5) return error.CommandTimeout;
}

pub fn dispatchWorkToApSlot(slot_index: u16, value: u32) Error!u32 {
    const slot_usize: usize = slot_index;
    if (slot_usize >= max_ap_command_slots) return error.NoSecondaryCpu;
    if (readStateVar(slotStartedPtr(slot_usize)) == 0 or readStateVar(slotHaltedPtr(slot_usize)) == 1) return error.ApNotStarted;
    const prior_count = readStateVar(slotWorkCountPtr(slot_usize));
    const expected_accumulator = readStateVar(slotWorkAccumulatorPtr(slot_usize)) + value;
    try issueSlotCommandWithValue(slot_usize, ap_command_work, value);
    if (readStateVar(slotWorkCountPtr(slot_usize)) != prior_count + 1 or
        readStateVar(slotLastWorkValuePtr(slot_usize)) != value or
        readStateVar(slotWorkAccumulatorPtr(slot_usize)) != expected_accumulator or
        readStateVar(slotStagePtr(slot_usize)) != 7)
    {
        return error.CommandTimeout;
    }
    return readStateVar(slotWorkAccumulatorPtr(slot_usize));
}

fn stageTaskBatchForSlot(slot_index: usize, values: []const u32) void {
    writeStateVar(slotTaskCountPtr(slot_index), @as(u32, @intCast(values.len)));
    for (0..max_task_batch_entries) |index| {
        const value = if (index < values.len) values[index] else 0;
        writeStateVar(slotTaskValuePtr(slot_index, index), value);
    }
}

pub fn dispatchWorkBatchToApSlot(slot_index: u16, values: []const u32) Error!u32 {
    const slot_usize: usize = slot_index;
    if (slot_usize >= max_ap_command_slots) return error.NoSecondaryCpu;
    if (readStateVar(slotStartedPtr(slot_usize)) == 0 or readStateVar(slotHaltedPtr(slot_usize)) == 1) return error.ApNotStarted;
    if (values.len == 0 or values.len > max_task_batch_entries) return error.InvalidWorkBatch;

    const prior_batch_count = readStateVar(slotBatchCountPtr(slot_usize));
    const expected_accumulator = batchAccumulator(values);
    stageTaskBatchForSlot(slot_usize, values);
    writeStateVar(slotCommandValuePtr(slot_usize), @as(u32, @intCast(values.len)));
    try issueSlotCommandWithValue(slot_usize, ap_command_batch_work, @as(u32, @intCast(values.len)));
    if (readStateVar(slotBatchCountPtr(slot_usize)) != prior_batch_count + 1 or
        readStateVar(slotTaskCountPtr(slot_usize)) != values.len or
        readStateVar(slotLastBatchCountPtr(slot_usize)) != values.len or
        readStateVar(slotLastBatchAccumulatorPtr(slot_usize)) != expected_accumulator or
        readStateVar(slotStagePtr(slot_usize)) != 8)
    {
        return error.CommandTimeout;
    }
    for (values, 0..) |value, index| {
        if (readStateVar(slotTaskValuePtr(slot_usize, index)) != value) return error.CommandTimeout;
    }
    return readStateVar(slotLastBatchAccumulatorPtr(slot_usize));
}

pub fn haltApSlot(slot_index: u16) Error!void {
    const slot_usize: usize = slot_index;
    if (slot_usize >= max_ap_command_slots) return error.NoSecondaryCpu;
    if (readStateVar(slotStartedPtr(slot_usize)) == 0 or readStateVar(slotHaltedPtr(slot_usize)) == 1) return error.ApNotStarted;
    try issueSlotCommand(slot_usize, ap_command_halt);
    var remaining = command_timeout_iterations;
    while (remaining > 0) : (remaining -= 1) {
        if (readStateVar(slotHaltedPtr(slot_usize)) == 1 and readStateVar(slotStagePtr(slot_usize)) == 6) return;
        std.atomic.spinLoopHint();
    }
    return error.CommandTimeout;
}

pub fn renderAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [1536]u8 = undefined;
    var used: usize = 0;

    const head = std.fmt.bufPrint(
        buffer[used..],
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
    ) catch unreachable;
    used += head.len;

    const mid = std.fmt.bufPrint(
        buffer[used..],
        "command_seq={d}\nresponse_seq={d}\nheartbeat_count={d}\nping_count={d}\nwarm_reset_programmed={d}\nwarm_reset_vector_segment=0x{x}\nwarm_reset_vector_offset=0x{x}\ninit_ipi_count={d}\nstartup_ipi_count={d}\nlast_delivery_status=0x{x}\nlast_accept_status=0x{x}\n",
        .{
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
    ) catch unreachable;
    used += mid.len;

    const tail = std.fmt.bufPrint(
        buffer[used..],
        "command_value={d}\ntask_count={d}\nwork_count={d}\nlast_work_value={d}\nwork_accumulator={d}\nbatch_count={d}\nlast_batch_count={d}\nlast_batch_accumulator={d}\n",
        .{
            state.command_value,
            state.task_count,
            state.work_count,
            state.last_work_value,
            state.work_accumulator,
            state.batch_count,
            state.last_batch_count,
            state.last_batch_accumulator,
        },
    ) catch unreachable;
    used += tail.len;

    return allocator.dupe(u8, buffer[0..used]);
}

pub fn renderWorkAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    return std.fmt.allocPrint(
        allocator,
        "started={d}\nhalted={d}\nlast_stage={d}\ncommand_seq={d}\nresponse_seq={d}\ncommand_value={d}\ntask_count={d}\nwork_count={d}\nlast_work_value={d}\nwork_accumulator={d}\nbatch_count={d}\nlast_batch_count={d}\nlast_batch_accumulator={d}\nheartbeat_count={d}\nping_count={d}\n",
        .{
            state.started,
            state.halted,
            state.last_stage,
            state.command_seq,
            state.response_seq,
            state.command_value,
            state.task_count,
            state.work_count,
            state.last_work_value,
            state.work_accumulator,
            state.batch_count,
            state.last_batch_count,
            state.last_batch_accumulator,
            state.heartbeat_count,
            state.ping_count,
        },
    );
}

pub fn renderTasksAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [1024]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
        buffer[used..],
        "started={d}\nhalted={d}\nlast_stage={d}\ncommand_seq={d}\nresponse_seq={d}\ncommand_value={d}\ntask_count={d}\nbatch_count={d}\nlast_batch_count={d}\nlast_batch_accumulator={d}\n",
        .{
            state.started,
            state.halted,
            state.last_stage,
            state.command_seq,
            state.response_seq,
            state.command_value,
            state.task_count,
            state.batch_count,
            state.last_batch_count,
            state.last_batch_accumulator,
        },
    ) catch unreachable;
    used += head.len;
    const task_count = @min(@as(usize, @intCast(state.task_count)), max_task_batch_entries);
    for (0..task_count) |index| {
        const line = std.fmt.bufPrint(buffer[used..], "task[{d}]={d}\n", .{ index, readStateVar(sharedTaskValuePtr(index)) }) catch unreachable;
        used += line.len;
    }
    return allocator.dupe(u8, buffer[0..used]);
}

pub fn renderMultiAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [1536]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
        buffer[used..],
        "present={d}\nexported_count={d}\nrun_count={d}\nstarted_count={d}\nhalted_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\nlast_target_apic_id={d}\nlast_reported_apic_id={d}\ntotal_task_count={d}\ntotal_batch_count={d}\ntotal_accumulator={d}\n",
        .{
            multi_state.present,
            multi_state.exported_count,
            multi_state.run_count,
            multi_state.started_count,
            multi_state.halted_count,
            multi_state.requested_cpu_count,
            multi_state.logical_processor_count,
            multi_state.bsp_apic_id,
            multi_state.last_target_apic_id,
            multi_state.last_reported_apic_id,
            multi_state.total_task_count,
            multi_state.total_batch_count,
            multi_state.total_accumulator,
        },
    ) catch unreachable;
    used += head.len;
    var entry_index: u16 = 0;
    while (entry_index < multi_state.exported_count) : (entry_index += 1) {
        const entry = multi_entries[entry_index];
        const line = std.fmt.bufPrint(
            buffer[used..],
            "ap[{d}].target_apic_id={d}\nap[{d}].reported_apic_id={d}\nap[{d}].task_count={d}\nap[{d}].batch_count={d}\nap[{d}].last_batch_count={d}\nap[{d}].last_batch_accumulator={d}\nap[{d}].heartbeat_count={d}\nap[{d}].ping_count={d}\nap[{d}].started={d}\nap[{d}].halted={d}\nap[{d}].last_stage={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.reported_apic_id,
                entry_index, entry.task_count,
                entry_index, entry.batch_count,
                entry_index, entry.last_batch_count,
                entry_index, entry.last_batch_accumulator,
                entry_index, entry.heartbeat_count,
                entry_index, entry.ping_count,
                entry_index, entry.started,
                entry_index, entry.halted,
                entry_index, entry.last_stage,
            },
        ) catch unreachable;
        used += line.len;
    }
    return allocator.dupe(u8, buffer[0..used]);
}

pub fn renderSlotsAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [2048]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
        buffer[used..],
        "present={d}\nexported_count={d}\nactive_count={d}\nstarted_count={d}\nhalted_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_task_count={d}\ntotal_batch_count={d}\ntotal_accumulator={d}\n",
        .{
            slot_state.present,
            slot_state.exported_count,
            slot_state.active_count,
            slot_state.started_count,
            slot_state.halted_count,
            slot_state.requested_cpu_count,
            slot_state.logical_processor_count,
            slot_state.bsp_apic_id,
            slot_state.total_task_count,
            slot_state.total_batch_count,
            slot_state.total_accumulator,
        },
    ) catch unreachable;
    used += head.len;
    var entry_index: u16 = 0;
    while (entry_index < slot_state.exported_count) : (entry_index += 1) {
        const entry = slot_entries[entry_index];
        const line_a = std.fmt.bufPrint(
            buffer[used..],
            "slot[{d}].target_apic_id={d}\nslot[{d}].reported_apic_id={d}\nslot[{d}].command_seq={d}\nslot[{d}].response_seq={d}\nslot[{d}].heartbeat_count={d}\nslot[{d}].ping_count={d}\nslot[{d}].task_count={d}\nslot[{d}].batch_count={d}\nslot[{d}].last_batch_count={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.reported_apic_id,
                entry_index, entry.command_seq,
                entry_index, entry.response_seq,
                entry_index, entry.heartbeat_count,
                entry_index, entry.ping_count,
                entry_index, entry.task_count,
                entry_index, entry.batch_count,
                entry_index, entry.last_batch_count,
            },
        ) catch unreachable;
        used += line_a.len;
        const line_b = std.fmt.bufPrint(
            buffer[used..],
            "slot[{d}].last_batch_accumulator={d}\nslot[{d}].work_count={d}\nslot[{d}].last_work_value={d}\nslot[{d}].work_accumulator={d}\nslot[{d}].started={d}\nslot[{d}].halted={d}\nslot[{d}].last_stage={d}\nslot[{d}].slot_index={d}\n",
            .{
                entry_index, entry.last_batch_accumulator,
                entry_index, entry.work_count,
                entry_index, entry.last_work_value,
                entry_index, entry.work_accumulator,
                entry_index, entry.started,
                entry_index, entry.halted,
                entry_index, entry.last_stage,
                entry_index, entry.slot_index,
            },
        ) catch unreachable;
        used += line_b.len;
    }
    return allocator.dupe(u8, buffer[0..used]);
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
    state.command_value = readStateVar(sharedCommandValuePtr());
    state.command_seq = readStateVar(sharedCommandSeqPtr());
    state.response_seq = readStateVar(sharedResponseSeqPtr());
    state.heartbeat_count = readStateVar(sharedHeartbeatPtr());
    state.ping_count = readStateVar(sharedPingCountPtr());
    state.task_count = readStateVar(sharedTaskCountPtr());
    state.work_count = readStateVar(sharedWorkCountPtr());
    state.last_work_value = readStateVar(sharedLastWorkValuePtr());
    state.work_accumulator = readStateVar(sharedWorkAccumulatorPtr());
    state.batch_count = readStateVar(sharedBatchCountPtr());
    state.last_batch_count = readStateVar(sharedLastBatchCountPtr());
    state.last_batch_accumulator = readStateVar(sharedLastBatchAccumulatorPtr());
    state.warm_reset_programmed = diagnostics.warm_reset_programmed;
    state.warm_reset_vector_segment = diagnostics.warm_reset_vector_segment;
    state.warm_reset_vector_offset = diagnostics.warm_reset_vector_offset;
    state.init_ipi_count = diagnostics.init_ipi_count;
    state.startup_ipi_count = diagnostics.startup_ipi_count;
    state.last_delivery_status = diagnostics.last_delivery_status;
    state.last_accept_status = diagnostics.last_accept_status;
    multi_state.requested_cpu_count = topology.enabled_count;
    multi_state.logical_processor_count = lapic_state.logical_processor_count;
    multi_state.bsp_apic_id = lapic_state.current_apic_id;
    if (multi_state.run_count == 0 and multi_state.exported_count == 0) {
        multi_state.present = if (state.supported != 0) 1 else multi_state.present;
    }

    slot_state = zeroSlotState();
    slot_state.present = if (state.supported != 0) 1 else 0;
    slot_state.requested_cpu_count = topology.enabled_count;
    slot_state.logical_processor_count = lapic_state.logical_processor_count;
    slot_state.bsp_apic_id = lapic_state.current_apic_id;
    @memset(&slot_entries, std.mem.zeroes(abi.BaremetalApSlotEntry));
    var slot_index: usize = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const target_apic_id = readStateVar(slotTargetApicIdPtr(slot_index));
        const reported_apic_id = readStateVar(slotReportedApicIdPtr(slot_index));
        const started = if (readStateVar(slotStartedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const halted = if (readStateVar(slotHaltedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const last_stage = @as(u8, @truncate(readStateVar(slotStagePtr(slot_index))));
        const heartbeat_count = readStateVar(slotHeartbeatPtr(slot_index));
        if (target_apic_id == 0 and reported_apic_id == 0 and started == 0 and halted == 0 and last_stage == 0 and heartbeat_count == 0) continue;
        const exported_index = slot_state.exported_count;
        slot_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .reported_apic_id = reported_apic_id,
            .command_seq = readStateVar(slotCommandSeqPtr(slot_index)),
            .response_seq = readStateVar(slotResponseSeqPtr(slot_index)),
            .heartbeat_count = heartbeat_count,
            .ping_count = readStateVar(slotPingCountPtr(slot_index)),
            .task_count = readStateVar(slotTaskCountPtr(slot_index)),
            .batch_count = readStateVar(slotBatchCountPtr(slot_index)),
            .last_batch_count = readStateVar(slotLastBatchCountPtr(slot_index)),
            .last_batch_accumulator = readStateVar(slotLastBatchAccumulatorPtr(slot_index)),
            .work_count = readStateVar(slotWorkCountPtr(slot_index)),
            .last_work_value = readStateVar(slotLastWorkValuePtr(slot_index)),
            .work_accumulator = readStateVar(slotWorkAccumulatorPtr(slot_index)),
            .started = started,
            .halted = halted,
            .last_stage = last_stage,
            .slot_index = @as(u8, @intCast(slot_index)),
        };
        slot_state.exported_count += 1;
        if (started != 0) slot_state.started_count +%= 1;
        if (started != 0 and halted == 0) slot_state.active_count +%= 1;
        if (halted != 0) slot_state.halted_count +%= 1;
        slot_state.total_task_count +%= slot_entries[exported_index].task_count;
        slot_state.total_batch_count +%= slot_entries[exported_index].batch_count;
        slot_state.total_accumulator +%= slot_entries[exported_index].last_batch_accumulator;
    }
    if (slot_state.exported_count != 0) slot_state.present = 1;
}

fn findSecondaryApicId(current_apic_id: u32) ?u32 {
    return secondaryApicIdAt(0, current_apic_id);
}

pub fn secondaryApicIdAt(target_index: u16, current_apic_id: u32) ?u32 {
    var remaining = target_index;
    var entry_index: u16 = 0;
    while (entry_index < acpi.cpuTopologyEntryCount()) : (entry_index += 1) {
        const entry = acpi.cpuTopologyEntry(entry_index);
        if (entry.enabled == 0) continue;
        if (entry.apic_id == @as(u8, @truncate(current_apic_id))) continue;
        if (remaining == 0) return entry.apic_id;
        remaining -= 1;
    }
    return null;
}

fn topologyContainsTargetApicId(target_apic_id: u32, current_apic_id: u32) bool {
    var index: u16 = 0;
    while (index < acpi.cpuTopologyEntryCount()) : (index += 1) {
        const entry = acpi.cpuTopologyEntry(index);
        if (entry.enabled == 0) continue;
        if (entry.apic_id == @as(u8, @truncate(current_apic_id))) continue;
        if (entry.apic_id == @as(u8, @truncate(target_apic_id))) return true;
    }
    return false;
}

pub fn recordCurrentApRun() void {
    refreshState();
    const entry_index = @min(@as(usize, multi_state.run_count), max_multi_ap_entries - 1);
    multi_entries[entry_index] = .{
        .target_apic_id = state.target_apic_id,
        .reported_apic_id = state.reported_apic_id,
        .task_count = state.task_count,
        .batch_count = state.batch_count,
        .last_batch_count = state.last_batch_count,
        .last_batch_accumulator = state.last_batch_accumulator,
        .heartbeat_count = state.heartbeat_count,
        .ping_count = state.ping_count,
        .started = state.started,
        .halted = state.halted,
        .last_stage = state.last_stage,
        .reserved0 = 0,
    };
    multi_state.present = 1;
    if (multi_state.exported_count < max_multi_ap_entries and entry_index == multi_state.exported_count) {
        multi_state.exported_count += 1;
    }
    multi_state.run_count +%= 1;
    if (state.started != 0) multi_state.started_count +%= 1;
    if (state.halted != 0) multi_state.halted_count +%= 1;
    multi_state.requested_cpu_count = state.requested_cpu_count;
    multi_state.logical_processor_count = state.logical_processor_count;
    multi_state.bsp_apic_id = state.bsp_apic_id;
    multi_state.last_target_apic_id = state.target_apic_id;
    multi_state.last_reported_apic_id = state.reported_apic_id;
    multi_state.total_task_count +%= state.task_count;
    multi_state.total_batch_count +%= state.batch_count;
    multi_state.total_accumulator +%= state.last_batch_accumulator;
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
    return issueSlotCommand(0, command_kind);
}

fn issueCommandWithValue(command_kind: u32, command_value: u32) Error!void {
    return issueSlotCommandWithValue(0, command_kind, command_value);
}

fn issueSlotCommand(slot_index: usize, command_kind: u32) Error!void {
    return issueSlotCommandWithValue(slot_index, command_kind, 0);
}

fn issueSlotCommandWithValue(slot_index: usize, command_kind: u32, command_value: u32) Error!void {
    const next_seq = readStateVar(slotCommandSeqPtr(slot_index)) + 1;
    writeStateVar(slotCommandKindPtr(slot_index), command_kind);
    writeStateVar(slotCommandValuePtr(slot_index), command_value);
    writeStateVar(slotCommandSeqPtr(slot_index), next_seq);

    var remaining = command_timeout_iterations;
    while (remaining > 0) : (remaining -= 1) {
        if (readStateVar(slotResponseSeqPtr(slot_index)) == next_seq) return;
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
    testApSlotResponder(0);
}

fn testApSlotResponder(slot_index: usize) void {
    while (true) {
        const command_seq = readStateVar(slotCommandSeqPtr(slot_index));
        const response_seq = readStateVar(slotResponseSeqPtr(slot_index));
        if (command_seq != 0 and command_seq != response_seq) {
            const command_kind = readStateVar(slotCommandKindPtr(slot_index));
            if (command_kind == ap_command_ping) {
                writeStateVar(slotHeartbeatPtr(slot_index), readStateVar(slotHeartbeatPtr(slot_index)) + 1);
                writeStateVar(slotPingCountPtr(slot_index), readStateVar(slotPingCountPtr(slot_index)) + 1);
                writeStateVar(slotStagePtr(slot_index), 5);
                writeStateVar(slotResponseSeqPtr(slot_index), command_seq);
            } else if (command_kind == ap_command_halt) {
                writeStateVar(slotHeartbeatPtr(slot_index), readStateVar(slotHeartbeatPtr(slot_index)) + 1);
                writeStateVar(slotStagePtr(slot_index), 6);
                writeStateVar(slotHaltedPtr(slot_index), 1);
                writeStateVar(slotResponseSeqPtr(slot_index), command_seq);
                return;
            } else if (command_kind == ap_command_work) {
                const value = readStateVar(slotCommandValuePtr(slot_index));
                writeStateVar(slotLastWorkValuePtr(slot_index), value);
                writeStateVar(slotWorkAccumulatorPtr(slot_index), readStateVar(slotWorkAccumulatorPtr(slot_index)) + value);
                writeStateVar(slotWorkCountPtr(slot_index), readStateVar(slotWorkCountPtr(slot_index)) + 1);
                writeStateVar(slotHeartbeatPtr(slot_index), readStateVar(slotHeartbeatPtr(slot_index)) + 1);
                writeStateVar(slotStagePtr(slot_index), 7);
                writeStateVar(slotResponseSeqPtr(slot_index), command_seq);
            } else if (command_kind == ap_command_batch_work) {
                const task_count = @min(@as(usize, @intCast(readStateVar(slotTaskCountPtr(slot_index)))), max_task_batch_entries);
                var accumulator: u32 = 0;
                for (0..task_count) |index| accumulator +%= readStateVar(slotTaskValuePtr(slot_index, index));
                writeStateVar(slotLastBatchCountPtr(slot_index), @as(u32, @intCast(task_count)));
                writeStateVar(slotLastBatchAccumulatorPtr(slot_index), accumulator);
                writeStateVar(slotBatchCountPtr(slot_index), readStateVar(slotBatchCountPtr(slot_index)) + 1);
                writeStateVar(slotHeartbeatPtr(slot_index), readStateVar(slotHeartbeatPtr(slot_index)) + 1);
                writeStateVar(slotStagePtr(slot_index), 8);
                writeStateVar(slotResponseSeqPtr(slot_index), command_seq);
            } else {
                writeStateVar(slotResponseSeqPtr(slot_index), command_seq);
            }
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
    try std.testing.expect(std.mem.indexOf(u8, render, "task_count=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "batch_count=0") != null);
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

test "i386 ap startup dispatches bounded work telemetry" {
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

    const first_accumulator = try dispatchWorkToStartedAp(3);
    try std.testing.expectEqual(@as(u32, 3), first_accumulator);
    var snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u32, 1), snapshot.command_seq);
    try std.testing.expectEqual(@as(u32, 1), snapshot.response_seq);
    try std.testing.expectEqual(@as(u32, 1), snapshot.work_count);
    try std.testing.expectEqual(@as(u32, 3), snapshot.last_work_value);
    try std.testing.expectEqual(@as(u32, 3), snapshot.work_accumulator);
    try std.testing.expectEqual(@as(u8, 7), snapshot.last_stage);

    const second_accumulator = try dispatchWorkToStartedAp(7);
    try std.testing.expectEqual(@as(u32, 10), second_accumulator);
    snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u32, 2), snapshot.command_seq);
    try std.testing.expectEqual(@as(u32, 2), snapshot.response_seq);
    try std.testing.expectEqual(@as(u32, 2), snapshot.work_count);
    try std.testing.expectEqual(@as(u32, 7), snapshot.last_work_value);
    try std.testing.expectEqual(@as(u32, 10), snapshot.work_accumulator);
    try std.testing.expectEqual(@as(u8, 7), snapshot.last_stage);

    try haltStartedAp();
    snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.halted);
    try std.testing.expectEqual(@as(u8, 6), snapshot.last_stage);
}

test "i386 ap startup dispatches bounded work batch telemetry" {
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

    const accumulator = try dispatchWorkBatchToStartedAp(&.{ 3, 7, 11 });
    try std.testing.expectEqual(@as(u32, 21), accumulator);
    var snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u32, 1), snapshot.command_seq);
    try std.testing.expectEqual(@as(u32, 1), snapshot.response_seq);
    try std.testing.expectEqual(@as(u32, 3), snapshot.task_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.batch_count);
    try std.testing.expectEqual(@as(u32, 3), snapshot.last_batch_count);
    try std.testing.expectEqual(@as(u32, 21), snapshot.last_batch_accumulator);
    try std.testing.expectEqual(@as(u8, 8), snapshot.last_stage);

    const tasks_render = try renderTasksAlloc(std.testing.allocator);
    defer std.testing.allocator.free(tasks_render);
    try std.testing.expect(std.mem.indexOf(u8, tasks_render, "task_count=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, tasks_render, "batch_count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, tasks_render, "last_batch_accumulator=21") != null);
    try std.testing.expect(std.mem.indexOf(u8, tasks_render, "task[0]=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, tasks_render, "task[1]=7") != null);
    try std.testing.expect(std.mem.indexOf(u8, tasks_render, "task[2]=11") != null);

    try haltStartedAp();
    snapshot = statePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.halted);
    try std.testing.expectEqual(@as(u8, 6), snapshot.last_stage);
}

test "i386 ap startup records bounded multi-ap telemetry" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    writeStateVar(sharedBspApicIdPtr(), 0);
    writeStateVar(sharedTargetApicIdPtr(), 1);
    writeStateVar(sharedReportedApicIdPtr(), 1);
    writeStateVar(sharedStartedPtr(), 1);
    writeStateVar(sharedHaltedPtr(), 1);
    writeStateVar(sharedStagePtr(), 6);
    writeStateVar(sharedHeartbeatPtr(), 5);
    writeStateVar(sharedPingCountPtr(), 1);
    writeStateVar(sharedTaskCountPtr(), 2);
    writeStateVar(sharedBatchCountPtr(), 1);
    writeStateVar(sharedLastBatchCountPtr(), 2);
    writeStateVar(sharedLastBatchAccumulatorPtr(), 8);
    recordCurrentApRun();

    writeStateVar(sharedTargetApicIdPtr(), 2);
    writeStateVar(sharedReportedApicIdPtr(), 2);
    writeStateVar(sharedHeartbeatPtr(), 7);
    writeStateVar(sharedPingCountPtr(), 1);
    writeStateVar(sharedTaskCountPtr(), 3);
    writeStateVar(sharedBatchCountPtr(), 1);
    writeStateVar(sharedLastBatchCountPtr(), 3);
    writeStateVar(sharedLastBatchAccumulatorPtr(), 41);
    recordCurrentApRun();

    const multi_snapshot = multiStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), multi_snapshot.present);
    try std.testing.expectEqual(@as(u8, 2), multi_snapshot.exported_count);
    try std.testing.expectEqual(@as(u16, 2), multi_snapshot.run_count);
    try std.testing.expectEqual(@as(u16, 2), multi_snapshot.started_count);
    try std.testing.expectEqual(@as(u16, 2), multi_snapshot.halted_count);
    try std.testing.expectEqual(@as(u32, 5), multi_snapshot.total_task_count);
    try std.testing.expectEqual(@as(u32, 2), multi_snapshot.total_batch_count);
    try std.testing.expectEqual(@as(u32, 49), multi_snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 2), multi_snapshot.last_target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), multi_snapshot.last_reported_apic_id);

    const first_entry = multiEntry(0);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 8), first_entry.last_batch_accumulator);
    const second_entry = multiEntry(1);
    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 41), second_entry.last_batch_accumulator);

    const multi_render = try renderMultiAlloc(std.testing.allocator);
    defer std.testing.allocator.free(multi_render);
    try std.testing.expect(std.mem.indexOf(u8, multi_render, "run_count=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, multi_render, "total_accumulator=49") != null);
    try std.testing.expect(std.mem.indexOf(u8, multi_render, "ap[0].target_apic_id=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, multi_render, "ap[1].target_apic_id=2") != null);
}

test "i386 ap startup drives bounded concurrent slot telemetry" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    writeStateVar(slotStartedPtr(0), 1);
    writeStateVar(slotStagePtr(0), 4);
    writeStateVar(slotReportedApicIdPtr(0), 1);
    writeStateVar(slotTargetApicIdPtr(0), 1);
    writeStateVar(slotHeartbeatPtr(0), 1);

    writeStateVar(slotStartedPtr(1), 1);
    writeStateVar(slotStagePtr(1), 4);
    writeStateVar(slotReportedApicIdPtr(1), 2);
    writeStateVar(slotTargetApicIdPtr(1), 2);
    writeStateVar(slotHeartbeatPtr(1), 1);

    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    errdefer {
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    const first_accumulator = try dispatchWorkBatchToApSlot(0, &.{ 3, 5 });
    try std.testing.expectEqual(@as(u32, 8), first_accumulator);
    const second_accumulator = try dispatchWorkBatchToApSlot(1, &.{ 11, 13, 17 });
    try std.testing.expectEqual(@as(u32, 41), second_accumulator);

    try pingApSlot(0);
    try pingApSlot(1);

    var snapshot = slotStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, 2), snapshot.exported_count);
    try std.testing.expectEqual(@as(u16, 2), snapshot.active_count);
    try std.testing.expectEqual(@as(u16, 2), snapshot.started_count);
    try std.testing.expectEqual(@as(u16, 0), snapshot.halted_count);
    try std.testing.expectEqual(@as(u32, 5), snapshot.total_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.total_batch_count);
    try std.testing.expectEqual(@as(u32, 49), snapshot.total_accumulator);

    const first_entry = slotEntry(0);
    const second_entry = slotEntry(1);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 8), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u8, 0), first_entry.halted);
    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 41), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u8, 0), second_entry.halted);

    const slots_render = try renderSlotsAlloc(std.testing.allocator);
    defer std.testing.allocator.free(slots_render);
    try std.testing.expect(std.mem.indexOf(u8, slots_render, "active_count=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, slots_render, "slot[0].target_apic_id=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, slots_render, "slot[1].target_apic_id=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, slots_render, "slot[0].last_batch_accumulator=8") != null);
    try std.testing.expect(std.mem.indexOf(u8, slots_render, "slot[1].last_batch_accumulator=41") != null);

    try haltApSlot(0);
    try haltApSlot(1);
    snapshot = slotStatePtr().*;
    try std.testing.expectEqual(@as(u16, 0), snapshot.active_count);
    try std.testing.expectEqual(@as(u16, 2), snapshot.halted_count);
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
