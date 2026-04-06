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

        .exported_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .total_owned_task_count = 0,
        .total_dispatch_count = 0,
        .total_accumulator = 0,
        .dispatch_round_count = 0,
        .last_round_owned_task_count = 0,
        .last_round_dispatch_count = 0,
        .last_round_accumulator = 0,
        .total_redistributed_task_count = 0,
        .last_redistributed_task_count = 0,
        .last_start_slot_index = 0,
    };
}

fn zeroFailoverState() abi.BaremetalApFailoverState {
    return .{
        .magic = abi.ap_failover_magic,
        .api_version = abi.api_version,
        .present = 0,
        .exported_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .total_owned_task_count = 0,
        .total_dispatch_count = 0,
        .total_accumulator = 0,
        .dispatch_round_count = 0,
        .total_redistributed_task_count = 0,
        .last_redistributed_task_count = 0,
        .total_backfilled_task_count = 0,
        .last_backfilled_task_count = 0,
        .total_terminated_task_count = 0,
        .last_terminated_task_count = 0,
        .total_backfill_round_count = 0,
        .last_start_slot_index = 0,
    };
}

fn zeroWindowState() abi.BaremetalApWindowState {
    return .{
        .magic = abi.ap_window_magic,
        .api_version = abi.api_version,
        .present = 0,
        .exported_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .total_window_task_count = 0,
        .total_dispatch_count = 0,
        .total_accumulator = 0,
        .dispatch_round_count = 0,
        .last_round_window_task_count = 0,
        .total_deferred_task_count = 0,
        .last_deferred_task_count = 0,
        .window_task_budget = 0,
        .task_cursor = 0,
        .wrap_count = 0,
        .last_start_slot_index = 0,
    };
}

fn zeroFairnessState() abi.BaremetalApFairnessState {
    return .{
        .magic = abi.ap_fairness_magic,
        .api_version = abi.api_version,
        .present = 0,
        .exported_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .total_drained_task_count = 0,
        .total_dispatch_count = 0,
        .total_accumulator = 0,
        .drain_round_count = 0,
        .last_round_drained_task_count = 0,
        .initial_pending_task_count = 0,
        .last_pending_task_count = 0,
        .peak_pending_task_count = 0,
        .drain_task_budget = 0,
        .final_task_cursor = 0,
        .wrap_count = 0,
        .last_start_slot_index = 0,
        .min_slot_task_count = 0,
        .max_slot_task_count = 0,
        .exported_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .exported_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .total_debt_task_count = 0,
        .total_dispatch_count = 0,
        .total_accumulator = 0,
        .drain_round_count = 0,
        .last_round_debt_task_count = 0,
        .initial_pending_task_count = 0,
        .last_pending_task_count = 0,
        .peak_pending_task_count = 0,
        .debt_task_budget = 0,
        .initial_min_slot_task_count = 0,
        .initial_max_slot_task_count = 0,
        .exported_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .total_admitted_task_count = 0,
        .total_debt_task_count = 0,
        .total_dispatch_count = 0,
        .total_accumulator = 0,
        .drain_round_count = 0,
        .last_round_admitted_task_count = 0,
        .last_round_debt_task_count = 0,
        .initial_pending_task_count = 0,
        .last_pending_task_count = 0,
        .peak_pending_task_count = 0,
        .task_budget = 0,
        .initial_min_slot_task_count = 0,
        .initial_max_slot_task_count = 0,
        .exported_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .total_waiting_task_count = 0,
        .total_debt_task_count = 0,
        .total_dispatch_count = 0,
        .total_accumulator = 0,
        .drain_round_count = 0,
        .aging_round_count = 0,
        .last_round_waiting_task_count = 0,
        .last_round_debt_task_count = 0,
        .initial_pending_task_count = 0,
        .last_pending_task_count = 0,
        .peak_pending_task_count = 0,
        .task_budget = 0,
        .aging_step = 0,
        .initial_min_slot_task_count = 0,
        .initial_max_slot_task_count = 0,
        .exported_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .total_waiting_task_count = 0,
        .total_debt_task_count = 0,
        .total_dispatch_count = 0,
        .total_accumulator = 0,
        .drain_round_count = 0,
        .aging_round_count = 0,
        .fairshare_round_count = 0,
        .last_round_waiting_task_count = 0,
        .last_round_debt_task_count = 0,
        .last_round_fairshare_task_count = 0,
        .initial_pending_task_count = 0,
        .last_pending_task_count = 0,
        .peak_pending_task_count = 0,
        .task_budget = 0,
        .aging_step = 0,
        .initial_min_slot_task_count = 0,
        .initial_max_slot_task_count = 0,
        .exported_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
        .total_waiting_task_count = 0,
        .total_debt_task_count = 0,
        .total_dispatch_count = 0,
        .total_accumulator = 0,
        .drain_round_count = 0,
        .aging_round_count = 0,
        .quota_round_count = 0,
        .last_round_waiting_task_count = 0,
        .last_round_debt_task_count = 0,
        .last_round_quota_task_count = 0,
        .initial_pending_task_count = 0,
        .last_pending_task_count = 0,
        .peak_pending_task_count = 0,
        .task_budget = 0,
        .aging_step = 0,
        .quota_budget_total = 0,
        .initial_min_slot_task_count = 0,
        .initial_max_slot_task_count = 0,
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

    return backfill_state.exported_count;
}

pub fn backfillEntry(index: u16) abi.BaremetalApBackfillEntry {
    refreshState();
    if (index >= backfill_state.exported_count) return std.mem.zeroes(abi.BaremetalApBackfillEntry);
    return backfill_entries[index];
}

pub fn windowEntryCount() u16 {
    refreshState();
    return window_state.exported_count;
}

pub fn windowEntry(index: u16) abi.BaremetalApWindowEntry {
    refreshState();
    if (index >= window_state.exported_count) return std.mem.zeroes(abi.BaremetalApWindowEntry);
    return window_entries[index];
}

pub fn fairnessStatePtr() *const abi.BaremetalApFairnessState {
    refreshState();
    return &fairness_state;
}

pub fn fairnessEntryCount() u16 {
    refreshState();
    return fairness_state.exported_count;
}

pub fn fairnessEntry(index: u16) abi.BaremetalApFairnessEntry {
    refreshState();
    if (index >= fairness_state.exported_count) return std.mem.zeroes(abi.BaremetalApFairnessEntry);
    return fairness_entries[index];
}

    return debt_state.exported_count;
}

