pub const OwnershipError = Error || error{
    NoReadyTask,
    TooManyOwnedTasks,
};

var state: abi.BaremetalApStartupState = zeroState();
var multi_state: abi.BaremetalApMultiState = zeroMultiState();
var multi_entries: [max_multi_ap_entries]abi.BaremetalApMultiEntry = std.mem.zeroes([max_multi_ap_entries]abi.BaremetalApMultiEntry);
var slot_state: abi.BaremetalApSlotState = zeroSlotState();
var slot_entries: [max_ap_command_slots]abi.BaremetalApSlotEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApSlotEntry);
var ownership_state: abi.BaremetalApOwnershipState = zeroOwnershipState();
var ownership_entries: [max_ap_command_slots]abi.BaremetalApOwnershipEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApOwnershipEntry);
var failover_state: abi.BaremetalApFailoverState = zeroFailoverState();
var backfill_state: abi.BaremetalApBackfillState = zeroBackfillState();
var backfill_entries: [max_ap_command_slots]abi.BaremetalApBackfillEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApBackfillEntry);
var window_state: abi.BaremetalApWindowState = zeroWindowState();
var window_entries: [max_ap_command_slots]abi.BaremetalApWindowEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApWindowEntry);
var fairness_state: abi.BaremetalApFairnessState = zeroFairnessState();
var fairness_entries: [max_ap_command_slots]abi.BaremetalApFairnessEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApFairnessEntry);
var ownership_dispatch_round_count: u32 = 0;
var ownership_policy: u8 = abi.ap_ownership_policy_round_robin;
var ownership_peak_active_slot_count: u8 = 0;
var ownership_last_round_active_slot_count: u8 = 0;
var ownership_last_round_owned_task_count: u32 = 0;
var ownership_last_round_dispatch_count: u32 = 0;
var ownership_last_round_accumulator: u32 = 0;
var ownership_last_redistributed_task_count: u32 = 0;
var ownership_last_start_slot_index: u32 = 0;
var failover_retired_slot_event_count: u8 = 0;
var failover_last_retired_slot_index: u8 = 0;
var failover_total_failed_over_task_count: u32 = 0;
var failover_last_failed_over_task_count: u32 = 0;
var backfill_last_backfilled_task_count: u32 = 0;
var backfill_total_terminated_task_count: u32 = 0;
var backfill_last_terminated_task_count: u32 = 0;
var backfill_total_round_count: u32 = 0;
var window_dispatch_round_count: u32 = 0;
var window_policy: u8 = abi.ap_ownership_policy_round_robin;
var window_peak_active_slot_count: u8 = 0;
var window_last_round_active_slot_count: u8 = 0;
var window_last_round_task_count: u32 = 0;
var window_last_round_dispatch_count: u32 = 0;
var window_last_round_accumulator: u32 = 0;
var window_total_deferred_task_count: u32 = 0;
var window_last_deferred_task_count: u32 = 0;
var window_task_budget: u32 = 0;
var window_task_cursor: u32 = 0;
var window_wrap_count: u32 = 0;
var window_last_start_slot_index: u32 = 0;
var fairness_drain_round_count: u32 = 0;
var fairness_policy: u8 = abi.ap_ownership_policy_round_robin;
var fairness_peak_active_slot_count: u8 = 0;
var fairness_last_round_active_slot_count: u8 = 0;
var fairness_last_round_task_count: u32 = 0;
var fairness_initial_pending_task_count: u32 = 0;
var fairness_last_pending_task_count: u32 = 0;
var fairness_peak_pending_task_count: u32 = 0;
var fairness_task_budget: u32 = 0;
var fairness_task_cursor: u32 = 0;
var fairness_wrap_count: u32 = 0;
var fairness_last_start_slot_index: u32 = 0;
var fairness_min_slot_task_count: u32 = 0;
var fairness_max_slot_task_count: u32 = 0;
var rebalance_policy: u8 = abi.ap_ownership_policy_round_robin;
var debt_policy: u8 = abi.ap_ownership_policy_round_robin;
var debt_peak_active_slot_count: u8 = 0;
var debt_last_round_active_slot_count: u8 = 0;
var debt_last_round_task_count: u32 = 0;
var debt_initial_pending_task_count: u32 = 0;
var debt_last_pending_task_count: u32 = 0;
var debt_peak_pending_task_count: u32 = 0;
var debt_task_budget: u32 = 0;
var debt_initial_min_slot_task_count: u32 = 0;
var debt_initial_max_slot_task_count: u32 = 0;
var admission_policy: u8 = abi.ap_ownership_policy_round_robin;
var admission_peak_active_slot_count: u8 = 0;
var admission_last_round_active_slot_count: u8 = 0;
var admission_last_round_admitted_task_count: u32 = 0;
var admission_last_round_debt_task_count: u32 = 0;
var admission_initial_pending_task_count: u32 = 0;
var admission_last_pending_task_count: u32 = 0;
var admission_peak_pending_task_count: u32 = 0;
var admission_task_budget: u32 = 0;
var admission_initial_min_slot_task_count: u32 = 0;
var admission_initial_max_slot_task_count: u32 = 0;
var aging_policy: u8 = abi.ap_ownership_policy_round_robin;
var aging_peak_active_slot_count: u8 = 0;
var aging_last_round_active_slot_count: u8 = 0;
var aging_last_round_waiting_task_count: u32 = 0;
var aging_last_round_debt_task_count: u32 = 0;
var aging_initial_pending_task_count: u32 = 0;
var aging_last_pending_task_count: u32 = 0;
var aging_peak_pending_task_count: u32 = 0;
var aging_task_budget: u32 = 0;
var aging_step_value: u32 = 0;
var aging_initial_min_slot_task_count: u32 = 0;
var aging_initial_max_slot_task_count: u32 = 0;
var fairshare_policy: u8 = abi.ap_ownership_policy_round_robin;
var fairshare_peak_active_slot_count: u8 = 0;
var fairshare_last_round_active_slot_count: u8 = 0;
var fairshare_last_round_waiting_task_count: u32 = 0;
var fairshare_last_round_debt_task_count: u32 = 0;
var fairshare_last_round_fairshare_task_count: u32 = 0;
var fairshare_initial_pending_task_count: u32 = 0;
var fairshare_last_pending_task_count: u32 = 0;
var fairshare_peak_pending_task_count: u32 = 0;
var fairshare_task_budget: u32 = 0;
var fairshare_aging_step_value: u32 = 0;
var fairshare_initial_min_slot_task_count: u32 = 0;
var fairshare_initial_max_slot_task_count: u32 = 0;
var quota_policy: u8 = abi.ap_ownership_policy_round_robin;
var quota_peak_active_slot_count: u8 = 0;
var quota_last_round_active_slot_count: u8 = 0;
var quota_last_round_waiting_task_count: u32 = 0;
var quota_last_round_debt_task_count: u32 = 0;
var quota_last_round_quota_task_count: u32 = 0;
var quota_initial_pending_task_count: u32 = 0;
var quota_last_pending_task_count: u32 = 0;
var quota_peak_pending_task_count: u32 = 0;
var quota_task_budget: u32 = 0;
var quota_aging_step_value: u32 = 0;
var quota_budget_total: u32 = 0;
var quota_initial_min_slot_task_count: u32 = 0;
var quota_initial_max_slot_task_count: u32 = 0;
const OwnershipStorage = struct {
    var owned_task_ids: [max_ap_command_slots][max_task_batch_entries]u32 = [_][max_task_batch_entries]u32{[_]u32{0} ** max_task_batch_entries} ** max_ap_command_slots;
    var owned_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var dispatch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_owned_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var redistributed_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_redistributed_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var backfilled_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_backfilled_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_task_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
fn zeroOwnershipState() abi.BaremetalApOwnershipState {
    return .{
        .magic = abi.ap_ownership_magic,
        .api_version = abi.api_version,
        .present = 0,
        .policy = abi.ap_ownership_policy_round_robin,
        .policy = abi.ap_ownership_policy_round_robin,
        .retired_slot_event_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .last_retired_slot_index = 0,
        .reserved0 = .{ 0, 0, 0 },
        .total_owned_task_count = 0,
        .total_dispatch_count = 0,
        .total_accumulator = 0,
        .dispatch_round_count = 0,
        .total_redistributed_task_count = 0,
        .last_redistributed_task_count = 0,
        .total_failed_over_task_count = 0,
        .last_failed_over_task_count = 0,
    };
}

fn zeroBackfillState() abi.BaremetalApBackfillState {
    return .{
        .magic = abi.ap_backfill_magic,
        .api_version = abi.api_version,
        .present = 0,
        .policy = abi.ap_ownership_policy_round_robin,
        .policy = abi.ap_ownership_policy_round_robin,
        .policy = abi.ap_ownership_policy_round_robin,
        .policy = abi.ap_ownership_policy_round_robin,
        .policy = abi.ap_ownership_policy_round_robin,
        .policy = abi.ap_ownership_policy_round_robin,
        .policy = abi.ap_ownership_policy_round_robin,
        .policy = abi.ap_ownership_policy_round_robin,
        .policy = abi.ap_ownership_policy_round_robin,
fn clearOwnershipRoundSlot(slot_index: usize) void {
    OwnershipStorage.owned_task_count[slot_index] = 0;
    OwnershipStorage.redistributed_task_count[slot_index] = 0;
    OwnershipStorage.backfilled_task_count[slot_index] = 0;
    OwnershipStorage.last_task_id[slot_index] = 0;
    OwnershipStorage.last_priority[slot_index] = 0;
    OwnershipStorage.last_budget_ticks[slot_index] = 0;
    OwnershipStorage.last_batch_accumulator[slot_index] = 0;
    @memset(&OwnershipStorage.owned_task_ids[slot_index], 0);
}

fn clearWindowRoundSlot(slot_index: usize) void {
    WindowStorage.task_count[slot_index] = 0;
    WindowStorage.last_task_id[slot_index] = 0;
fn resetOwnershipSlot(slot_index: usize) void {
    clearOwnershipRoundSlot(slot_index);
    OwnershipStorage.dispatch_count[slot_index] = 0;
    OwnershipStorage.total_owned_task_count[slot_index] = 0;
    OwnershipStorage.total_redistributed_task_count[slot_index] = 0;
    OwnershipStorage.total_backfilled_task_count[slot_index] = 0;
    OwnershipStorage.total_accumulator[slot_index] = 0;
}

fn resetWindowSlot(slot_index: usize) void {
    clearWindowRoundSlot(slot_index);
    WindowStorage.dispatch_count[slot_index] = 0;
    WindowStorage.total_window_task_count[slot_index] = 0;
    WindowStorage.total_accumulator[slot_index] = 0;
}

fn resetWindowState() void {
    window_state = zeroWindowState();
    @memset(&window_entries, std.mem.zeroes(abi.BaremetalApWindowEntry));
    window_dispatch_round_count = 0;
    window_policy = abi.ap_ownership_policy_round_robin;
    window_peak_active_slot_count = 0;
    window_last_round_active_slot_count = 0;
    window_last_round_task_count = 0;
    window_last_round_dispatch_count = 0;
    window_last_round_accumulator = 0;
    window_total_deferred_task_count = 0;
    window_last_deferred_task_count = 0;
    window_task_budget = 0;
    window_task_cursor = 0;
    window_wrap_count = 0;
    window_last_start_slot_index = 0;
    for (0..max_ap_command_slots) |slot_index| resetWindowSlot(slot_index);
}

fn resetFairnessSlot(slot_index: usize) void {
    FairnessStorage.task_count[slot_index] = 0;
    FairnessStorage.dispatch_count[slot_index] = 0;
    FairnessStorage.total_drained_task_count[slot_index] = 0;
    FairnessStorage.last_task_id[slot_index] = 0;
    fairness_policy = abi.ap_ownership_policy_round_robin;
    fairness_peak_active_slot_count = 0;
    fairness_last_round_active_slot_count = 0;
    fairness_last_round_task_count = 0;
    fairness_initial_pending_task_count = 0;
    fairness_last_pending_task_count = 0;
    fairness_peak_pending_task_count = 0;
    fairness_task_budget = 0;
    fairness_task_cursor = 0;
    fairness_wrap_count = 0;
    fairness_last_start_slot_index = 0;
    fairness_min_slot_task_count = 0;
    fairness_max_slot_task_count = 0;
    rebalance_policy = abi.ap_ownership_policy_round_robin;
    debt_policy = abi.ap_ownership_policy_round_robin;
    debt_peak_active_slot_count = 0;
    debt_last_round_active_slot_count = 0;
    debt_last_round_task_count = 0;
    debt_initial_pending_task_count = 0;
    debt_last_pending_task_count = 0;
    debt_peak_pending_task_count = 0;
    debt_task_budget = 0;
    debt_initial_min_slot_task_count = 0;
    debt_initial_max_slot_task_count = 0;
    admission_policy = abi.ap_ownership_policy_round_robin;
    admission_peak_active_slot_count = 0;
    admission_last_round_active_slot_count = 0;
    admission_last_round_admitted_task_count = 0;
    admission_last_round_debt_task_count = 0;
    admission_initial_pending_task_count = 0;
    admission_last_pending_task_count = 0;
    admission_peak_pending_task_count = 0;
    admission_task_budget = 0;
    admission_initial_min_slot_task_count = 0;
    admission_initial_max_slot_task_count = 0;
    aging_policy = abi.ap_ownership_policy_round_robin;
    aging_peak_active_slot_count = 0;
    aging_last_round_active_slot_count = 0;
    aging_last_round_waiting_task_count = 0;
    aging_last_round_debt_task_count = 0;
    aging_initial_pending_task_count = 0;
    aging_last_pending_task_count = 0;
    aging_peak_pending_task_count = 0;
    aging_task_budget = 0;
    aging_step_value = 0;
    aging_initial_min_slot_task_count = 0;
    aging_initial_max_slot_task_count = 0;
    fairshare_policy = abi.ap_ownership_policy_round_robin;
    fairshare_peak_active_slot_count = 0;
    fairshare_last_round_active_slot_count = 0;
    fairshare_last_round_waiting_task_count = 0;
    fairshare_last_round_debt_task_count = 0;
    fairshare_last_round_fairshare_task_count = 0;
    fairshare_initial_pending_task_count = 0;
    fairshare_last_pending_task_count = 0;
    fairshare_peak_pending_task_count = 0;
    fairshare_task_budget = 0;
    fairshare_aging_step_value = 0;
    fairshare_initial_min_slot_task_count = 0;
    fairshare_initial_max_slot_task_count = 0;
    quota_policy = abi.ap_ownership_policy_round_robin;
    quota_peak_active_slot_count = 0;
    quota_last_round_active_slot_count = 0;
    quota_last_round_waiting_task_count = 0;
    quota_last_round_debt_task_count = 0;
    quota_last_round_quota_task_count = 0;
    quota_initial_pending_task_count = 0;
    quota_last_pending_task_count = 0;
    quota_peak_pending_task_count = 0;
    quota_task_budget = 0;
    quota_aging_step_value = 0;
    quota_budget_total = 0;
    quota_initial_min_slot_task_count = 0;
    quota_initial_max_slot_task_count = 0;
pub fn resetOwnershipState() void {
    ownership_state = zeroOwnershipState();
    failover_state = zeroFailoverState();
    backfill_state = zeroBackfillState();
    resetWindowState();
    resetFairnessState();
    @memset(&ownership_entries, std.mem.zeroes(abi.BaremetalApOwnershipEntry));
    @memset(&backfill_entries, std.mem.zeroes(abi.BaremetalApBackfillEntry));
    ownership_dispatch_round_count = 0;
    ownership_policy = abi.ap_ownership_policy_round_robin;
    ownership_peak_active_slot_count = 0;
    ownership_last_round_active_slot_count = 0;
    ownership_last_round_owned_task_count = 0;
    ownership_last_round_dispatch_count = 0;
    ownership_last_round_accumulator = 0;
    ownership_last_redistributed_task_count = 0;
    ownership_last_start_slot_index = 0;
    failover_retired_slot_event_count = 0;
    failover_last_retired_slot_index = 0;
    failover_total_failed_over_task_count = 0;
    failover_last_failed_over_task_count = 0;
    backfill_last_backfilled_task_count = 0;
    backfill_total_terminated_task_count = 0;
    backfill_last_terminated_task_count = 0;
    backfill_total_round_count = 0;
    for (0..max_ap_command_slots) |slot_index| resetOwnershipSlot(slot_index);
    @memset(&OwnershipStorage.seen_task_ids, 0);
    OwnershipStorage.seen_task_count = 0;
}

pub fn resetSlotState() void {
    slot_state = zeroSlotState();
    @memset(&slot_entries, std.mem.zeroes(abi.BaremetalApSlotEntry));
    writeStateVar(sharedBootSlotIndexPtr(), 0);
    for (0..max_ap_command_slots) |slot_index| resetSlotEntry(slot_index);
    resetOwnershipState();
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
pub fn ownershipStatePtr() *const abi.BaremetalApOwnershipState {
    refreshState();
    return &ownership_state;
}

pub fn failoverStatePtr() *const abi.BaremetalApFailoverState {
    refreshState();
    return &failover_state;
}

pub fn backfillStatePtr() *const abi.BaremetalApBackfillState {
    refreshState();
    return &backfill_state;
}

pub fn windowStatePtr() *const abi.BaremetalApWindowState {
    refreshState();
    return &window_state;
}

pub fn ownershipEntryCount() u16 {
    refreshState();
    return ownership_state.exported_count;
}

pub fn ownershipEntry(index: u16) abi.BaremetalApOwnershipEntry {
    refreshState();
    if (index >= ownership_state.exported_count) return std.mem.zeroes(abi.BaremetalApOwnershipEntry);
    return ownership_entries[index];
}

pub fn backfillEntryCount() u16 {
    refreshState();
fn activeOwnershipSlots(slot_indices: *[max_ap_command_slots]u16) usize {
    var count: usize = 0;
    for (0..max_ap_command_slots) |slot_index| {
        if (readStateVar(slotStartedPtr(slot_index)) == 0) continue;
        if (readStateVar(slotHaltedPtr(slot_index)) != 0) continue;
        if (readStateVar(slotTargetApicIdPtr(slot_index)) == 0) continue;
        slot_indices[count] = @as(u16, @intCast(slot_index));
        count += 1;
    }
    return count;
}

    ownership_state = zeroOwnershipState();
    @memset(&ownership_entries, std.mem.zeroes(abi.BaremetalApOwnershipEntry));
    ownership_last_round_active_slot_count = 0;
    ownership_last_round_owned_task_count = 0;
    ownership_last_round_dispatch_count = 0;
    ownership_last_round_accumulator = 0;
    ownership_last_redistributed_task_count = 0;
    ownership_last_start_slot_index = 0;
    for (0..max_ap_command_slots) |slot_index| clearOwnershipRoundSlot(slot_index);
}

    while (index < OwnershipStorage.seen_task_count) : (index += 1) {
        if (OwnershipStorage.seen_task_ids[index] == task_id) return true;
    }
    return false;
}

fn markSeenOwnedTask(task_id: u32) void {
    if (task_id == 0 or hasSeenOwnedTask(task_id)) return;
    if (OwnershipStorage.seen_task_count >= OwnershipStorage.seen_task_ids.len) return;
    OwnershipStorage.seen_task_ids[OwnershipStorage.seen_task_count] = task_id;
    OwnershipStorage.seen_task_count += 1;
}

fn slotIndexIsActive(active_slots: []const u16, slot_index: usize) bool {
    for (active_slots) |active_slot| {
        if (@as(usize, active_slot) == slot_index) return true;
    }
    return false;
}

fn collectOwnedRunnableTasksOrdered(
    tasks: []const abi.BaremetalTask,
    policy: u8,
    ordered: *[max_owned_dispatch_entries]abi.BaremetalTask,
) OwnershipError![]const abi.BaremetalTask {
    var runnable_count: usize = 0;
    for (tasks) |task| {
        if (task.task_id == 0) continue;
        if (task.state != abi.task_state_ready and task.state != abi.task_state_running) continue;
        if (runnable_count >= ordered.len) return error.TooManyOwnedTasks;
        ordered[runnable_count] = task;
        runnable_count += 1;
    }
    if (runnable_count == 0) return error.NoReadyTask;
    switch (policy) {
        abi.ap_ownership_policy_round_robin => {},
        abi.ap_ownership_policy_priority => {
            var index: usize = 1;
            while (index < runnable_count) : (index += 1) {
                const current = ordered[index];
                var insert_index = index;
) OwnershipError!u32 {
    var active_slots: [max_ap_command_slots]u16 = undefined;
    const active_slot_count = activeOwnershipSlots(&active_slots);
    if (active_slot_count == 0) return error.ApNotStarted;

    const previous_owned_task_ids = OwnershipStorage.owned_task_ids;
    const previous_owned_task_count = OwnershipStorage.owned_task_count;
    var ordered_tasks_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    const ordered_tasks = try collectOwnedRunnableTasksOrdered(tasks, policy, &ordered_tasks_storage);
    const prior_dispatch_round_count = ownership_dispatch_round_count;
    const terminated_count = if (prior_dispatch_round_count == 0) @as(u32, 0) else countRemovedOwnedTasks(previous_owned_task_ids, previous_owned_task_count, ordered_tasks);
    ownership_policy = policy;
    ownership_dispatch_round_count +%= 1;
    const initial_slot_cursor = start_slot_offset % active_slot_count;
    ownership_last_start_slot_index = @as(u32, @intCast(initial_slot_cursor));
    ownership_last_round_active_slot_count = @as(u8, @intCast(active_slot_count));
    if (ownership_peak_active_slot_count < ownership_last_round_active_slot_count) {
        ownership_peak_active_slot_count = ownership_last_round_active_slot_count;
    }

    var slot_cursor: usize = initial_slot_cursor;
    var assigned_count: usize = 0;
    var redistributed_count: u32 = 0;
    var failed_over_count: u32 = 0;
    var backfilled_count: u32 = 0;
    for (ordered_tasks) |task| {
        const slot_index = @as(usize, active_slots[slot_cursor]);
        const owned_count = @as(usize, OwnershipStorage.owned_task_count[slot_index]);
        if (owned_count >= max_task_batch_entries) return error.TooManyOwnedTasks;

        OwnershipStorage.owned_task_ids[slot_index][owned_count] = task.task_id;
        OwnershipStorage.owned_task_count[slot_index] = @as(u32, @intCast(owned_count + 1));
        OwnershipStorage.total_owned_task_count[slot_index] +%= 1;
        OwnershipStorage.last_task_id[slot_index] = task.task_id;
        OwnershipStorage.last_priority[slot_index] = @as(u32, task.priority);
        OwnershipStorage.last_budget_ticks[slot_index] = task.budget_ticks;
        const seen_before = hasSeenOwnedTask(task.task_id);
        if (prior_dispatch_round_count != 0 and !seen_before) {
            OwnershipStorage.backfilled_task_count[slot_index] +%= 1;
            OwnershipStorage.total_backfilled_task_count[slot_index] +%= 1;
            backfilled_count +%= 1;
        }
        markSeenOwnedTask(task.task_id);
        if (previousTaskOwner(previous_owned_task_ids, previous_owned_task_count, task.task_id)) |previous_owner| {
            if (previous_owner != slot_index) {
                OwnershipStorage.redistributed_task_count[slot_index] +%= 1;
                OwnershipStorage.total_redistributed_task_count[slot_index] +%= 1;
                redistributed_count +%= 1;
                if (!slotIndexIsActive(active_slots[0..active_slot_count], previous_owner)) {
                    failed_over_count +%= 1;
                }
            }
        }
        assigned_count += 1;
        slot_cursor = (slot_cursor + 1) % active_slot_count;
    }
    ownership_last_round_owned_task_count = @as(u32, @intCast(assigned_count));
    ownership_last_redistributed_task_count = redistributed_count;
    failover_last_failed_over_task_count = failed_over_count;
    failover_total_failed_over_task_count +%= failed_over_count;
    backfill_last_backfilled_task_count = backfilled_count;
    backfill_last_terminated_task_count = terminated_count;
    backfill_total_terminated_task_count +%= terminated_count;
    if (backfilled_count != 0) backfill_total_round_count +%= 1;

    var total_accumulator: u32 = 0;
    var round_dispatch_count: u32 = 0;
    var active_slot_cursor: usize = 0;
    while (active_slot_cursor < active_slot_count) : (active_slot_cursor += 1) {
        const slot_index = @as(usize, active_slots[active_slot_cursor]);
        const owned_count = @as(usize, OwnershipStorage.owned_task_count[slot_index]);
        if (owned_count == 0) continue;
        const accumulator = try dispatchWorkBatchToApSlot(active_slots[active_slot_cursor], OwnershipStorage.owned_task_ids[slot_index][0..owned_count]);
        OwnershipStorage.dispatch_count[slot_index] +%= 1;
        OwnershipStorage.last_batch_accumulator[slot_index] = accumulator;
        OwnershipStorage.total_accumulator[slot_index] +%= accumulator;
        total_accumulator +%= accumulator;
        round_dispatch_count +%= 1;
    }
    ownership_last_round_dispatch_count = round_dispatch_count;
    ownership_last_round_accumulator = total_accumulator;
    refreshState();
    return total_accumulator;
}

pub fn dispatchOwnedSchedulerTasksRoundRobin(tasks: []const abi.BaremetalTask) OwnershipError!u32 {
    return dispatchOwnedSchedulerTasksByPolicyFromOffset(tasks, abi.ap_ownership_policy_round_robin, 0);
}

pub fn dispatchOwnedSchedulerTasksRoundRobinFromOffset(tasks: []const abi.BaremetalTask, start_slot_offset: usize) OwnershipError!u32 {
    return dispatchOwnedSchedulerTasksByPolicyFromOffset(tasks, abi.ap_ownership_policy_round_robin, start_slot_offset);
}

pub fn dispatchOwnedSchedulerTasksPriority(tasks: []const abi.BaremetalTask) OwnershipError!u32 {
    return dispatchOwnedSchedulerTasksByPolicyFromOffset(tasks, abi.ap_ownership_policy_priority, 0);
}

pub fn dispatchOwnedSchedulerTasksPriorityFromOffset(tasks: []const abi.BaremetalTask, start_slot_offset: usize) OwnershipError!u32 {
    return dispatchOwnedSchedulerTasksByPolicyFromOffset(tasks, abi.ap_ownership_policy_priority, start_slot_offset);
}

fn dispatchWindowedSchedulerTasksByPolicyFromOffset(
    tasks: []const abi.BaremetalTask,
    policy: u8,
    start_slot_offset: usize,
    task_budget: usize,
) OwnershipError!u32 {
    if (task_budget == 0) return error.InvalidWorkBatch;

    var active_slots: [max_ap_command_slots]u16 = undefined;
    const active_slot_count = activeOwnershipSlots(&active_slots);
    if (active_slot_count == 0) return error.ApNotStarted;

    var ordered_tasks_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    const ordered_tasks = try collectOwnedRunnableTasksOrdered(tasks, policy, &ordered_tasks_storage);

) OwnershipError!u32 {
    return dispatchWindowedSchedulerTasksByPolicyFromOffset(tasks, abi.ap_ownership_policy_priority, start_slot_offset, task_budget);
}

fn snapshotFairnessFromWindow(active_slots: []const u16) void {
    fairness_policy = window_policy;
    fairness_peak_active_slot_count = window_peak_active_slot_count;
    fairness_last_round_active_slot_count = window_last_round_active_slot_count;
    fairness_task_budget = window_task_budget;
    fairness_task_cursor = window_task_cursor;
    fairness_wrap_count = window_wrap_count;
    fairness_last_start_slot_index = window_last_start_slot_index;

    var min_slot_task_count: u32 = std.math.maxInt(u32);
    var max_slot_task_count: u32 = 0;
    var have_active_slot = false;
    for (active_slots) |slot| {
        const slot_index = @as(usize, slot);
        const total_drained_task_count = WindowStorage.total_window_task_count[slot_index];
        if (total_drained_task_count < min_slot_task_count) min_slot_task_count = total_drained_task_count;
        if (total_drained_task_count > max_slot_task_count) max_slot_task_count = total_drained_task_count;
        have_active_slot = true;
    }
    fairness_min_slot_task_count = if (have_active_slot) min_slot_task_count else 0;
    fairness_max_slot_task_count = max_slot_task_count;
) OwnershipError!u32 {
    if (task_budget == 0) return error.InvalidWorkBatch;

    var active_slots: [max_ap_command_slots]u16 = undefined;
    const active_slot_count = activeOwnershipSlots(&active_slots);
    if (active_slot_count == 0) return error.ApNotStarted;

    var ordered_tasks_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    const ordered_tasks = try collectOwnedRunnableTasksOrdered(tasks, abi.ap_ownership_policy_priority, &ordered_tasks_storage);

    resetWindowState();
    resetFairnessState();
    fairness_policy = abi.ap_ownership_policy_priority;
    fairness_last_round_active_slot_count = @as(u8, @intCast(active_slot_count));
    fairness_peak_active_slot_count = fairness_last_round_active_slot_count;
    fairness_initial_pending_task_count = @as(u32, @intCast(ordered_tasks.len));
    fairness_last_pending_task_count = fairness_initial_pending_task_count;
    fairness_peak_pending_task_count = fairness_initial_pending_task_count;
    fairness_task_budget = @as(u32, @intCast(task_budget));

    var total_accumulator: u32 = 0;
    var task_cursor: usize = 0;
    var round_index: usize = 0;
    while (task_cursor < ordered_tasks.len) : (round_index += 1) {
        const round_start_slot = (start_slot_offset + round_index) % active_slot_count;
        const remaining_task_count = ordered_tasks.len - task_cursor;
        const round_task_count = @min(task_budget, remaining_task_count);
) OwnershipError!u32 {
    if (task_budget == 0) return error.InvalidWorkBatch;

    var active_slots: [max_ap_command_slots]u16 = undefined;
    const active_slot_count = activeOwnershipSlots(&active_slots);
    if (active_slot_count == 0) return error.ApNotStarted;

    var ordered_tasks_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    const ordered_tasks = try collectOwnedRunnableTasksOrdered(tasks, abi.ap_ownership_policy_priority, &ordered_tasks_storage);

    rebalance_policy = abi.ap_ownership_policy_priority;
) OwnershipError!u32 {
    if (task_budget == 0) return error.InvalidWorkBatch;
    if (debt_tasks.len + admitted_tasks.len > max_owned_dispatch_entries) return error.TooManyOwnedTasks;

    var active_slots: [max_ap_command_slots]u16 = undefined;
    const active_slot_count = activeOwnershipSlots(&active_slots);
    if (active_slot_count == 0) return error.ApNotStarted;

    var combined_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    var combined_count: usize = 0;
    for (debt_tasks) |task| {
        if (task.task_id == 0) continue;
        if (task.state != abi.task_state_ready and task.state != abi.task_state_running) continue;
        combined_storage[combined_count] = task;
        combined_count += 1;
    }
    for (admitted_tasks) |task| {
        if (task.task_id == 0) continue;
        if (task.state != abi.task_state_ready and task.state != abi.task_state_running) continue;
        if (combined_count >= combined_storage.len) return error.TooManyOwnedTasks;
        combined_storage[combined_count] = task;
        combined_count += 1;
    }
    if (combined_count == 0) return error.NoReadyTask;

    var ordered_tasks_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    const ordered_tasks = try collectOwnedRunnableTasksOrdered(combined_storage[0..combined_count], abi.ap_ownership_policy_priority, &ordered_tasks_storage);

    resetAdmissionState();
    admission_policy = abi.ap_ownership_policy_priority;
    admission_last_round_active_slot_count = @as(u8, @intCast(active_slot_count));
    admission_peak_active_slot_count = admission_last_round_active_slot_count;
    admission_initial_pending_task_count = @as(u32, @intCast(ordered_tasks.len));
    admission_last_pending_task_count = admission_initial_pending_task_count;
    admission_peak_pending_task_count = admission_initial_pending_task_count;
    admission_task_budget = @as(u32, @intCast(task_budget));

    for (active_slots[0..active_slot_count]) |slot| {
        const slot_index = @as(usize, slot);
        const seed_task_count = WindowStorage.total_window_task_count[slot_index];
        AdmissionStorage.seed_task_count[slot_index] = seed_task_count;
        AdmissionStorage.final_task_count[slot_index] = seed_task_count;
    }
    snapshotAdmissionLoadRange(active_slots[0..active_slot_count], false);
    for (active_slots[0..active_slot_count]) |slot| {
        const slot_index = @as(usize, slot);
        const initial_debt = admission_initial_max_slot_task_count - AdmissionStorage.seed_task_count[slot_index];
        AdmissionStorage.initial_debt[slot_index] = initial_debt;
        AdmissionStorage.remaining_debt[slot_index] = initial_debt;
        admission_initial_total_debt +%= initial_debt;
        admission_remaining_total_debt +%= initial_debt;
    }
    snapshotAdmissionLoadRange(active_slots[0..active_slot_count], true);

    var total_accumulator: u32 = 0;
    var task_cursor: usize = 0;
    var round_index: usize = 0;
    while (task_cursor < ordered_tasks.len) : (round_index += 1) {
) OwnershipError!u32 {
    if (task_budget == 0 or aging_step == 0) return error.InvalidWorkBatch;
    if (debt_tasks.len + waiting_tasks.len > max_owned_dispatch_entries) return error.TooManyOwnedTasks;

    var active_slots: [max_ap_command_slots]u16 = undefined;
    const active_slot_count = activeOwnershipSlots(&active_slots);
    if (active_slot_count == 0) return error.ApNotStarted;

    var debt_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    var debt_count: usize = 0;
    for (debt_tasks) |task| {
        if (task.task_id == 0) continue;
        if (task.state != abi.task_state_ready and task.state != abi.task_state_running) continue;
        if (debt_count >= debt_storage.len) return error.TooManyOwnedTasks;
        debt_storage[debt_count] = task;
        debt_count += 1;
    }

    var waiting_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    var waiting_count: usize = 0;
    for (waiting_tasks) |task| {
        if (task.task_id == 0) continue;
        if (task.state != abi.task_state_ready and task.state != abi.task_state_running) continue;
        if (waiting_count >= waiting_storage.len) return error.TooManyOwnedTasks;
        waiting_storage[waiting_count] = task;
        waiting_count += 1;
    }
    if (debt_count + waiting_count == 0) return error.NoReadyTask;

    var ordered_debt_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    var ordered_waiting_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    const ordered_debt = if (debt_count == 0)
        debt_storage[0..0]
    else
        try collectOwnedRunnableTasksOrdered(debt_storage[0..debt_count], abi.ap_ownership_policy_priority, &ordered_debt_storage);
    const ordered_waiting = if (waiting_count == 0)
        waiting_storage[0..0]
    else
        try collectOwnedRunnableTasksOrdered(waiting_storage[0..waiting_count], abi.ap_ownership_policy_priority, &ordered_waiting_storage);

    var remaining_debt_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    std.mem.copyForwards(abi.BaremetalTask, remaining_debt_storage[0..ordered_debt.len], ordered_debt);
    var remaining_debt_count = ordered_debt.len;

    var remaining_waiting_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    std.mem.copyForwards(abi.BaremetalTask, remaining_waiting_storage[0..ordered_waiting.len], ordered_waiting);
    var waiting_age_rounds: [max_owned_dispatch_entries]u32 = [_]u32{0} ** max_owned_dispatch_entries;
    var remaining_waiting_count = ordered_waiting.len;

    resetAgingState();
    aging_policy = abi.ap_ownership_policy_priority;
    aging_last_round_active_slot_count = @as(u8, @intCast(active_slot_count));
    aging_peak_active_slot_count = aging_last_round_active_slot_count;
    aging_initial_pending_task_count = @as(u32, @intCast(remaining_debt_count + remaining_waiting_count));
    aging_last_pending_task_count = aging_initial_pending_task_count;
    aging_peak_pending_task_count = aging_initial_pending_task_count;
    aging_task_budget = @as(u32, @intCast(task_budget));
    aging_step_value = aging_step;

    for (active_slots[0..active_slot_count]) |slot| {
        const slot_index = @as(usize, slot);
        const seed_task_count = WindowStorage.total_window_task_count[slot_index];
        AgingStorage.seed_task_count[slot_index] = seed_task_count;
        AgingStorage.final_task_count[slot_index] = seed_task_count;
    }
    snapshotAgingLoadRange(active_slots[0..active_slot_count], false);
    for (active_slots[0..active_slot_count]) |slot| {
        const slot_index = @as(usize, slot);
        const initial_debt = aging_initial_max_slot_task_count - AgingStorage.seed_task_count[slot_index];
        AgingStorage.initial_debt[slot_index] = initial_debt;
        AgingStorage.remaining_debt[slot_index] = initial_debt;
        aging_initial_total_debt +%= initial_debt;
        aging_remaining_total_debt +%= initial_debt;
    }
    snapshotAgingLoadRange(active_slots[0..active_slot_count], true);

    var total_accumulator: u32 = 0;
    var round_index: usize = 0;
    while (remaining_debt_count != 0 or remaining_waiting_count != 0) : (round_index += 1) {
) OwnershipError!u32 {
    if (task_budget == 0 or aging_step == 0) return error.InvalidWorkBatch;
    if (debt_tasks.len + waiting_tasks.len > max_owned_dispatch_entries) return error.TooManyOwnedTasks;

    var active_slots: [max_ap_command_slots]u16 = undefined;
    const active_slot_count = activeOwnershipSlots(&active_slots);
    if (active_slot_count == 0) return error.ApNotStarted;

    var debt_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    var debt_count: usize = 0;
    for (debt_tasks) |task| {
        if (task.task_id == 0) continue;
        if (task.state != abi.task_state_ready and task.state != abi.task_state_running) continue;
        if (debt_count >= debt_storage.len) return error.TooManyOwnedTasks;
        debt_storage[debt_count] = task;
        debt_count += 1;
    }

    var waiting_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    var waiting_count: usize = 0;
    for (waiting_tasks) |task| {
        if (task.task_id == 0) continue;
        if (task.state != abi.task_state_ready and task.state != abi.task_state_running) continue;
        if (waiting_count >= waiting_storage.len) return error.TooManyOwnedTasks;
        waiting_storage[waiting_count] = task;
        waiting_count += 1;
    }
    if (debt_count + waiting_count == 0) return error.NoReadyTask;

    var ordered_debt_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    var ordered_waiting_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    const ordered_debt = if (debt_count == 0)
        debt_storage[0..0]
    else
        try collectOwnedRunnableTasksOrdered(debt_storage[0..debt_count], abi.ap_ownership_policy_priority, &ordered_debt_storage);
    const ordered_waiting = if (waiting_count == 0)
        waiting_storage[0..0]
    else
        try collectOwnedRunnableTasksOrdered(waiting_storage[0..waiting_count], abi.ap_ownership_policy_priority, &ordered_waiting_storage);

    var remaining_debt_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    std.mem.copyForwards(abi.BaremetalTask, remaining_debt_storage[0..ordered_debt.len], ordered_debt);
    var remaining_debt_count = ordered_debt.len;

    var remaining_waiting_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    std.mem.copyForwards(abi.BaremetalTask, remaining_waiting_storage[0..ordered_waiting.len], ordered_waiting);
    var waiting_age_rounds: [max_owned_dispatch_entries]u32 = [_]u32{0} ** max_owned_dispatch_entries;
    var remaining_waiting_count = ordered_waiting.len;

    resetFairshareState();
    fairshare_policy = abi.ap_ownership_policy_priority;
    fairshare_last_round_active_slot_count = @as(u8, @intCast(active_slot_count));
    fairshare_peak_active_slot_count = fairshare_last_round_active_slot_count;
    fairshare_initial_pending_task_count = @as(u32, @intCast(remaining_debt_count + remaining_waiting_count));
    fairshare_last_pending_task_count = fairshare_initial_pending_task_count;
    fairshare_peak_pending_task_count = fairshare_initial_pending_task_count;
    fairshare_task_budget = @as(u32, @intCast(task_budget));
    fairshare_aging_step_value = aging_step;

    for (active_slots[0..active_slot_count]) |slot| {
        const slot_index = @as(usize, slot);
        const seed_task_count = WindowStorage.total_window_task_count[slot_index];
        FairshareStorage.seed_task_count[slot_index] = seed_task_count;
        FairshareStorage.final_task_count[slot_index] = seed_task_count;
    }
    snapshotFairshareLoadRange(active_slots[0..active_slot_count], false);
    for (active_slots[0..active_slot_count]) |slot| {
        const slot_index = @as(usize, slot);
        const initial_debt = fairshare_initial_max_slot_task_count - FairshareStorage.seed_task_count[slot_index];
        FairshareStorage.initial_debt[slot_index] = initial_debt;
        FairshareStorage.remaining_debt[slot_index] = initial_debt;
        fairshare_initial_total_debt +%= initial_debt;
        fairshare_remaining_total_debt +%= initial_debt;
    }
    snapshotFairshareLoadRange(active_slots[0..active_slot_count], true);

    var total_accumulator: u32 = 0;
    var round_index: usize = 0;
    while (remaining_debt_count != 0 or remaining_waiting_count != 0) : (round_index += 1) {
) OwnershipError!u32 {
    if (task_budget == 0 or aging_step == 0) return error.InvalidWorkBatch;
    if (debt_tasks.len + waiting_tasks.len > max_owned_dispatch_entries) return error.TooManyOwnedTasks;

    var active_slots: [max_ap_command_slots]u16 = undefined;
    const active_slot_count = activeOwnershipSlots(&active_slots);
    if (active_slot_count == 0) return error.ApNotStarted;
    if (quotas.len != active_slot_count) return error.InvalidWorkBatch;

    var quota_budget_sum: u32 = 0;
    for (quotas) |quota_value| {
        if (quota_value == 0) return error.InvalidWorkBatch;
        quota_budget_sum +%= quota_value;
    }
    if (task_budget > quota_budget_sum) return error.InvalidWorkBatch;

    var debt_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    var debt_count: usize = 0;
    for (debt_tasks) |task| {
        if (task.task_id == 0) continue;
        if (task.state != abi.task_state_ready and task.state != abi.task_state_running) continue;
        if (debt_count >= debt_storage.len) return error.TooManyOwnedTasks;
        debt_storage[debt_count] = task;
        debt_count += 1;
    }

    var waiting_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    var waiting_count: usize = 0;
    for (waiting_tasks) |task| {
        if (task.task_id == 0) continue;
        if (task.state != abi.task_state_ready and task.state != abi.task_state_running) continue;
        if (waiting_count >= waiting_storage.len) return error.TooManyOwnedTasks;
        waiting_storage[waiting_count] = task;
        waiting_count += 1;
    }
    if (debt_count + waiting_count == 0) return error.NoReadyTask;

    var ordered_debt_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    var ordered_waiting_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    const ordered_debt = if (debt_count == 0)
        debt_storage[0..0]
    else
        try collectOwnedRunnableTasksOrdered(debt_storage[0..debt_count], abi.ap_ownership_policy_priority, &ordered_debt_storage);
    const ordered_waiting = if (waiting_count == 0)
        waiting_storage[0..0]
    else
        try collectOwnedRunnableTasksOrdered(waiting_storage[0..waiting_count], abi.ap_ownership_policy_priority, &ordered_waiting_storage);

    var remaining_debt_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    std.mem.copyForwards(abi.BaremetalTask, remaining_debt_storage[0..ordered_debt.len], ordered_debt);
    var remaining_debt_count = ordered_debt.len;

    var remaining_waiting_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    std.mem.copyForwards(abi.BaremetalTask, remaining_waiting_storage[0..ordered_waiting.len], ordered_waiting);
    var waiting_age_rounds: [max_owned_dispatch_entries]u32 = [_]u32{0} ** max_owned_dispatch_entries;
    var remaining_waiting_count = ordered_waiting.len;

    resetQuotaState();
    quota_policy = abi.ap_ownership_policy_priority;
    quota_last_round_active_slot_count = @as(u8, @intCast(active_slot_count));
    quota_peak_active_slot_count = quota_last_round_active_slot_count;
    quota_initial_pending_task_count = @as(u32, @intCast(remaining_debt_count + remaining_waiting_count));
    quota_last_pending_task_count = quota_initial_pending_task_count;
    quota_peak_pending_task_count = quota_initial_pending_task_count;
    quota_task_budget = @as(u32, @intCast(task_budget));
    quota_aging_step_value = aging_step;
    quota_budget_total = quota_budget_sum;

    for (active_slots[0..active_slot_count], 0..) |slot, active_index| {
        const slot_index = @as(usize, slot);
        const seed_task_count = WindowStorage.total_window_task_count[slot_index];
        QuotaStorage.seed_task_count[slot_index] = seed_task_count;
        QuotaStorage.final_task_count[slot_index] = seed_task_count;
        QuotaStorage.configured_quota[slot_index] = quotas[active_index];
        QuotaStorage.remaining_quota[slot_index] = quotas[active_index];
    }
    snapshotQuotaLoadRange(active_slots[0..active_slot_count], false);
    for (active_slots[0..active_slot_count]) |slot| {
        const slot_index = @as(usize, slot);
        const initial_debt = quota_initial_max_slot_task_count - QuotaStorage.seed_task_count[slot_index];
        QuotaStorage.initial_debt[slot_index] = initial_debt;
        QuotaStorage.remaining_debt[slot_index] = initial_debt;
        quota_initial_total_debt +%= initial_debt;
        quota_remaining_total_debt +%= initial_debt;
    }
    snapshotQuotaLoadRange(active_slots[0..active_slot_count], true);

    var total_accumulator: u32 = 0;
    var round_index: usize = 0;
    while (remaining_debt_count != 0 or remaining_waiting_count != 0) : (round_index += 1) {
) OwnershipError!u32 {
    if (task_budget == 0) return error.InvalidWorkBatch;

    var active_slots: [max_ap_command_slots]u16 = undefined;
    const active_slot_count = activeOwnershipSlots(&active_slots);
    if (active_slot_count == 0) return error.ApNotStarted;

    var ordered_tasks_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    const ordered_tasks = try collectOwnedRunnableTasksOrdered(tasks, abi.ap_ownership_policy_priority, &ordered_tasks_storage);

    resetDebtState();
    debt_policy = abi.ap_ownership_policy_priority;
    debt_last_round_active_slot_count = @as(u8, @intCast(active_slot_count));
    debt_peak_active_slot_count = debt_last_round_active_slot_count;
    debt_initial_pending_task_count = @as(u32, @intCast(ordered_tasks.len));
    debt_last_pending_task_count = debt_initial_pending_task_count;
    debt_peak_pending_task_count = debt_initial_pending_task_count;
    debt_task_budget = @as(u32, @intCast(task_budget));

    for (active_slots[0..active_slot_count]) |slot| {
        const slot_index = @as(usize, slot);
        const seed_task_count = WindowStorage.total_window_task_count[slot_index];
        DebtStorage.seed_task_count[slot_index] = seed_task_count;
        DebtStorage.final_task_count[slot_index] = seed_task_count;
    }
    snapshotDebtLoadRange(active_slots[0..active_slot_count], false);
    for (active_slots[0..active_slot_count]) |slot| {
        const slot_index = @as(usize, slot);
        const initial_debt = debt_initial_max_slot_task_count - DebtStorage.seed_task_count[slot_index];
        DebtStorage.initial_debt[slot_index] = initial_debt;
        DebtStorage.remaining_debt[slot_index] = initial_debt;
        debt_initial_total_debt +%= initial_debt;
        debt_remaining_total_debt +%= initial_debt;
    }
    snapshotDebtLoadRange(active_slots[0..active_slot_count], true);

    var total_accumulator: u32 = 0;
    var task_cursor: usize = 0;
    var round_index: usize = 0;
    while (task_cursor < ordered_tasks.len) : (round_index += 1) {
pub fn renderOwnershipAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [3072]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
        buffer[used..],
            ownership_state.present,
            ownership_state.policy,
            ownership_state.exported_count,
            ownership_state.active_count,
            ownership_state.peak_active_slot_count,
            ownership_state.requested_cpu_count,
            ownership_state.logical_processor_count,
            ownership_state.bsp_apic_id,
            ownership_state.total_owned_task_count,
            ownership_state.total_dispatch_count,
            ownership_state.total_accumulator,
            ownership_state.dispatch_round_count,
        },
    ) catch unreachable;
    used += head.len;
    const round = std.fmt.bufPrint(
        buffer[used..],
        "last_round_active_slot_count={d}\nlast_round_owned_task_count={d}\nlast_round_dispatch_count={d}\nlast_round_accumulator={d}\ntotal_redistributed_task_count={d}\nlast_redistributed_task_count={d}\nlast_start_slot_index={d}\n",
        .{
            ownership_state.last_round_active_slot_count,
            ownership_state.last_round_owned_task_count,
            ownership_state.last_round_dispatch_count,
            ownership_state.last_round_accumulator,
            ownership_state.total_redistributed_task_count,
            ownership_state.last_redistributed_task_count,
            ownership_state.last_start_slot_index,
        },
    ) catch unreachable;
    used += round.len;
    var entry_index: u16 = 0;
    while (entry_index < ownership_state.exported_count) : (entry_index += 1) {
        const entry = ownership_entries[entry_index];
        const line = std.fmt.bufPrint(
            buffer[used..],
                .{ entry_index, task_index, OwnershipStorage.owned_task_ids[entry.slot_index][task_index] },
            ) catch unreachable;
            used += task_line.len;
        }
    }
    return allocator.dupe(u8, buffer[0..used]);
}

pub fn renderFailoverAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    return std.fmt.allocPrint(
        allocator,
        "present={d}\npolicy={d}\nretired_slot_event_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nlast_round_active_slot_count={d}\nlast_retired_slot_index={d}\ntotal_owned_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndispatch_round_count={d}\ntotal_redistributed_task_count={d}\nlast_redistributed_task_count={d}\ntotal_failed_over_task_count={d}\nlast_failed_over_task_count={d}\n",
        .{
            failover_state.present,
            failover_state.policy,
            failover_state.retired_slot_event_count,
            failover_state.active_count,
            failover_state.peak_active_slot_count,
            failover_state.last_round_active_slot_count,
            failover_state.last_retired_slot_index,
            failover_state.total_owned_task_count,
            failover_state.total_dispatch_count,
            failover_state.total_accumulator,
            failover_state.dispatch_round_count,
            failover_state.total_redistributed_task_count,
            failover_state.last_redistributed_task_count,
            failover_state.total_failed_over_task_count,
            failover_state.last_failed_over_task_count,
        },
    );
}

pub fn renderBackfillAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [4096]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
        buffer[used..],
    ownership_state = zeroOwnershipState();
    ownership_state.present = if (state.supported != 0) 1 else 0;
    ownership_state.policy = ownership_policy;
    ownership_state.requested_cpu_count = topology.enabled_count;
    ownership_state.logical_processor_count = lapic_state.logical_processor_count;
    ownership_state.bsp_apic_id = lapic_state.current_apic_id;
    ownership_state.peak_active_slot_count = ownership_peak_active_slot_count;
    ownership_state.last_round_active_slot_count = ownership_last_round_active_slot_count;
    ownership_state.dispatch_round_count = ownership_dispatch_round_count;
    ownership_state.last_round_owned_task_count = ownership_last_round_owned_task_count;
    ownership_state.last_round_dispatch_count = ownership_last_round_dispatch_count;
    ownership_state.last_round_accumulator = ownership_last_round_accumulator;
    ownership_state.total_redistributed_task_count = 0;
    ownership_state.last_redistributed_task_count = ownership_last_redistributed_task_count;
    ownership_state.last_start_slot_index = ownership_last_start_slot_index;
    @memset(&ownership_entries, std.mem.zeroes(abi.BaremetalApOwnershipEntry));
    slot_index = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const target_apic_id = readStateVar(slotTargetApicIdPtr(slot_index));
        const started = if (readStateVar(slotStartedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const halted = if (readStateVar(slotHaltedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const owned_task_count = OwnershipStorage.owned_task_count[slot_index];
        const dispatch_count = OwnershipStorage.dispatch_count[slot_index];
        const total_owned_task_count = OwnershipStorage.total_owned_task_count[slot_index];
        const redistributed_task_count = OwnershipStorage.redistributed_task_count[slot_index];
        const total_redistributed_task_count = OwnershipStorage.total_redistributed_task_count[slot_index];
        const total_accumulator = OwnershipStorage.total_accumulator[slot_index];
        if (target_apic_id == 0 and
            owned_task_count == 0 and
            dispatch_count == 0 and
            total_owned_task_count == 0 and
            redistributed_task_count == 0 and
            total_redistributed_task_count == 0 and
            total_accumulator == 0 and
            started == 0 and
            halted == 0)
        {
            continue;
        }
        const exported_index = ownership_state.exported_count;
        ownership_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .dispatch_count = dispatch_count,
            .owned_task_count = owned_task_count,
            .total_owned_task_count = total_owned_task_count,
            .redistributed_task_count = redistributed_task_count,
            .total_redistributed_task_count = total_redistributed_task_count,
            .last_task_id = OwnershipStorage.last_task_id[slot_index],
            .last_priority = OwnershipStorage.last_priority[slot_index],
            .last_budget_ticks = OwnershipStorage.last_budget_ticks[slot_index],
            .last_batch_accumulator = OwnershipStorage.last_batch_accumulator[slot_index],
            .total_accumulator = total_accumulator,
            .started = started,
            .halted = halted,
            .slot_index = @as(u8, @intCast(slot_index)),
            .reserved0 = 0,
        };
        ownership_state.exported_count += 1;
        if (started != 0 and halted == 0) ownership_state.active_count +%= 1;
        ownership_state.total_owned_task_count +%= total_owned_task_count;
        ownership_state.total_dispatch_count +%= dispatch_count;
        ownership_state.total_accumulator +%= total_accumulator;
        ownership_state.total_redistributed_task_count +%= total_redistributed_task_count;
    }
    if (ownership_state.active_count > ownership_peak_active_slot_count) {
        ownership_peak_active_slot_count = ownership_state.active_count;
    }
    ownership_state.peak_active_slot_count = ownership_peak_active_slot_count;
    if (ownership_state.exported_count != 0) ownership_state.present = 1;

    failover_state = zeroFailoverState();
    failover_state.present = ownership_state.present;
    failover_state.policy = ownership_state.policy;
    failover_state.retired_slot_event_count = failover_retired_slot_event_count;
    failover_state.active_count = ownership_state.active_count;
    failover_state.peak_active_slot_count = ownership_peak_active_slot_count;
    failover_state.last_round_active_slot_count = ownership_last_round_active_slot_count;
    failover_state.last_retired_slot_index = failover_last_retired_slot_index;
    failover_state.total_owned_task_count = ownership_state.total_owned_task_count;
    failover_state.total_dispatch_count = ownership_state.total_dispatch_count;
    failover_state.total_accumulator = ownership_state.total_accumulator;
    failover_state.dispatch_round_count = ownership_dispatch_round_count;
    failover_state.total_redistributed_task_count = ownership_state.total_redistributed_task_count;
    failover_state.last_redistributed_task_count = ownership_last_redistributed_task_count;
    failover_state.total_failed_over_task_count = failover_total_failed_over_task_count;
    failover_state.last_failed_over_task_count = failover_last_failed_over_task_count;
    if (failover_state.retired_slot_event_count != 0) failover_state.present = 1;

    backfill_state = zeroBackfillState();
    backfill_state.present = ownership_state.present;
    backfill_state.policy = ownership_state.policy;
    backfill_state.exported_count = ownership_state.exported_count;
    backfill_state.active_count = ownership_state.active_count;
    backfill_state.peak_active_slot_count = ownership_state.peak_active_slot_count;
    backfill_state.last_round_active_slot_count = ownership_state.last_round_active_slot_count;
    backfill_state.requested_cpu_count = ownership_state.requested_cpu_count;
    backfill_state.logical_processor_count = ownership_state.logical_processor_count;
    backfill_state.bsp_apic_id = ownership_state.bsp_apic_id;
    backfill_state.total_owned_task_count = ownership_state.total_owned_task_count;
    backfill_state.total_dispatch_count = ownership_state.total_dispatch_count;
    backfill_state.total_accumulator = ownership_state.total_accumulator;
    backfill_state.dispatch_round_count = ownership_state.dispatch_round_count;
    backfill_state.total_redistributed_task_count = ownership_state.total_redistributed_task_count;
    backfill_state.last_redistributed_task_count = ownership_state.last_redistributed_task_count;
    backfill_state.last_backfilled_task_count = backfill_last_backfilled_task_count;
    backfill_state.total_terminated_task_count = backfill_total_terminated_task_count;
    backfill_state.last_terminated_task_count = backfill_last_terminated_task_count;
    backfill_state.total_backfill_round_count = backfill_total_round_count;
    backfill_state.last_start_slot_index = ownership_state.last_start_slot_index;
    @memset(&backfill_entries, std.mem.zeroes(abi.BaremetalApBackfillEntry));
    slot_index = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const ownership_entry = ownership_entries[slot_index];
        const total_backfilled_task_count = OwnershipStorage.total_backfilled_task_count[slot_index];
        backfill_entries[slot_index] = .{
            .target_apic_id = ownership_entry.target_apic_id,
            .dispatch_count = ownership_entry.dispatch_count,
            .owned_task_count = ownership_entry.owned_task_count,
            .total_owned_task_count = ownership_entry.total_owned_task_count,
            .redistributed_task_count = ownership_entry.redistributed_task_count,
            .total_redistributed_task_count = ownership_entry.total_redistributed_task_count,
            .backfilled_task_count = OwnershipStorage.backfilled_task_count[slot_index],
            .total_backfilled_task_count = total_backfilled_task_count,
            .last_task_id = ownership_entry.last_task_id,
            .last_priority = ownership_entry.last_priority,
            .last_budget_ticks = ownership_entry.last_budget_ticks,
            .last_batch_accumulator = ownership_entry.last_batch_accumulator,
            .total_accumulator = ownership_entry.total_accumulator,
            .started = ownership_entry.started,
            .halted = ownership_entry.halted,
            .slot_index = ownership_entry.slot_index,
            .reserved0 = 0,
        };
        backfill_state.total_backfilled_task_count +%= total_backfilled_task_count;
    }
    if (backfill_state.total_backfilled_task_count != 0 or backfill_state.total_terminated_task_count != 0) {
        backfill_state.present = 1;
    }

    window_state = zeroWindowState();
    window_state.present = if (state.supported != 0) 1 else 0;
    window_state.policy = window_policy;
    window_state.requested_cpu_count = topology.enabled_count;
    window_state.logical_processor_count = lapic_state.logical_processor_count;
    window_state.bsp_apic_id = lapic_state.current_apic_id;
    window_state.peak_active_slot_count = window_peak_active_slot_count;
    window_state.last_round_active_slot_count = window_last_round_active_slot_count;
    window_state.dispatch_round_count = window_dispatch_round_count;
    window_state.last_round_window_task_count = window_last_round_task_count;
    window_state.total_deferred_task_count = window_total_deferred_task_count;
    window_state.last_deferred_task_count = window_last_deferred_task_count;
    window_state.window_task_budget = window_task_budget;
    window_state.task_cursor = window_task_cursor;
    window_state.wrap_count = window_wrap_count;
    window_state.last_start_slot_index = window_last_start_slot_index;
    @memset(&window_entries, std.mem.zeroes(abi.BaremetalApWindowEntry));
    slot_index = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const target_apic_id = readStateVar(slotTargetApicIdPtr(slot_index));
        const started = if (readStateVar(slotStartedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const halted = if (readStateVar(slotHaltedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const window_task_count = WindowStorage.task_count[slot_index];
        const dispatch_count = WindowStorage.dispatch_count[slot_index];
        const total_window_task_count = WindowStorage.total_window_task_count[slot_index];
        const total_accumulator = WindowStorage.total_accumulator[slot_index];
        if (target_apic_id == 0 and
            window_task_count == 0 and
            dispatch_count == 0 and
            total_window_task_count == 0 and
            total_accumulator == 0 and
            started == 0 and
            halted == 0)
        {
            continue;
        }
    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_round_robin), snapshot.policy);
    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 1), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 5), first_entry.last_task_id);
    const ownership_render = try renderOwnershipAlloc(std.testing.allocator);
    defer std.testing.allocator.free(ownership_render);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "dispatch_round_count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].target_apic_id=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].owned_task_count=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[0]=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[1]=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[2]=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[0]=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[1]=4") != null);

    try haltApSlot(0);
    try haltApSlot(1);
    snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 0), snapshot.active_count);
}

test "i386 ap startup redistributes scheduler-owned tasks across rounds" {
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
    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 5), first_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 2), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 4), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][1]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 3), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 5), second_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 3), second_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 3), second_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 5), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 3), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 5), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][2]);

    const ownership_render = try renderOwnershipAlloc(std.testing.allocator);
    defer std.testing.allocator.free(ownership_render);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "dispatch_round_count=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_round_owned_task_count=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_round_dispatch_count=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_redistributed_task_count=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_start_slot_index=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[0]=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[1]=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[0]=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[1]=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[2]=5") != null);

    try haltApSlot(0);
    try haltApSlot(1);
    snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 0), snapshot.active_count);
    try std.testing.expectEqual(@as(u32, 10), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 30), snapshot.total_accumulator);
}

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 1), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 3), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 2), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 1), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][2]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 5), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 4), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][1]);

    const ownership_render = try renderOwnershipAlloc(std.testing.allocator);
    defer std.testing.allocator.free(ownership_render);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "policy=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[0]=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[1]=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[2]=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[0]=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[1]=4") != null);

    try haltApSlot(0);
    try haltApSlot(1);
    snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 0), snapshot.active_count);
}

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 3), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 6), first_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 5), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 4), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 5), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][2]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 3), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 2), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][1]);

    const ownership_render = try renderOwnershipAlloc(std.testing.allocator);
    defer std.testing.allocator.free(ownership_render);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "policy=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "dispatch_round_count=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_redistributed_task_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_start_slot_index=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[0]=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[1]=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[2]=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[0]=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[1]=2") != null);

    try haltApSlot(0);
    try haltApSlot(1);
    snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 0), snapshot.active_count);
    try std.testing.expectEqual(@as(u32, 10), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 30), snapshot.total_accumulator);
}

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    const third_entry = ownershipEntry(2);

    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 3), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 8), first_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 3), first_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 5), first_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 7), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 5), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 7), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][2]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 8), second_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 8), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 2), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][1]);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 3), third_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 8), third_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 5), third_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 3), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 6), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 4), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 3), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][2]);

    const ownership_render = try renderOwnershipAlloc(std.testing.allocator);
    defer std.testing.allocator.free(ownership_render);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "policy=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "active_count=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "peak_active_slot_count=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_round_active_slot_count=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "dispatch_round_count=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_owned_task_count=24") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_dispatch_count=9") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_accumulator=108") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_redistributed_task_count=14") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_redistributed_task_count=7") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_start_slot_index=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[0]=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[1]=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[2]=7") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[0]=8") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[1]=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[2].task[0]=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[2].task[1]=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[2].task[2]=3") != null);

    try haltApSlot(0);
    try haltApSlot(1);
    try haltApSlot(2);
    snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 0), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 3), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 3), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 24), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 9), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 108), snapshot.total_accumulator);
}

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    const third_entry = ownershipEntry(2);
    const fourth_entry = ownershipEntry(3);

    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 8), first_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 6), first_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 7), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 5), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 7), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][1]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 8), second_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 6), second_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 3), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 6), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 3), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][1]);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 8), third_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 6), third_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 4), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][1]);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 8), fourth_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 5), fourth_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 8), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 2), OwnershipStorage.owned_task_ids[@as(usize, fourth_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 8), OwnershipStorage.owned_task_ids[@as(usize, fourth_entry.slot_index)][1]);

    const ownership_render = try renderOwnershipAlloc(std.testing.allocator);
    defer std.testing.allocator.free(ownership_render);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "policy=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "active_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "peak_active_slot_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_round_active_slot_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "dispatch_round_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_owned_task_count=32") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_dispatch_count=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_accumulator=144") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_redistributed_task_count=23") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_redistributed_task_count=7") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_start_slot_index=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[0]=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[1]=7") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[0]=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[1]=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[2].task[0]=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[2].task[1]=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[3].task[0]=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[3].task[1]=8") != null);

    try haltApSlot(0);
    try haltApSlot(1);
    try haltApSlot(2);
    try haltApSlot(3);
    snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 0), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 32), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 144), snapshot.total_accumulator);
}

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    const third_entry = ownershipEntry(2);
    const fourth_entry = ownershipEntry(3);

    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 16), first_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 12), first_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 3), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 15), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 11), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 7), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][2]);
    try std.testing.expectEqual(@as(u32, 3), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][3]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 16), second_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 12), second_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 14), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 10), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 6), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][2]);
    try std.testing.expectEqual(@as(u32, 2), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][3]);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 16), third_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 12), third_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 13), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 9), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 5), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][2]);
    try std.testing.expectEqual(@as(u32, 1), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][3]);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 16), fourth_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 12), fourth_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 16), OwnershipStorage.owned_task_ids[@as(usize, fourth_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 12), OwnershipStorage.owned_task_ids[@as(usize, fourth_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 8), OwnershipStorage.owned_task_ids[@as(usize, fourth_entry.slot_index)][2]);
    try std.testing.expectEqual(@as(u32, 4), OwnershipStorage.owned_task_ids[@as(usize, fourth_entry.slot_index)][3]);

    const ownership_render = try renderOwnershipAlloc(std.testing.allocator);
    defer std.testing.allocator.free(ownership_render);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "policy=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "active_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "peak_active_slot_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_round_active_slot_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "dispatch_round_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_owned_task_count=64") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_dispatch_count=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_accumulator=544") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_round_owned_task_count=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_round_dispatch_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_round_accumulator=136") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_redistributed_task_count=48") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_redistributed_task_count=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_start_slot_index=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[0]=15") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[1]=11") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[2]=7") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[3]=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[0]=14") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[1]=10") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[2]=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[3]=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[2].task[0]=13") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[2].task[1]=9") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[2].task[2]=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[2].task[3]=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[3].task[0]=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[3].task[1]=12") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[3].task[2]=8") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[3].task[3]=4") != null);

    try haltApSlot(0);
    try haltApSlot(1);
    try haltApSlot(2);
    try haltApSlot(3);
    snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 0), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 64), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 16), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 544), snapshot.total_accumulator);
}

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    const third_entry = ownershipEntry(2);
    const fourth_entry = ownershipEntry(3);

    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 6), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 24), first_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 20), first_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 15), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 3), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 7), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 11), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][2]);
    try std.testing.expectEqual(@as(u32, 15), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][3]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 6), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 24), second_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 16), second_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 16), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 4), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 8), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 12), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][2]);
    try std.testing.expectEqual(@as(u32, 16), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][3]);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 6), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 24), third_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 20), third_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 13), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 5), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 9), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][2]);
    try std.testing.expectEqual(@as(u32, 13), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][3]);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 6), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 24), fourth_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 16), fourth_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 14), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 2), OwnershipStorage.owned_task_ids[@as(usize, fourth_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 6), OwnershipStorage.owned_task_ids[@as(usize, fourth_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 10), OwnershipStorage.owned_task_ids[@as(usize, fourth_entry.slot_index)][2]);
    try std.testing.expectEqual(@as(u32, 14), OwnershipStorage.owned_task_ids[@as(usize, fourth_entry.slot_index)][3]);

    const ownership_render = try renderOwnershipAlloc(std.testing.allocator);
    defer std.testing.allocator.free(ownership_render);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "dispatch_round_count=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_owned_task_count=96") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_dispatch_count=24") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_accumulator=816") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_redistributed_task_count=72") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_redistributed_task_count=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_start_slot_index=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[0]=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[0].task[3]=15") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[0]=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[1].task[3]=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[2].task[0]=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[2].task[3]=13") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[3].task[0]=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[3].task[3]=14") != null);

    try haltApSlot(0);
    try haltApSlot(1);
    try haltApSlot(2);
    try haltApSlot(3);
    snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 0), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 96), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 24), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 816), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 72), snapshot.total_redistributed_task_count);
}

    var ownership_snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), ownership_snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), ownership_snapshot.policy);
    try std.testing.expectEqual(@as(u8, 4), ownership_snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 3), ownership_snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), ownership_snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 3), ownership_snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u32, 96), ownership_snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 22), ownership_snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 816), ownership_snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 6), ownership_snapshot.dispatch_round_count);
    try std.testing.expectEqual(@as(u32, 16), ownership_snapshot.last_round_owned_task_count);
    try std.testing.expectEqual(@as(u32, 3), ownership_snapshot.last_round_dispatch_count);
    try std.testing.expectEqual(@as(u32, 136), ownership_snapshot.last_round_accumulator);
    try std.testing.expectEqual(@as(u32, 77), ownership_snapshot.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 16), ownership_snapshot.last_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 1), ownership_snapshot.last_start_slot_index);

    const failover_snapshot = failoverStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), failover_snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), failover_snapshot.policy);
    try std.testing.expectEqual(@as(u8, 1), failover_snapshot.retired_slot_event_count);
    try std.testing.expectEqual(@as(u8, 3), failover_snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), failover_snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 3), failover_snapshot.last_round_active_slot_count);
    try std.testing.expectEqual(@as(u8, 3), failover_snapshot.last_retired_slot_index);
    try std.testing.expectEqual(@as(u32, 96), failover_snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 22), failover_snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 816), failover_snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 6), failover_snapshot.dispatch_round_count);
    try std.testing.expectEqual(@as(u32, 77), failover_snapshot.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 16), failover_snapshot.last_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 4), failover_snapshot.total_failed_over_task_count);
    try std.testing.expectEqual(@as(u32, 0), failover_snapshot.last_failed_over_task_count);

    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    const third_entry = ownershipEntry(2);
    const fourth_entry = ownershipEntry(3);

    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 6), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 5), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 27), first_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 5), first_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 22), first_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 14), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 11), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 8), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][2]);
    try std.testing.expectEqual(@as(u32, 5), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][3]);
    try std.testing.expectEqual(@as(u32, 2), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][4]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 6), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 6), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 27), second_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 6), second_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 22), second_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 16), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 13), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 10), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][2]);
    try std.testing.expectEqual(@as(u32, 7), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][3]);
    try std.testing.expectEqual(@as(u32, 4), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][4]);
    try std.testing.expectEqual(@as(u32, 1), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][5]);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 6), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 5), third_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 26), third_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 5), third_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 21), third_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 3), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 15), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 12), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 9), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][2]);
    try std.testing.expectEqual(@as(u32, 6), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][3]);
    try std.testing.expectEqual(@as(u32, 3), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][4]);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 16), fourth_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 12), fourth_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.last_task_id);
    const ownership_render = try renderOwnershipAlloc(std.testing.allocator);
    defer std.testing.allocator.free(ownership_render);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "active_count=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "peak_active_slot_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_round_active_slot_count=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_owned_task_count=96") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_dispatch_count=22") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_accumulator=816") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "dispatch_round_count=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "total_redistributed_task_count=77") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_redistributed_task_count=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "last_start_slot_index=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, ownership_render, "slot[3].halted=1") != null);

    const failover_render = try renderFailoverAlloc(std.testing.allocator);
    defer std.testing.allocator.free(failover_render);
    try std.testing.expect(std.mem.indexOf(u8, failover_render, "retired_slot_event_count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, failover_render, "active_count=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, failover_render, "last_retired_slot_index=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, failover_render, "total_failed_over_task_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, failover_render, "last_failed_over_task_count=0") != null);

    try haltApSlot(2);
    try haltApSlot(1);
    try haltApSlot(0);
    ownership_snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 0), ownership_snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), ownership_snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u32, 96), ownership_snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 22), ownership_snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 816), ownership_snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 77), ownership_snapshot.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 4), failoverStatePtr().*.total_failed_over_task_count);
}

    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