pub fn debtEntry(index: u16) abi.BaremetalApDebtEntry {
    refreshState();
    if (index >= debt_state.exported_count) return std.mem.zeroes(abi.BaremetalApDebtEntry);
    return debt_entries[index];
}

pub fn admissionStatePtr() *const abi.BaremetalApAdmissionState {
    refreshState();
    return &admission_state;
}

pub fn admissionEntryCount() u16 {
    refreshState();
    return admission_state.exported_count;
}

pub fn admissionEntry(index: u16) abi.BaremetalApAdmissionEntry {
    refreshState();
    if (index >= admission_state.exported_count) return std.mem.zeroes(abi.BaremetalApAdmissionEntry);
    return admission_entries[index];
}

pub fn agingStatePtr() *const abi.BaremetalApAgingState {
    refreshState();
    return &aging_state;
}

pub fn agingEntryCount() u16 {
    refreshState();
    return aging_state.exported_count;
}

pub fn agingEntry(index: u16) abi.BaremetalApAgingEntry {
    refreshState();
    if (index >= aging_state.exported_count) return std.mem.zeroes(abi.BaremetalApAgingEntry);
    return aging_entries[index];
}

pub fn fairshareStatePtr() *const abi.BaremetalApFairshareState {
    refreshState();
    return &fairshare_state;
}

pub fn fairshareEntryCount() u16 {
    refreshState();
    return fairshare_state.exported_count;
}

pub fn fairshareEntry(index: u16) abi.BaremetalApFairshareEntry {
    refreshState();
    if (index >= fairshare_state.exported_count) return std.mem.zeroes(abi.BaremetalApFairshareEntry);
    return fairshare_entries[index];
}

pub fn quotaStatePtr() *const abi.BaremetalApQuotaState {
    refreshState();
    return &quota_state;
}

pub fn quotaEntryCount() u16 {
    refreshState();
    return quota_state.exported_count;
}

pub fn quotaEntry(index: u16) abi.BaremetalApQuotaEntry {
    refreshState();
    if (index >= quota_state.exported_count) return std.mem.zeroes(abi.BaremetalApQuotaEntry);
    return quota_entries[index];
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

        "present={d}\npolicy={d}\nexported_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_owned_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndispatch_round_count={d}\n",
        .{
        "present={d}\npolicy={d}\nexported_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nlast_round_active_slot_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_owned_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndispatch_round_count={d}\ntotal_redistributed_task_count={d}\nlast_redistributed_task_count={d}\n",
        .{
            backfill_state.present,
            backfill_state.policy,
            backfill_state.exported_count,
            backfill_state.active_count,
            backfill_state.peak_active_slot_count,
            backfill_state.last_round_active_slot_count,
            backfill_state.requested_cpu_count,
            backfill_state.logical_processor_count,
            backfill_state.bsp_apic_id,
            backfill_state.total_owned_task_count,
            backfill_state.total_dispatch_count,
            backfill_state.total_accumulator,
            backfill_state.dispatch_round_count,
            backfill_state.total_redistributed_task_count,
            backfill_state.last_redistributed_task_count,
        },
    ) catch unreachable;
    used += head.len;
    const tail = std.fmt.bufPrint(
        buffer[used..],
        "total_backfilled_task_count={d}\nlast_backfilled_task_count={d}\ntotal_terminated_task_count={d}\nlast_terminated_task_count={d}\ntotal_backfill_round_count={d}\nlast_start_slot_index={d}\n",
        .{
            backfill_state.total_backfilled_task_count,
            backfill_state.last_backfilled_task_count,
            backfill_state.total_terminated_task_count,
            backfill_state.last_terminated_task_count,
            backfill_state.total_backfill_round_count,
            backfill_state.last_start_slot_index,
        },
    ) catch unreachable;
    used += tail.len;
    var entry_index: u16 = 0;
    while (entry_index < backfill_state.exported_count) : (entry_index += 1) {
        const entry = backfill_entries[entry_index];
        const line = std.fmt.bufPrint(
            buffer[used..],
        "present={d}\npolicy={d}\nexported_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nlast_round_active_slot_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_window_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndispatch_round_count={d}\n",
        .{
            window_state.present,
            window_state.policy,
            window_state.exported_count,
            window_state.active_count,
            window_state.peak_active_slot_count,
            window_state.last_round_active_slot_count,
            window_state.requested_cpu_count,
            window_state.logical_processor_count,
            window_state.bsp_apic_id,
            window_state.total_window_task_count,
            window_state.total_dispatch_count,
            window_state.total_accumulator,
            window_state.dispatch_round_count,
        },
    ) catch unreachable;
    used += head.len;
    const tail = std.fmt.bufPrint(
        buffer[used..],
        "last_round_window_task_count={d}\ntotal_deferred_task_count={d}\nlast_deferred_task_count={d}\nwindow_task_budget={d}\ntask_cursor={d}\nwrap_count={d}\nlast_start_slot_index={d}\n",
        .{
            window_state.last_round_window_task_count,
            window_state.total_deferred_task_count,
            window_state.last_deferred_task_count,
            window_state.window_task_budget,
            window_state.task_cursor,
            window_state.wrap_count,
            window_state.last_start_slot_index,
        },
    ) catch unreachable;
    used += tail.len;
    var entry_index: u16 = 0;
    while (entry_index < window_state.exported_count) : (entry_index += 1) {
        const entry = window_entries[entry_index];
        const line = std.fmt.bufPrint(
            buffer[used..],
        "present={d}\npolicy={d}\nexported_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nlast_round_active_slot_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_drained_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndrain_round_count={d}\n",
        .{
            fairness_state.present,
            fairness_state.policy,
            fairness_state.exported_count,
            fairness_state.active_count,
            fairness_state.peak_active_slot_count,
            fairness_state.last_round_active_slot_count,
            fairness_state.requested_cpu_count,
            fairness_state.logical_processor_count,
            fairness_state.bsp_apic_id,
            fairness_state.total_drained_task_count,
            fairness_state.total_dispatch_count,
            fairness_state.total_accumulator,
            fairness_state.drain_round_count,
        },
    ) catch unreachable;
    used += head.len;
    const tail = std.fmt.bufPrint(
        buffer[used..],
    while (entry_index < fairness_state.exported_count) : (entry_index += 1) {
        const entry = fairness_entries[entry_index];
        const line = std.fmt.bufPrint(
            buffer[used..],
        "present={d}\npolicy={d}\nexported_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nlast_round_active_slot_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_debt_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndrain_round_count={d}\n",
        .{
            debt_state.present,
            debt_state.policy,
            debt_state.exported_count,
            debt_state.active_count,
            debt_state.peak_active_slot_count,
            debt_state.last_round_active_slot_count,
            debt_state.requested_cpu_count,
            debt_state.logical_processor_count,
            debt_state.bsp_apic_id,
            debt_state.total_debt_task_count,
            debt_state.total_dispatch_count,
            debt_state.total_accumulator,
            debt_state.drain_round_count,
        },
    ) catch unreachable;
    used += head.len;
    const tail = std.fmt.bufPrint(
        buffer[used..],
    while (entry_index < debt_state.exported_count) : (entry_index += 1) {
        const entry = debt_entries[entry_index];
        const line_a = std.fmt.bufPrint(
            buffer[used..],
            "slot[{d}].target_apic_id={d}\nslot[{d}].dispatch_count={d}\nslot[{d}].debt_task_count={d}\nslot[{d}].total_debt_task_count={d}\nslot[{d}].seed_task_count={d}\nslot[{d}].final_task_count={d}\nslot[{d}].initial_debt={d}\nslot[{d}].remaining_debt={d}\nslot[{d}].last_task_id={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.dispatch_count,
                entry_index, entry.debt_task_count,
                entry_index, entry.total_debt_task_count,
                entry_index, entry.seed_task_count,
                entry_index, entry.final_task_count,
                entry_index, entry.initial_debt,
                entry_index, entry.remaining_debt,
                entry_index, entry.last_task_id,
            },
        ) catch unreachable;
        used += line_a.len;
        const line_b = std.fmt.bufPrint(
            buffer[used..],
        "present={d}\npolicy={d}\nexported_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nlast_round_active_slot_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_admitted_task_count={d}\ntotal_debt_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndrain_round_count={d}\n",
        .{
            admission_state.present,
            admission_state.policy,
            admission_state.exported_count,
            admission_state.active_count,
            admission_state.peak_active_slot_count,
            admission_state.last_round_active_slot_count,
            admission_state.requested_cpu_count,
            admission_state.logical_processor_count,
            admission_state.bsp_apic_id,
            admission_state.total_admitted_task_count,
            admission_state.total_debt_task_count,
            admission_state.total_dispatch_count,
            admission_state.total_accumulator,
            admission_state.drain_round_count,
        },
    ) catch unreachable;
    used += head.len;
    const tail = std.fmt.bufPrint(
        buffer[used..],
    while (entry_index < admission_state.exported_count) : (entry_index += 1) {
        const entry = admission_entries[entry_index];
        const line_a = std.fmt.bufPrint(
            buffer[used..],
            "slot[{d}].target_apic_id={d}\nslot[{d}].dispatch_count={d}\nslot[{d}].admission_task_count={d}\nslot[{d}].total_admitted_task_count={d}\nslot[{d}].debt_task_count={d}\nslot[{d}].total_debt_task_count={d}\nslot[{d}].seed_task_count={d}\nslot[{d}].final_task_count={d}\nslot[{d}].initial_debt={d}\nslot[{d}].remaining_debt={d}\nslot[{d}].last_task_id={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.dispatch_count,
                entry_index, entry.admission_task_count,
                entry_index, entry.total_admitted_task_count,
                entry_index, entry.debt_task_count,
                entry_index, entry.total_debt_task_count,
                entry_index, entry.seed_task_count,
                entry_index, entry.final_task_count,
                entry_index, entry.initial_debt,
                entry_index, entry.remaining_debt,
                entry_index, entry.last_task_id,
            },
        ) catch unreachable;
        used += line_a.len;
        const line_b = std.fmt.bufPrint(
            buffer[used..],
        "present={d}\npolicy={d}\nexported_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nlast_round_active_slot_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_waiting_task_count={d}\ntotal_debt_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndrain_round_count={d}\naging_round_count={d}\n",
        .{
            aging_state.present,
            aging_state.policy,
            aging_state.exported_count,
            aging_state.active_count,
            aging_state.peak_active_slot_count,
            aging_state.last_round_active_slot_count,
            aging_state.requested_cpu_count,
            aging_state.logical_processor_count,
            aging_state.bsp_apic_id,
            aging_state.total_waiting_task_count,
            aging_state.total_debt_task_count,
            aging_state.total_dispatch_count,
            aging_state.total_accumulator,
            aging_state.drain_round_count,
            aging_state.aging_round_count,
        },
    ) catch unreachable;
    used += head.len;
    const tail = std.fmt.bufPrint(
        buffer[used..],
    while (entry_index < aging_state.exported_count) : (entry_index += 1) {
        const entry = aging_entries[entry_index];
        const line_a = std.fmt.bufPrint(
            buffer[used..],
        "present={d}\npolicy={d}\nexported_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nlast_round_active_slot_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_waiting_task_count={d}\ntotal_debt_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndrain_round_count={d}\naging_round_count={d}\nfairshare_round_count={d}\n",
        .{
            fairshare_state.present,
            fairshare_state.policy,
            fairshare_state.exported_count,
            fairshare_state.active_count,
            fairshare_state.peak_active_slot_count,
            fairshare_state.last_round_active_slot_count,
            fairshare_state.requested_cpu_count,
            fairshare_state.logical_processor_count,
            fairshare_state.bsp_apic_id,
            fairshare_state.total_waiting_task_count,
            fairshare_state.total_debt_task_count,
            fairshare_state.total_dispatch_count,
            fairshare_state.total_accumulator,
            fairshare_state.drain_round_count,
            fairshare_state.aging_round_count,
            fairshare_state.fairshare_round_count,
        },
    ) catch unreachable;
    used += head.len;
    const tail = std.fmt.bufPrint(
        buffer[used..],
    while (entry_index < fairshare_state.exported_count) : (entry_index += 1) {
        const entry = fairshare_entries[entry_index];
        const line_a = std.fmt.bufPrint(
            buffer[used..],
        "present={d}\npolicy={d}\nexported_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nlast_round_active_slot_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_waiting_task_count={d}\ntotal_debt_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndrain_round_count={d}\naging_round_count={d}\nquota_round_count={d}\n",
        .{
            quota_state.present,
            quota_state.policy,
            quota_state.exported_count,
            quota_state.active_count,
            quota_state.peak_active_slot_count,
            quota_state.last_round_active_slot_count,
            quota_state.requested_cpu_count,
            quota_state.logical_processor_count,
            quota_state.bsp_apic_id,
            quota_state.total_waiting_task_count,
            quota_state.total_debt_task_count,
            quota_state.total_dispatch_count,
            quota_state.total_accumulator,
            quota_state.drain_round_count,
            quota_state.aging_round_count,
            quota_state.quota_round_count,
        },
    ) catch unreachable;
    used += head.len;
    const tail = std.fmt.bufPrint(
        buffer[used..],
    while (entry_index < quota_state.exported_count) : (entry_index += 1) {
        const entry = quota_entries[entry_index];
        const line_a = std.fmt.bufPrint(
            buffer[used..],
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

        if (slot_index >= backfill_state.exported_count) break;
        const exported_index = window_state.exported_count;
        window_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .dispatch_count = dispatch_count,
            .window_task_count = window_task_count,
            .total_window_task_count = total_window_task_count,
            .last_task_id = WindowStorage.last_task_id[slot_index],
        window_state.exported_count += 1;
        if (started != 0 and halted == 0) window_state.active_count +%= 1;
        window_state.total_window_task_count +%= total_window_task_count;
        window_state.total_dispatch_count +%= dispatch_count;
        window_state.total_accumulator +%= total_accumulator;
    }
    if (window_state.active_count > window_peak_active_slot_count) {
        window_peak_active_slot_count = window_state.active_count;
    }
    window_state.peak_active_slot_count = window_peak_active_slot_count;
    if (window_state.exported_count != 0 or window_state.total_deferred_task_count != 0 or window_state.wrap_count != 0) {
        window_state.present = 1;
    }

    fairness_state = zeroFairnessState();
    fairness_state.present = if (state.supported != 0) 1 else 0;
    fairness_state.policy = fairness_policy;
    fairness_state.requested_cpu_count = topology.enabled_count;
    fairness_state.logical_processor_count = lapic_state.logical_processor_count;
    fairness_state.bsp_apic_id = lapic_state.current_apic_id;
    fairness_state.peak_active_slot_count = fairness_peak_active_slot_count;
    fairness_state.last_round_active_slot_count = fairness_last_round_active_slot_count;
    fairness_state.drain_round_count = fairness_drain_round_count;
    fairness_state.last_round_drained_task_count = fairness_last_round_task_count;
    fairness_state.initial_pending_task_count = fairness_initial_pending_task_count;
    fairness_state.last_pending_task_count = fairness_last_pending_task_count;
    fairness_state.peak_pending_task_count = fairness_peak_pending_task_count;
    fairness_state.drain_task_budget = fairness_task_budget;
    fairness_state.final_task_cursor = fairness_task_cursor;
    fairness_state.wrap_count = fairness_wrap_count;
    fairness_state.last_start_slot_index = fairness_last_start_slot_index;
    fairness_state.min_slot_task_count = fairness_min_slot_task_count;
    fairness_state.max_slot_task_count = fairness_max_slot_task_count;
        const exported_index = fairness_state.exported_count;
        fairness_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .dispatch_count = dispatch_count,
            .drained_task_count = drained_task_count,
            .total_drained_task_count = total_drained_task_count,
            .last_task_id = FairnessStorage.last_task_id[slot_index],
        fairness_state.exported_count += 1;
        if (started != 0 and halted == 0) fairness_state.active_count +%= 1;
        fairness_state.total_drained_task_count +%= total_drained_task_count;
        fairness_state.total_dispatch_count +%= dispatch_count;
        fairness_state.total_accumulator +%= total_accumulator;
    }
    if (fairness_state.active_count > fairness_peak_active_slot_count) {
        fairness_peak_active_slot_count = fairness_state.active_count;
    }
    fairness_state.peak_active_slot_count = fairness_peak_active_slot_count;
    if (fairness_state.exported_count != 0 or fairness_state.drain_round_count != 0) {
        fairness_state.present = 1;
    }

        const exported_index = debt_state.exported_count;
        debt_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .dispatch_count = dispatch_count,
            .debt_task_count = debt_task_count,
            .total_debt_task_count = total_debt_task_count,
            .seed_task_count = seed_task_count,
            .final_task_count = final_task_count,
            .initial_debt = DebtStorage.initial_debt[slot_index],
            .remaining_debt = remaining_debt,
            .last_task_id = DebtStorage.last_task_id[slot_index],
        debt_state.exported_count += 1;
        if (started != 0 and halted == 0) debt_state.active_count +%= 1;
        debt_state.total_debt_task_count +%= total_debt_task_count;
        debt_state.total_dispatch_count +%= dispatch_count;
        debt_state.total_accumulator +%= total_accumulator;
    }
    if (debt_state.active_count > debt_peak_active_slot_count) {
        debt_peak_active_slot_count = debt_state.active_count;
    }
    debt_state.peak_active_slot_count = debt_peak_active_slot_count;
    if (debt_state.exported_count != 0 or debt_state.drain_round_count != 0 or debt_state.initial_total_debt != 0) {
        debt_state.present = 1;
    }

    admission_state = zeroAdmissionState();
    admission_state.present = if (state.supported != 0) 1 else 0;
    admission_state.policy = admission_policy;
    admission_state.requested_cpu_count = topology.enabled_count;
    admission_state.logical_processor_count = lapic_state.logical_processor_count;
    admission_state.bsp_apic_id = lapic_state.current_apic_id;
    admission_state.peak_active_slot_count = admission_peak_active_slot_count;
    admission_state.last_round_active_slot_count = admission_last_round_active_slot_count;
    admission_state.drain_round_count = admission_drain_round_count;
    admission_state.last_round_admitted_task_count = admission_last_round_admitted_task_count;
    admission_state.last_round_debt_task_count = admission_last_round_debt_task_count;
    admission_state.initial_pending_task_count = admission_initial_pending_task_count;
    admission_state.last_pending_task_count = admission_last_pending_task_count;
    admission_state.peak_pending_task_count = admission_peak_pending_task_count;
    admission_state.task_budget = admission_task_budget;
    admission_state.initial_min_slot_task_count = admission_initial_min_slot_task_count;
    admission_state.initial_max_slot_task_count = admission_initial_max_slot_task_count;
        const exported_index = admission_state.exported_count;
        admission_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .dispatch_count = dispatch_count,
            .admission_task_count = admission_task_count,
            .total_admitted_task_count = total_admitted_task_count,
            .debt_task_count = debt_task_count,
            .total_debt_task_count = total_debt_task_count,
            .seed_task_count = seed_task_count,
            .final_task_count = final_task_count,
            .initial_debt = AdmissionStorage.initial_debt[slot_index],
            .remaining_debt = remaining_debt,
            .last_task_id = AdmissionStorage.last_task_id[slot_index],
        admission_state.exported_count += 1;
        if (started != 0 and halted == 0) admission_state.active_count +%= 1;
        admission_state.total_admitted_task_count +%= total_admitted_task_count;
        admission_state.total_debt_task_count +%= total_debt_task_count;
        admission_state.total_dispatch_count +%= dispatch_count;
        admission_state.total_accumulator +%= total_accumulator;
    }
    if (admission_state.active_count > admission_peak_active_slot_count) {
        admission_peak_active_slot_count = admission_state.active_count;
    }
    admission_state.peak_active_slot_count = admission_peak_active_slot_count;
    if (admission_state.exported_count != 0 or
        admission_state.drain_round_count != 0 or
        admission_state.initial_total_debt != 0 or
        admission_state.total_admitted_task_count != 0)
    {
        admission_state.present = 1;
    }

    aging_state = zeroAgingState();
    aging_state.present = if (state.supported != 0) 1 else 0;
    aging_state.policy = aging_policy;
    aging_state.requested_cpu_count = topology.enabled_count;
    aging_state.logical_processor_count = lapic_state.logical_processor_count;
    aging_state.bsp_apic_id = lapic_state.current_apic_id;
    aging_state.peak_active_slot_count = aging_peak_active_slot_count;
    aging_state.last_round_active_slot_count = aging_last_round_active_slot_count;
    aging_state.drain_round_count = aging_drain_round_count;
    aging_state.aging_round_count = aging_round_count;
    aging_state.last_round_waiting_task_count = aging_last_round_waiting_task_count;
    aging_state.last_round_debt_task_count = aging_last_round_debt_task_count;
    aging_state.initial_pending_task_count = aging_initial_pending_task_count;
    aging_state.last_pending_task_count = aging_last_pending_task_count;
    aging_state.peak_pending_task_count = aging_peak_pending_task_count;
    aging_state.task_budget = aging_task_budget;
    aging_state.aging_step = aging_step_value;
    aging_state.initial_min_slot_task_count = aging_initial_min_slot_task_count;
    aging_state.initial_max_slot_task_count = aging_initial_max_slot_task_count;
        const exported_index = aging_state.exported_count;
        aging_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .dispatch_count = dispatch_count,
            .waiting_task_count = waiting_task_count,
            .total_waiting_task_count = total_waiting_task_count,
            .debt_task_count = debt_task_count,
            .total_debt_task_count = total_debt_task_count,
            .seed_task_count = seed_task_count,
            .final_task_count = final_task_count,
            .initial_debt = AgingStorage.initial_debt[slot_index],
            .remaining_debt = remaining_debt,
            .last_task_id = AgingStorage.last_task_id[slot_index],
        aging_state.exported_count += 1;
        if (started != 0 and halted == 0) aging_state.active_count +%= 1;
        aging_state.total_waiting_task_count +%= total_waiting_task_count;
        aging_state.total_debt_task_count +%= total_debt_task_count;
        aging_state.total_dispatch_count +%= dispatch_count;
        aging_state.total_accumulator +%= total_accumulator;
    }
    if (aging_state.active_count > aging_peak_active_slot_count) {
        aging_peak_active_slot_count = aging_state.active_count;
    }
    aging_state.peak_active_slot_count = aging_peak_active_slot_count;
    if (aging_state.exported_count != 0 or
        aging_state.drain_round_count != 0 or
        aging_state.initial_total_debt != 0 or
        aging_state.total_waiting_task_count != 0 or
        aging_state.total_aged_task_count != 0)
    {
        aging_state.present = 1;
    }

    fairshare_state = zeroFairshareState();
    fairshare_state.present = if (state.supported != 0) 1 else 0;
    fairshare_state.policy = fairshare_policy;
    fairshare_state.requested_cpu_count = topology.enabled_count;
    fairshare_state.logical_processor_count = lapic_state.logical_processor_count;
    fairshare_state.bsp_apic_id = lapic_state.current_apic_id;
    fairshare_state.peak_active_slot_count = fairshare_peak_active_slot_count;
    fairshare_state.last_round_active_slot_count = fairshare_last_round_active_slot_count;
    fairshare_state.drain_round_count = fairshare_drain_round_count;
    fairshare_state.aging_round_count = fairshare_aging_round_count;
    fairshare_state.fairshare_round_count = fairshare_fairshare_round_count;
    fairshare_state.last_round_waiting_task_count = fairshare_last_round_waiting_task_count;
    fairshare_state.last_round_debt_task_count = fairshare_last_round_debt_task_count;
    fairshare_state.last_round_fairshare_task_count = fairshare_last_round_fairshare_task_count;
    fairshare_state.initial_pending_task_count = fairshare_initial_pending_task_count;
    fairshare_state.last_pending_task_count = fairshare_last_pending_task_count;
    fairshare_state.peak_pending_task_count = fairshare_peak_pending_task_count;
    fairshare_state.task_budget = fairshare_task_budget;
    fairshare_state.aging_step = fairshare_aging_step_value;
    fairshare_state.initial_min_slot_task_count = fairshare_initial_min_slot_task_count;
    fairshare_state.initial_max_slot_task_count = fairshare_initial_max_slot_task_count;
        const exported_index = fairshare_state.exported_count;
        fairshare_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .dispatch_count = dispatch_count,
            .waiting_task_count = waiting_task_count,
            .total_waiting_task_count = total_waiting_task_count,
            .debt_task_count = debt_task_count,
            .total_debt_task_count = total_debt_task_count,
            .fairshare_task_count = fairshare_task_count,
            .total_fairshare_task_count = total_fairshare_task_count,
            .seed_task_count = seed_task_count,
            .final_task_count = final_task_count,
            .initial_debt = FairshareStorage.initial_debt[slot_index],
            .remaining_debt = remaining_debt,
            .last_task_id = FairshareStorage.last_task_id[slot_index],
        fairshare_state.exported_count += 1;
        if (started != 0 and halted == 0) fairshare_state.active_count +%= 1;
        fairshare_state.total_waiting_task_count +%= total_waiting_task_count;
        fairshare_state.total_debt_task_count +%= total_debt_task_count;
        fairshare_state.total_dispatch_count +%= dispatch_count;
        fairshare_state.total_accumulator +%= total_accumulator;
    }
    if (fairshare_state.active_count > fairshare_peak_active_slot_count) {
        fairshare_peak_active_slot_count = fairshare_state.active_count;
    }
    fairshare_state.peak_active_slot_count = fairshare_peak_active_slot_count;
    if (fairshare_state.exported_count != 0 or
        fairshare_state.drain_round_count != 0 or
        fairshare_state.initial_total_debt != 0 or
        fairshare_state.total_waiting_task_count != 0 or
        fairshare_state.total_fairshare_task_count != 0)
    {
        fairshare_state.present = 1;
    }

    quota_state = zeroQuotaState();
    quota_state.present = if (state.supported != 0) 1 else 0;
    quota_state.policy = quota_policy;
    quota_state.requested_cpu_count = topology.enabled_count;
    quota_state.logical_processor_count = lapic_state.logical_processor_count;
    quota_state.bsp_apic_id = lapic_state.current_apic_id;
    quota_state.peak_active_slot_count = quota_peak_active_slot_count;
    quota_state.last_round_active_slot_count = quota_last_round_active_slot_count;
    quota_state.drain_round_count = quota_drain_round_count;
    quota_state.aging_round_count = quota_aging_round_count;
    quota_state.quota_round_count = quota_quota_round_count;
    quota_state.last_round_waiting_task_count = quota_last_round_waiting_task_count;
    quota_state.last_round_debt_task_count = quota_last_round_debt_task_count;
    quota_state.last_round_quota_task_count = quota_last_round_quota_task_count;
    quota_state.initial_pending_task_count = quota_initial_pending_task_count;
    quota_state.last_pending_task_count = quota_last_pending_task_count;
    quota_state.peak_pending_task_count = quota_peak_pending_task_count;
    quota_state.task_budget = quota_task_budget;
    quota_state.aging_step = quota_aging_step_value;
    quota_state.quota_budget_total = quota_budget_total;
    quota_state.initial_min_slot_task_count = quota_initial_min_slot_task_count;
    quota_state.initial_max_slot_task_count = quota_initial_max_slot_task_count;
        const exported_index = quota_state.exported_count;
        quota_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .dispatch_count = dispatch_count,
            .waiting_task_count = waiting_task_count,
            .total_waiting_task_count = total_waiting_task_count,
            .debt_task_count = debt_task_count,
            .total_debt_task_count = total_debt_task_count,
            .quota_task_count = quota_task_count,
            .total_quota_task_count = total_quota_task_count,
            .seed_task_count = seed_task_count,
            .final_task_count = final_task_count,
            .configured_quota = configured_quota,
            .remaining_quota = remaining_quota,
            .initial_debt = QuotaStorage.initial_debt[slot_index],
            .remaining_debt = remaining_debt,
            .last_task_id = QuotaStorage.last_task_id[slot_index],
        quota_state.exported_count += 1;
        if (started != 0 and halted == 0) quota_state.active_count +%= 1;
        quota_state.total_waiting_task_count +%= total_waiting_task_count;
        quota_state.total_debt_task_count +%= total_debt_task_count;
        quota_state.total_dispatch_count +%= dispatch_count;
        quota_state.total_accumulator +%= total_accumulator;
    }
    if (quota_state.active_count > quota_peak_active_slot_count) {
        quota_peak_active_slot_count = quota_state.active_count;
    }
    quota_state.peak_active_slot_count = quota_peak_active_slot_count;
    if (quota_state.exported_count != 0 or
        quota_state.drain_round_count != 0 or
        quota_state.initial_total_debt != 0 or
        quota_state.total_waiting_task_count != 0 or
        quota_state.total_quota_task_count != 0)
    {
        quota_state.present = 1;
    }
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

test "i386 ap startup maps scheduler-owned tasks onto concurrent slots" {
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

    const tasks = [_]abi.BaremetalTask{
    try std.testing.expectEqual(@as(u8, 2), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 2), snapshot.active_count);
    try std.testing.expectEqual(@as(u32, 5), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 15), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), snapshot.dispatch_round_count);

    try std.testing.expectEqual(@as(u8, 2), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 2), snapshot.active_count);
    try std.testing.expectEqual(@as(u32, 10), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 30), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 2), snapshot.dispatch_round_count);
    try std.testing.expectEqual(@as(u32, 5), snapshot.last_round_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_round_dispatch_count);
    try std.testing.expectEqual(@as(u32, 15), snapshot.last_round_accumulator);
    try std.testing.expectEqual(@as(u32, 5), snapshot.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 5), snapshot.last_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u8, 2), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 2), snapshot.active_count);
    try std.testing.expectEqual(@as(u32, 5), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 15), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), snapshot.dispatch_round_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u8, 2), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 2), snapshot.active_count);
    try std.testing.expectEqual(@as(u32, 10), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 30), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 2), snapshot.dispatch_round_count);
    try std.testing.expectEqual(@as(u32, 5), snapshot.last_round_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_round_dispatch_count);
    try std.testing.expectEqual(@as(u32, 15), snapshot.last_round_accumulator);
    try std.testing.expectEqual(@as(u32, 4), snapshot.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.last_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u8, 3), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 3), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 3), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 3), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 24), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 9), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 108), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 3), snapshot.dispatch_round_count);
    try std.testing.expectEqual(@as(u32, 8), snapshot.last_round_owned_task_count);
    try std.testing.expectEqual(@as(u32, 3), snapshot.last_round_dispatch_count);
    try std.testing.expectEqual(@as(u32, 36), snapshot.last_round_accumulator);
    try std.testing.expectEqual(@as(u32, 14), snapshot.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 7), snapshot.last_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 32), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 144), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 4), snapshot.dispatch_round_count);
    try std.testing.expectEqual(@as(u32, 8), snapshot.last_round_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.last_round_dispatch_count);
    try std.testing.expectEqual(@as(u32, 36), snapshot.last_round_accumulator);
    try std.testing.expectEqual(@as(u32, 23), snapshot.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 7), snapshot.last_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 3), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 64), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 544), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 4), snapshot.dispatch_round_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.last_round_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.last_round_dispatch_count);
    try std.testing.expectEqual(@as(u32, 136), snapshot.last_round_accumulator);
    try std.testing.expectEqual(@as(u32, 48), snapshot.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.last_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 3), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 96), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 24), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 816), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 6), snapshot.dispatch_round_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.last_round_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.last_round_dispatch_count);
    try std.testing.expectEqual(@as(u32, 136), snapshot.last_round_accumulator);
    try std.testing.expectEqual(@as(u32, 72), snapshot.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.last_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.total_window_task_count);
    try std.testing.expectEqual(@as(u32, 12), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 136), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 3), snapshot.dispatch_round_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.last_round_window_task_count);
    try std.testing.expectEqual(@as(u32, 32), snapshot.total_deferred_task_count);
    try std.testing.expectEqual(@as(u32, 12), snapshot.last_deferred_task_count);
    try std.testing.expectEqual(@as(u32, 6), snapshot.window_task_budget);
    try std.testing.expectEqual(@as(u32, 0), snapshot.task_cursor);
    try std.testing.expectEqual(@as(u32, 1), snapshot.wrap_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u16, 4), windowEntryCount());
    const first_entry = windowEntry(0);
    const second_entry = windowEntry(1);
    const third_entry = windowEntry(2);
    const fourth_entry = windowEntry(3);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), first_entry.window_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.total_window_task_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 37), first_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 2), WindowStorage.task_ids[@as(usize, first_entry.slot_index)][0]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.window_task_count);
    try std.testing.expectEqual(@as(u32, 5), second_entry.total_window_task_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 43), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), WindowStorage.task_ids[@as(usize, second_entry.slot_index)][0]);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.window_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.total_window_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 32), third_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 4), WindowStorage.task_ids[@as(usize, third_entry.slot_index)][0]);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.window_task_count);
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.total_window_task_count);
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 24), fourth_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 3), WindowStorage.task_ids[@as(usize, fourth_entry.slot_index)][0]);

    const window_render = try renderWindowAlloc(std.testing.allocator);
    defer std.testing.allocator.free(window_render);
    try std.testing.expect(std.mem.indexOf(u8, window_render, "total_window_task_count=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, window_render, "total_deferred_task_count=32") != null);
    try std.testing.expect(std.mem.indexOf(u8, window_render, "last_deferred_task_count=12") != null);
    try std.testing.expect(std.mem.indexOf(u8, window_render, "window_task_budget=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, window_render, "wrap_count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, window_render, "slot[0].task[0]=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, window_render, "slot[1].task[0]=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, window_render, "slot[2].task[0]=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, window_render, "slot[3].task[0]=3") != null);

    try haltApSlot(3);
    try haltApSlot(2);
    try haltApSlot(1);
    try haltApSlot(0);
}

    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.total_drained_task_count);
    try std.testing.expectEqual(@as(u32, 13), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 136), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 4), snapshot.drain_round_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.last_round_drained_task_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.initial_pending_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_pending_task_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.peak_pending_task_count);
    try std.testing.expectEqual(@as(u32, 5), snapshot.drain_task_budget);
    try std.testing.expectEqual(@as(u32, 0), snapshot.final_task_cursor);
    try std.testing.expectEqual(@as(u32, 1), snapshot.wrap_count);
    try std.testing.expectEqual(@as(u32, 3), snapshot.last_start_slot_index);
    try std.testing.expectEqual(@as(u32, 4), snapshot.min_slot_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.max_slot_task_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 10), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 2), snapshot.drain_round_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_round_debt_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.initial_pending_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_pending_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.peak_pending_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.debt_task_budget);
    try std.testing.expectEqual(@as(u32, 2), snapshot.initial_min_slot_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.initial_max_slot_task_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.total_admitted_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 6), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 21), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 3), snapshot.drain_round_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_round_admitted_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_round_debt_task_count);
    try std.testing.expectEqual(@as(u32, 6), snapshot.initial_pending_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_pending_task_count);
    try std.testing.expectEqual(@as(u32, 6), snapshot.peak_pending_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.task_budget);
    try std.testing.expectEqual(@as(u32, 2), snapshot.initial_min_slot_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.initial_max_slot_task_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.total_waiting_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 6), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 21), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 3), snapshot.drain_round_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.aging_round_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_round_waiting_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_round_debt_task_count);
    try std.testing.expectEqual(@as(u32, 6), snapshot.initial_pending_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_pending_task_count);
    try std.testing.expectEqual(@as(u32, 6), snapshot.peak_pending_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.task_budget);
    try std.testing.expectEqual(@as(u32, 3), snapshot.aging_step);
    try std.testing.expectEqual(@as(u32, 2), snapshot.initial_min_slot_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.initial_max_slot_task_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 8), snapshot.total_waiting_task_count);
    try std.testing.expectEqual(@as(u32, 3), snapshot.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 11), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 66), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 6), snapshot.drain_round_count);
    try std.testing.expectEqual(@as(u32, 5), snapshot.aging_round_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.fairshare_round_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.last_round_waiting_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_round_debt_task_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.last_round_fairshare_task_count);
    try std.testing.expectEqual(@as(u32, 11), snapshot.initial_pending_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_pending_task_count);
    try std.testing.expectEqual(@as(u32, 11), snapshot.peak_pending_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.task_budget);
    try std.testing.expectEqual(@as(u32, 2), snapshot.aging_step);
    try std.testing.expectEqual(@as(u32, 1), snapshot.initial_min_slot_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.initial_max_slot_task_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 8), snapshot.total_waiting_task_count);
    try std.testing.expectEqual(@as(u32, 3), snapshot.total_debt_task_count);
    try std.testing.expectEqual(total_accumulator, snapshot.total_accumulator);
    try std.testing.expect(snapshot.total_dispatch_count > 0);
    try std.testing.expect(snapshot.drain_round_count > 0);
    try std.testing.expect(snapshot.aging_round_count > 0);
    try std.testing.expect(snapshot.quota_round_count > 0);
    try std.testing.expectEqual(@as(u32, 11), snapshot.initial_pending_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_pending_task_count);
    try std.testing.expectEqual(@as(u32, 11), snapshot.peak_pending_task_count);
    try std.testing.expectEqual(@as(u32, 3), snapshot.task_budget);
    try std.testing.expectEqual(@as(u32, 2), snapshot.aging_step);
    try std.testing.expectEqual(@as(u32, 8), snapshot.quota_budget_total);
    try std.testing.expectEqual(@as(u32, 3), snapshot.initial_total_debt);
    try std.testing.expectEqual(@as(u32, 0), snapshot.remaining_total_debt);
    try std.testing.expectEqual(@as(u32, 3), snapshot.total_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 8), snapshot.total_promoted_task_count);
    try std.testing.expectEqual(@as(u32, 8), snapshot.total_quota_task_count);
    try std.testing.expect(snapshot.final_max_slot_task_count >= snapshot.final_min_slot_task_count);
    try std.testing.expect(snapshot.last_start_slot_index < 4);

    try std.testing.expectEqual(@as(u16, 4), quotaEntryCount());
    var final_task_total: u32 = 0;
    var waiting_task_total: u32 = 0;
    var debt_task_total: u32 = 0;
    var quota_task_total: u32 = 0;
    inline for ([_]struct { index: u16, apic_id: u32, quota: u32 }{
        .{ .index = 0, .apic_id = 1, .quota = 3 },
        .{ .index = 1, .apic_id = 2, .quota = 2 },
        .{ .index = 2, .apic_id = 3, .quota = 2 },
        .{ .index = 3, .apic_id = 4, .quota = 1 },
    }) |expected| {
        const entry = quotaEntry(expected.index);
        try std.testing.expectEqual(expected.apic_id, entry.target_apic_id);
        try std.testing.expectEqual(expected.quota, entry.configured_quota);
        try std.testing.expect(entry.seed_task_count > 0);
        try std.testing.expect(entry.final_task_count >= entry.seed_task_count);
        try std.testing.expect(entry.total_accumulator > 0);
        try std.testing.expectEqual(@as(u32, 1), entry.started);
        try std.testing.expectEqual(@as(u32, 0), entry.halted);
        try std.testing.expectEqual(expected.index, entry.slot_index);
        final_task_total +%= entry.final_task_count;
        waiting_task_total +%= entry.total_waiting_task_count;
        debt_task_total +%= entry.total_debt_task_count;
        quota_task_total +%= entry.total_quota_task_count;
    }
    try std.testing.expectEqual(@as(u32, 16), final_task_total);
    try std.testing.expectEqual(snapshot.total_waiting_task_count, waiting_task_total);
    try std.testing.expectEqual(snapshot.total_debt_task_count, debt_task_total);
    try std.testing.expectEqual(snapshot.total_quota_task_count, quota_task_total);

    const quota_render = try renderQuotaAlloc(std.testing.allocator);
    defer std.testing.allocator.free(quota_render);
    try std.testing.expect(std.mem.indexOf(u8, quota_render, "total_waiting_task_count=8") != null);
    try std.testing.expect(std.mem.indexOf(u8, quota_render, "total_debt_task_count=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, quota_render, "quota_budget_total=8") != null);
    try std.testing.expect(std.mem.indexOf(u8, quota_render, "total_quota_task_count=8") != null);
    try std.testing.expect(std.mem.indexOf(u8, quota_render, "slot[0].configured_quota=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, quota_render, "slot[3].configured_quota=1") != null);

    try haltApSlot(3);
    try haltApSlot(2);
    try haltApSlot(1);
    try haltApSlot(0);
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
