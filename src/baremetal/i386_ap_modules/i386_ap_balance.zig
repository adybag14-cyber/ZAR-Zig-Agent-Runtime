var rebalance_state: abi.BaremetalApRebalanceState = zeroRebalanceState();
var rebalance_entries: [max_ap_command_slots]abi.BaremetalApRebalanceEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApRebalanceEntry);
var debt_state: abi.BaremetalApDebtState = zeroDebtState();
var debt_entries: [max_ap_command_slots]abi.BaremetalApDebtEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApDebtEntry);
var admission_state: abi.BaremetalApAdmissionState = zeroAdmissionState();
var admission_entries: [max_ap_command_slots]abi.BaremetalApAdmissionEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApAdmissionEntry);
var aging_state: abi.BaremetalApAgingState = zeroAgingState();
var aging_entries: [max_ap_command_slots]abi.BaremetalApAgingEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApAgingEntry);
var fairshare_state: abi.BaremetalApFairshareState = zeroFairshareState();
var fairshare_entries: [max_ap_command_slots]abi.BaremetalApFairshareEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApFairshareEntry);
var quota_state: abi.BaremetalApQuotaState = zeroQuotaState();
var quota_entries: [max_ap_command_slots]abi.BaremetalApQuotaEntry = std.mem.zeroes([max_ap_command_slots]abi.BaremetalApQuotaEntry);
var fairness_task_balance_gap: u32 = 0;
var rebalance_drain_round_count: u32 = 0;
var rebalance_peak_active_slot_count: u8 = 0;
var rebalance_last_round_active_slot_count: u8 = 0;
var rebalance_last_round_task_count: u32 = 0;
var rebalance_initial_pending_task_count: u32 = 0;
var rebalance_last_pending_task_count: u32 = 0;
var rebalance_peak_pending_task_count: u32 = 0;
var rebalance_task_budget: u32 = 0;
var rebalance_initial_min_slot_task_count: u32 = 0;
var rebalance_initial_max_slot_task_count: u32 = 0;
var rebalance_initial_task_balance_gap: u32 = 0;
var rebalance_final_min_slot_task_count: u32 = 0;
var rebalance_final_max_slot_task_count: u32 = 0;
var rebalance_final_task_balance_gap: u32 = 0;
var rebalance_total_compensated_task_count: u32 = 0;
var rebalance_last_round_compensated_task_count: u32 = 0;
var rebalance_last_start_slot_index: u32 = 0;
var debt_drain_round_count: u32 = 0;
var debt_initial_task_balance_gap: u32 = 0;
var debt_final_min_slot_task_count: u32 = 0;
var debt_final_max_slot_task_count: u32 = 0;
var debt_final_task_balance_gap: u32 = 0;
var debt_initial_total_debt: u32 = 0;
var debt_remaining_total_debt: u32 = 0;
var debt_total_compensated_task_count: u32 = 0;
var debt_last_round_compensated_task_count: u32 = 0;
var debt_last_start_slot_index: u32 = 0;
var admission_drain_round_count: u32 = 0;
var admission_initial_task_balance_gap: u32 = 0;
var admission_final_min_slot_task_count: u32 = 0;
var admission_final_max_slot_task_count: u32 = 0;
var admission_final_task_balance_gap: u32 = 0;
var admission_initial_total_debt: u32 = 0;
var admission_remaining_total_debt: u32 = 0;
var admission_total_compensated_task_count: u32 = 0;
var admission_last_round_compensated_task_count: u32 = 0;
var admission_last_start_slot_index: u32 = 0;
var aging_drain_round_count: u32 = 0;
var aging_round_count: u32 = 0;
var aging_initial_task_balance_gap: u32 = 0;
var aging_final_min_slot_task_count: u32 = 0;
var aging_final_max_slot_task_count: u32 = 0;
var aging_final_task_balance_gap: u32 = 0;
var aging_initial_total_debt: u32 = 0;
var aging_remaining_total_debt: u32 = 0;
var aging_total_compensated_task_count: u32 = 0;
var aging_last_round_compensated_task_count: u32 = 0;
var aging_total_aged_task_count: u32 = 0;
var aging_last_round_aged_task_count: u32 = 0;
var aging_total_promoted_task_count: u32 = 0;
var fairshare_initial_task_balance_gap: u32 = 0;
var fairshare_final_min_slot_task_count: u32 = 0;
var fairshare_final_max_slot_task_count: u32 = 0;
var fairshare_final_task_balance_gap: u32 = 0;
var fairshare_initial_total_debt: u32 = 0;
var fairshare_remaining_total_debt: u32 = 0;
var fairshare_total_compensated_task_count: u32 = 0;
var fairshare_last_round_compensated_task_count: u32 = 0;
var fairshare_total_aged_task_count: u32 = 0;
var fairshare_last_round_aged_task_count: u32 = 0;
var fairshare_total_promoted_task_count: u32 = 0;
var fairshare_total_fairshare_task_count: u32 = 0;
var quota_initial_task_balance_gap: u32 = 0;
var quota_final_min_slot_task_count: u32 = 0;
var quota_final_max_slot_task_count: u32 = 0;
var quota_final_task_balance_gap: u32 = 0;
var quota_initial_total_debt: u32 = 0;
var quota_remaining_total_debt: u32 = 0;
var quota_total_compensated_task_count: u32 = 0;
var quota_last_round_compensated_task_count: u32 = 0;
var quota_total_aged_task_count: u32 = 0;
var quota_last_round_aged_task_count: u32 = 0;
var quota_total_promoted_task_count: u32 = 0;
var quota_total_quota_task_count: u32 = 0;
const RebalanceStorage = struct {
    var task_ids: [max_ap_command_slots][max_task_batch_entries]u32 = [_][max_task_batch_entries]u32{[_]u32{0} ** max_task_batch_entries} ** max_ap_command_slots;
    var task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var dispatch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_rebalanced_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var seed_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var final_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_task_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
        .task_balance_gap = 0,
    };
}

fn zeroRebalanceState() abi.BaremetalApRebalanceState {
    return .{
        .magic = abi.ap_rebalance_magic,
        .api_version = abi.api_version,
        .present = 0,
        .total_rebalanced_task_count = 0,
        .total_dispatch_count = 0,
        .total_accumulator = 0,
        .drain_round_count = 0,
        .last_round_rebalanced_task_count = 0,
        .initial_pending_task_count = 0,
        .last_pending_task_count = 0,
        .peak_pending_task_count = 0,
        .rebalance_task_budget = 0,
        .initial_min_slot_task_count = 0,
        .initial_max_slot_task_count = 0,
        .initial_task_balance_gap = 0,
        .final_min_slot_task_count = 0,
        .final_max_slot_task_count = 0,
        .final_task_balance_gap = 0,
        .total_compensated_task_count = 0,
        .last_round_compensated_task_count = 0,
        .last_start_slot_index = 0,
    };
}

fn zeroDebtState() abi.BaremetalApDebtState {
    return .{
        .magic = abi.ap_debt_magic,
        .api_version = abi.api_version,
        .present = 0,
        .initial_task_balance_gap = 0,
        .final_min_slot_task_count = 0,
        .final_max_slot_task_count = 0,
        .final_task_balance_gap = 0,
        .initial_total_debt = 0,
        .remaining_total_debt = 0,
        .total_compensated_task_count = 0,
        .last_round_compensated_task_count = 0,
        .last_start_slot_index = 0,
    };
}

fn zeroAdmissionState() abi.BaremetalApAdmissionState {
    return .{
        .magic = abi.ap_admission_magic,
        .api_version = abi.api_version,
        .present = 0,
        .initial_task_balance_gap = 0,
        .final_min_slot_task_count = 0,
        .final_max_slot_task_count = 0,
        .final_task_balance_gap = 0,
        .initial_total_debt = 0,
        .remaining_total_debt = 0,
        .total_compensated_task_count = 0,
        .last_round_compensated_task_count = 0,
        .last_start_slot_index = 0,
    };
}

fn zeroAgingState() abi.BaremetalApAgingState {
    return .{
        .magic = abi.ap_aging_magic,
        .api_version = abi.api_version,
        .present = 0,
        .initial_task_balance_gap = 0,
        .final_min_slot_task_count = 0,
        .final_max_slot_task_count = 0,
        .final_task_balance_gap = 0,
        .initial_total_debt = 0,
        .remaining_total_debt = 0,
        .total_compensated_task_count = 0,
        .last_round_compensated_task_count = 0,
        .total_aged_task_count = 0,
        .last_round_aged_task_count = 0,
        .total_promoted_task_count = 0,
        .initial_task_balance_gap = 0,
        .final_min_slot_task_count = 0,
        .final_max_slot_task_count = 0,
        .final_task_balance_gap = 0,
        .initial_total_debt = 0,
        .remaining_total_debt = 0,
        .total_compensated_task_count = 0,
        .last_round_compensated_task_count = 0,
        .total_aged_task_count = 0,
        .last_round_aged_task_count = 0,
        .total_promoted_task_count = 0,
        .total_fairshare_task_count = 0,
        .initial_task_balance_gap = 0,
        .final_min_slot_task_count = 0,
        .final_max_slot_task_count = 0,
        .final_task_balance_gap = 0,
        .initial_total_debt = 0,
        .remaining_total_debt = 0,
        .total_compensated_task_count = 0,
        .last_round_compensated_task_count = 0,
        .total_aged_task_count = 0,
        .last_round_aged_task_count = 0,
        .total_promoted_task_count = 0,
        .total_quota_task_count = 0,
    fairness_task_balance_gap = 0;
    for (0..max_ap_command_slots) |slot_index| resetFairnessSlot(slot_index);
}

fn resetRebalanceSlot(slot_index: usize) void {
    RebalanceStorage.task_count[slot_index] = 0;
    RebalanceStorage.dispatch_count[slot_index] = 0;
    RebalanceStorage.total_rebalanced_task_count[slot_index] = 0;
    RebalanceStorage.seed_task_count[slot_index] = 0;
    RebalanceStorage.final_task_count[slot_index] = 0;
    RebalanceStorage.last_task_id[slot_index] = 0;
    RebalanceStorage.last_budget_ticks[slot_index] = 0;
    RebalanceStorage.last_batch_accumulator[slot_index] = 0;
    RebalanceStorage.total_accumulator[slot_index] = 0;
    RebalanceStorage.compensated_task_count[slot_index] = 0;
    RebalanceStorage.total_compensated_task_count[slot_index] = 0;
    @memset(&RebalanceStorage.task_ids[slot_index], 0);
}

fn resetRebalanceState() void {
    rebalance_state = zeroRebalanceState();
    @memset(&rebalance_entries, std.mem.zeroes(abi.BaremetalApRebalanceEntry));
    rebalance_drain_round_count = 0;
    rebalance_peak_active_slot_count = 0;
    rebalance_last_round_active_slot_count = 0;
    rebalance_last_round_task_count = 0;
    rebalance_initial_pending_task_count = 0;
    rebalance_last_pending_task_count = 0;
    rebalance_peak_pending_task_count = 0;
    rebalance_task_budget = 0;
    rebalance_initial_min_slot_task_count = 0;
    rebalance_initial_max_slot_task_count = 0;
    rebalance_initial_task_balance_gap = 0;
    rebalance_final_min_slot_task_count = 0;
    rebalance_final_max_slot_task_count = 0;
    rebalance_final_task_balance_gap = 0;
    rebalance_total_compensated_task_count = 0;
    rebalance_last_round_compensated_task_count = 0;
    rebalance_last_start_slot_index = 0;
    for (0..max_ap_command_slots) |slot_index| resetRebalanceSlot(slot_index);
}

fn resetDebtSlot(slot_index: usize) void {
    DebtStorage.task_count[slot_index] = 0;
    DebtStorage.dispatch_count[slot_index] = 0;
    DebtStorage.total_debt_task_count[slot_index] = 0;
    DebtStorage.seed_task_count[slot_index] = 0;
    DebtStorage.final_task_count[slot_index] = 0;
    DebtStorage.initial_debt[slot_index] = 0;
    DebtStorage.remaining_debt[slot_index] = 0;
    DebtStorage.last_task_id[slot_index] = 0;
    debt_initial_task_balance_gap = 0;
    debt_final_min_slot_task_count = 0;
    debt_final_max_slot_task_count = 0;
    debt_final_task_balance_gap = 0;
    debt_initial_total_debt = 0;
    debt_remaining_total_debt = 0;
    debt_total_compensated_task_count = 0;
    debt_last_round_compensated_task_count = 0;
    debt_last_start_slot_index = 0;
    for (0..max_ap_command_slots) |slot_index| resetDebtSlot(slot_index);
}

fn resetAdmissionState() void {
    admission_state = zeroAdmissionState();
    @memset(&admission_entries, std.mem.zeroes(abi.BaremetalApAdmissionEntry));
    admission_drain_round_count = 0;
    admission_initial_task_balance_gap = 0;
    admission_final_min_slot_task_count = 0;
    admission_final_max_slot_task_count = 0;
    admission_final_task_balance_gap = 0;
    admission_initial_total_debt = 0;
    admission_remaining_total_debt = 0;
    admission_total_compensated_task_count = 0;
    admission_last_round_compensated_task_count = 0;
    admission_last_start_slot_index = 0;
    for (0..max_ap_command_slots) |slot_index| resetAdmissionSlot(slot_index);
}

fn resetAgingState() void {
    aging_state = zeroAgingState();
    @memset(&aging_entries, std.mem.zeroes(abi.BaremetalApAgingEntry));
    aging_drain_round_count = 0;
    aging_round_count = 0;
    aging_initial_task_balance_gap = 0;
    aging_final_min_slot_task_count = 0;
    aging_final_max_slot_task_count = 0;
    aging_final_task_balance_gap = 0;
    aging_initial_total_debt = 0;
    aging_remaining_total_debt = 0;
    aging_total_compensated_task_count = 0;
    aging_last_round_compensated_task_count = 0;
    aging_total_aged_task_count = 0;
    aging_last_round_aged_task_count = 0;
    aging_total_promoted_task_count = 0;
    fairshare_initial_task_balance_gap = 0;
    fairshare_final_min_slot_task_count = 0;
    fairshare_final_max_slot_task_count = 0;
    fairshare_final_task_balance_gap = 0;
    fairshare_initial_total_debt = 0;
    fairshare_remaining_total_debt = 0;
    fairshare_total_compensated_task_count = 0;
    fairshare_last_round_compensated_task_count = 0;
    fairshare_total_aged_task_count = 0;
    fairshare_last_round_aged_task_count = 0;
    fairshare_total_promoted_task_count = 0;
    fairshare_total_fairshare_task_count = 0;
    quota_initial_task_balance_gap = 0;
    quota_final_min_slot_task_count = 0;
    quota_final_max_slot_task_count = 0;
    quota_final_task_balance_gap = 0;
    quota_initial_total_debt = 0;
    quota_remaining_total_debt = 0;
    quota_total_compensated_task_count = 0;
    quota_last_round_compensated_task_count = 0;
    quota_total_aged_task_count = 0;
    quota_last_round_aged_task_count = 0;
    quota_total_promoted_task_count = 0;
    quota_total_quota_task_count = 0;
    resetRebalanceState();
    resetDebtState();
    resetAdmissionState();
    resetAgingState();
    resetFairshareState();
    resetQuotaState();
pub fn rebalanceStatePtr() *const abi.BaremetalApRebalanceState {
    refreshState();
    return &rebalance_state;
}

pub fn rebalanceEntryCount() u16 {
    refreshState();
    return rebalance_state.exported_count;
}

pub fn rebalanceEntry(index: u16) abi.BaremetalApRebalanceEntry {
    refreshState();
    if (index >= rebalance_state.exported_count) return std.mem.zeroes(abi.BaremetalApRebalanceEntry);
    return rebalance_entries[index];
}

pub fn debtStatePtr() *const abi.BaremetalApDebtState {
    refreshState();
    return &debt_state;
}

pub fn debtEntryCount() u16 {
    refreshState();
    fairness_task_balance_gap = if (have_active_slot) max_slot_task_count - fairness_min_slot_task_count else 0;

    for (0..max_ap_command_slots) |slot_index| {
        FairnessStorage.task_count[slot_index] = WindowStorage.task_count[slot_index];
        FairnessStorage.dispatch_count[slot_index] = WindowStorage.dispatch_count[slot_index];
        FairnessStorage.total_drained_task_count[slot_index] = WindowStorage.total_window_task_count[slot_index];
        FairnessStorage.total_accumulator[slot_index] = WindowStorage.total_accumulator[slot_index];
        if (WindowStorage.task_count[slot_index] != 0) {
            FairnessStorage.last_task_id[slot_index] = WindowStorage.last_task_id[slot_index];
        RebalanceStorage.task_count[slot_index] = 0;
        RebalanceStorage.compensated_task_count[slot_index] = 0;
        @memset(&RebalanceStorage.task_ids[slot_index], 0);
    }
}

fn snapshotRebalanceLoadRange(active_slots: []const u16, final: bool) void {
    var min_slot_task_count: u32 = std.math.maxInt(u32);
    var max_slot_task_count: u32 = 0;
    var have_active_slot = false;
    for (active_slots) |slot| {
        const slot_index = @as(usize, slot);
        const load = if (final) RebalanceStorage.final_task_count[slot_index] else RebalanceStorage.seed_task_count[slot_index];
        if (load < min_slot_task_count) min_slot_task_count = load;
        if (load > max_slot_task_count) max_slot_task_count = load;
        have_active_slot = true;
    }
    const min_value = if (have_active_slot) min_slot_task_count else 0;
    const gap_value = if (have_active_slot) max_slot_task_count - min_value else 0;
    if (final) {
        rebalance_final_min_slot_task_count = min_value;
        rebalance_final_max_slot_task_count = max_slot_task_count;
        rebalance_final_task_balance_gap = gap_value;
    } else {
        rebalance_initial_min_slot_task_count = min_value;
        rebalance_initial_max_slot_task_count = max_slot_task_count;
        rebalance_initial_task_balance_gap = gap_value;
    }
}

fn selectLeastLoadedRebalanceSlot(active_slots: []const u16, start_offset: usize) u16 {
    var best_slot = active_slots[start_offset % active_slots.len];
    var best_load = RebalanceStorage.final_task_count[@as(usize, best_slot)];
    var offset: usize = 1;
    while (offset < active_slots.len) : (offset += 1) {
        const slot = active_slots[(start_offset + offset) % active_slots.len];
        const load = RebalanceStorage.final_task_count[@as(usize, slot)];
        if (load < best_load) {
            best_slot = slot;
            best_load = load;
        }
    }
    return best_slot;
}

    resetRebalanceState();
    rebalance_last_round_active_slot_count = @as(u8, @intCast(active_slot_count));
    rebalance_peak_active_slot_count = rebalance_last_round_active_slot_count;
    rebalance_initial_pending_task_count = @as(u32, @intCast(ordered_tasks.len));
    rebalance_last_pending_task_count = rebalance_initial_pending_task_count;
    rebalance_peak_pending_task_count = rebalance_initial_pending_task_count;
    rebalance_task_budget = @as(u32, @intCast(task_budget));

    for (active_slots[0..active_slot_count]) |slot| {
        const slot_index = @as(usize, slot);
        const seed_task_count = WindowStorage.total_window_task_count[slot_index];
        RebalanceStorage.seed_task_count[slot_index] = seed_task_count;
        RebalanceStorage.final_task_count[slot_index] = seed_task_count;
    }
    snapshotRebalanceLoadRange(active_slots[0..active_slot_count], false);
    snapshotRebalanceLoadRange(active_slots[0..active_slot_count], true);

    var total_accumulator: u32 = 0;
    var task_cursor: usize = 0;
    var round_index: usize = 0;
    while (task_cursor < ordered_tasks.len) : (round_index += 1) {
        rebalance_drain_round_count +%= 1;
        rebalance_last_round_task_count = @as(u32, @intCast(round_task_count));
        rebalance_last_start_slot_index = @as(u32, @intCast(round_start_slot));
        rebalance_last_round_compensated_task_count = 0;

        for (selected_tasks, 0..) |task, task_index| {
            const slot = selectLeastLoadedRebalanceSlot(active_slots[0..active_slot_count], round_start_slot + task_index);
            const slot_index = @as(usize, slot);
            const current_count = @as(usize, RebalanceStorage.task_count[slot_index]);
            if (current_count >= max_task_batch_entries) return error.TooManyOwnedTasks;
            const load_before = RebalanceStorage.final_task_count[slot_index];
            RebalanceStorage.task_ids[slot_index][current_count] = task.task_id;
            RebalanceStorage.task_count[slot_index] = @as(u32, @intCast(current_count + 1));
            RebalanceStorage.total_rebalanced_task_count[slot_index] +%= 1;
            RebalanceStorage.final_task_count[slot_index] +%= 1;
            RebalanceStorage.last_task_id[slot_index] = task.task_id;
            RebalanceStorage.last_budget_ticks[slot_index] = task.budget_ticks;
            if (load_before < rebalance_initial_max_slot_task_count) {
                RebalanceStorage.compensated_task_count[slot_index] +%= 1;
                RebalanceStorage.total_compensated_task_count[slot_index] +%= 1;
                rebalance_total_compensated_task_count +%= 1;
                rebalance_last_round_compensated_task_count +%= 1;
            }
        }

        var round_accumulator: u32 = 0;
        for (active_slots[0..active_slot_count]) |slot| {
            const slot_index = @as(usize, slot);
            const owned_count = @as(usize, RebalanceStorage.task_count[slot_index]);
            if (owned_count == 0) continue;
            const accumulator = try dispatchWorkBatchToApSlot(slot, RebalanceStorage.task_ids[slot_index][0..owned_count]);
            RebalanceStorage.dispatch_count[slot_index] +%= 1;
            RebalanceStorage.last_batch_accumulator[slot_index] = accumulator;
            RebalanceStorage.total_accumulator[slot_index] +%= accumulator;
            round_accumulator +%= accumulator;
        }

        total_accumulator +%= round_accumulator;
        task_cursor += round_task_count;
        rebalance_last_pending_task_count = @as(u32, @intCast(ordered_tasks.len - task_cursor));
        snapshotRebalanceLoadRange(active_slots[0..active_slot_count], true);
    }

    snapshotRebalanceLoadRange(active_slots[0..active_slot_count], true);
    refreshState();
    return total_accumulator;
}

        debt_final_task_balance_gap = gap_value;
    } else {
        debt_initial_min_slot_task_count = min_value;
        debt_initial_max_slot_task_count = max_slot_task_count;
        debt_initial_task_balance_gap = gap_value;
    }
}

fn selectHighestDebtSlot(active_slots: []const u16, start_offset: usize) u16 {
    var best_slot = active_slots[start_offset % active_slots.len];
    var best_debt = DebtStorage.remaining_debt[@as(usize, best_slot)];
    var best_load = DebtStorage.final_task_count[@as(usize, best_slot)];
    var offset: usize = 1;
    while (offset < active_slots.len) : (offset += 1) {
        const slot = active_slots[(start_offset + offset) % active_slots.len];
        const slot_index = @as(usize, slot);
        const debt = DebtStorage.remaining_debt[slot_index];
        const load = DebtStorage.final_task_count[slot_index];
        if (debt > best_debt or (debt == best_debt and load < best_load)) {
            best_slot = slot;
            best_debt = debt;
            best_load = load;
        }
    }
    return best_slot;
}

        admission_final_task_balance_gap = gap_value;
    } else {
        admission_initial_min_slot_task_count = min_value;
        admission_initial_max_slot_task_count = max_slot_task_count;
        admission_initial_task_balance_gap = gap_value;
    }
}

fn selectHighestAdmissionDebtSlot(active_slots: []const u16, start_offset: usize) u16 {
    var best_slot = active_slots[start_offset % active_slots.len];
    var best_debt = AdmissionStorage.remaining_debt[@as(usize, best_slot)];
    var best_load = AdmissionStorage.final_task_count[@as(usize, best_slot)];
    var offset: usize = 1;
    while (offset < active_slots.len) : (offset += 1) {
        const slot = active_slots[(start_offset + offset) % active_slots.len];
        const slot_index = @as(usize, slot);
        const debt = AdmissionStorage.remaining_debt[slot_index];
        const load = AdmissionStorage.final_task_count[slot_index];
        if (debt > best_debt or (debt == best_debt and load < best_load)) {
            best_slot = slot;
            best_debt = debt;
            best_load = load;
        }
    }
    return best_slot;
}

fn taskSliceContainsTaskId(tasks: []const abi.BaremetalTask, task_id: u32) bool {
    for (tasks) |task| {
        if (task.task_id == task_id) return true;
    }
    return false;
}

const AgingCandidateKind = enum(u8) {
    debt = 0,
    waiting = 1,
};

const AgingCandidate = struct {
    task: abi.BaremetalTask,
        aging_final_task_balance_gap = gap_value;
    } else {
        aging_initial_min_slot_task_count = min_value;
        aging_initial_max_slot_task_count = max_slot_task_count;
        aging_initial_task_balance_gap = gap_value;
    }
}

fn selectHighestAgingDebtSlot(active_slots: []const u16, start_offset: usize) u16 {
    var best_slot = active_slots[start_offset % active_slots.len];
    var best_debt = AgingStorage.remaining_debt[@as(usize, best_slot)];
    var best_load = AgingStorage.final_task_count[@as(usize, best_slot)];
    var offset: usize = 1;
    while (offset < active_slots.len) : (offset += 1) {
        const slot = active_slots[(start_offset + offset) % active_slots.len];
        const slot_index = @as(usize, slot);
        const debt = AgingStorage.remaining_debt[slot_index];
        const load = AgingStorage.final_task_count[slot_index];
        if (debt > best_debt or (debt == best_debt and load < best_load)) {
            best_slot = slot;
            best_debt = debt;
            best_load = load;
        }
    }
    return best_slot;
}

fn containsAgingCandidateTaskId(candidates: []const AgingCandidate, task_id: u32) bool {
    for (candidates) |candidate| {
        if (candidate.task.task_id == task_id) return true;
    }
    return false;
}

fn sortAgingCandidates(candidates: []AgingCandidate) void {
    var index: usize = 1;
    while (index < candidates.len) : (index += 1) {
        const current = candidates[index];
        var insert_index = index;
        while (insert_index > 0) : (insert_index -= 1) {
            const previous = candidates[insert_index - 1];
        fairshare_final_task_balance_gap = gap_value;
    } else {
        fairshare_initial_min_slot_task_count = min_value;
        fairshare_initial_max_slot_task_count = max_slot_task_count;
        fairshare_initial_task_balance_gap = gap_value;
    }
}

fn selectHighestFairshareDebtSlot(active_slots: []const u16, start_offset: usize) u16 {
    var best_slot = active_slots[start_offset % active_slots.len];
    var best_debt = FairshareStorage.remaining_debt[@as(usize, best_slot)];
    var best_load = FairshareStorage.final_task_count[@as(usize, best_slot)];
    var best_waiting = FairshareStorage.total_waiting_task_count[@as(usize, best_slot)];
    var offset: usize = 1;
    while (offset < active_slots.len) : (offset += 1) {
        const slot = active_slots[(start_offset + offset) % active_slots.len];
        const slot_index = @as(usize, slot);
        const debt = FairshareStorage.remaining_debt[slot_index];
        const load = FairshareStorage.final_task_count[slot_index];
        const waiting = FairshareStorage.total_waiting_task_count[slot_index];
        if (debt > best_debt or
            (debt == best_debt and load < best_load) or
            (debt == best_debt and load == best_load and waiting < best_waiting))
        {
            best_slot = slot;
            best_debt = debt;
            best_load = load;
            best_waiting = waiting;
        }
    }
    return best_slot;
}

        quota_final_task_balance_gap = gap_value;
    } else {
        quota_initial_min_slot_task_count = min_value;
        quota_initial_max_slot_task_count = max_slot_task_count;
        quota_initial_task_balance_gap = gap_value;
    }
}

fn selectHighestQuotaDebtSlot(active_slots: []const u16, start_offset: usize) u16 {
    var best_slot = active_slots[start_offset % active_slots.len];
    var best_debt = QuotaStorage.remaining_debt[@as(usize, best_slot)];
    var best_load = QuotaStorage.final_task_count[@as(usize, best_slot)];
    var best_waiting = QuotaStorage.total_waiting_task_count[@as(usize, best_slot)];
    var offset: usize = 1;
    while (offset < active_slots.len) : (offset += 1) {
        const slot = active_slots[(start_offset + offset) % active_slots.len];
        const slot_index = @as(usize, slot);
        const debt = QuotaStorage.remaining_debt[slot_index];
        const load = QuotaStorage.final_task_count[slot_index];
        const waiting = QuotaStorage.total_waiting_task_count[slot_index];
        if (debt > best_debt or
            (debt == best_debt and load < best_load) or
            (debt == best_debt and load == best_load and waiting < best_waiting))
        {
            best_slot = slot;
            best_debt = debt;
            best_load = load;
            best_waiting = waiting;
        }
    }
    return best_slot;
}

fn selectHighestQuotaSlot(active_slots: []const u16, start_offset: usize) u16 {
    var best_slot = active_slots[start_offset % active_slots.len];
    var best_quota = QuotaStorage.remaining_quota[@as(usize, best_slot)];
    var best_load = QuotaStorage.final_task_count[@as(usize, best_slot)];
    var best_waiting = QuotaStorage.total_waiting_task_count[@as(usize, best_slot)];
    var offset: usize = 1;
    while (offset < active_slots.len) : (offset += 1) {
        const slot = active_slots[(start_offset + offset) % active_slots.len];
        const slot_index = @as(usize, slot);
        const quota = QuotaStorage.remaining_quota[slot_index];
        const load = QuotaStorage.final_task_count[slot_index];
        const waiting = QuotaStorage.total_waiting_task_count[slot_index];
        if (quota > best_quota or
            (quota == best_quota and load < best_load) or
            (quota == best_quota and load == best_load and waiting < best_waiting))
        {
            best_slot = slot;
            best_quota = quota;
            best_load = load;
            best_waiting = waiting;
        }
    }
    return best_slot;
}

        "last_round_drained_task_count={d}\ninitial_pending_task_count={d}\nlast_pending_task_count={d}\npeak_pending_task_count={d}\ndrain_task_budget={d}\nfinal_task_cursor={d}\nwrap_count={d}\nlast_start_slot_index={d}\nmin_slot_task_count={d}\nmax_slot_task_count={d}\ntask_balance_gap={d}\n",
        .{
            fairness_state.last_round_drained_task_count,
            fairness_state.initial_pending_task_count,
            fairness_state.last_pending_task_count,
            fairness_state.peak_pending_task_count,
            fairness_state.drain_task_budget,
            fairness_state.final_task_cursor,
            fairness_state.wrap_count,
            fairness_state.last_start_slot_index,
            fairness_state.min_slot_task_count,
            fairness_state.max_slot_task_count,
            fairness_state.task_balance_gap,
        },
    ) catch unreachable;
    used += tail.len;
    var entry_index: u16 = 0;
pub fn renderRebalanceAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [4096]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
        buffer[used..],
        "present={d}\npolicy={d}\nexported_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nlast_round_active_slot_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_rebalanced_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndrain_round_count={d}\n",
        .{
            rebalance_state.present,
            rebalance_state.policy,
            rebalance_state.exported_count,
            rebalance_state.active_count,
            rebalance_state.peak_active_slot_count,
            rebalance_state.last_round_active_slot_count,
            rebalance_state.requested_cpu_count,
            rebalance_state.logical_processor_count,
            rebalance_state.bsp_apic_id,
            rebalance_state.total_rebalanced_task_count,
            rebalance_state.total_dispatch_count,
            rebalance_state.total_accumulator,
            rebalance_state.drain_round_count,
        },
    ) catch unreachable;
    used += head.len;
    const tail = std.fmt.bufPrint(
        buffer[used..],
        "last_round_rebalanced_task_count={d}\ninitial_pending_task_count={d}\nlast_pending_task_count={d}\npeak_pending_task_count={d}\nrebalance_task_budget={d}\ninitial_min_slot_task_count={d}\ninitial_max_slot_task_count={d}\ninitial_task_balance_gap={d}\nfinal_min_slot_task_count={d}\nfinal_max_slot_task_count={d}\nfinal_task_balance_gap={d}\ntotal_compensated_task_count={d}\nlast_round_compensated_task_count={d}\nlast_start_slot_index={d}\n",
        .{
            rebalance_state.last_round_rebalanced_task_count,
            rebalance_state.initial_pending_task_count,
            rebalance_state.last_pending_task_count,
            rebalance_state.peak_pending_task_count,
            rebalance_state.rebalance_task_budget,
            rebalance_state.initial_min_slot_task_count,
            rebalance_state.initial_max_slot_task_count,
            rebalance_state.initial_task_balance_gap,
            rebalance_state.final_min_slot_task_count,
            rebalance_state.final_max_slot_task_count,
            rebalance_state.final_task_balance_gap,
            rebalance_state.total_compensated_task_count,
            rebalance_state.last_round_compensated_task_count,
            rebalance_state.last_start_slot_index,
        },
    ) catch unreachable;
    used += tail.len;
    var entry_index: u16 = 0;
    while (entry_index < rebalance_state.exported_count) : (entry_index += 1) {
        const entry = rebalance_entries[entry_index];
        const line = std.fmt.bufPrint(
            buffer[used..],
                entry_index, entry.rebalanced_task_count,
                entry_index, entry.total_rebalanced_task_count,
                entry_index, entry.seed_task_count,
                entry_index, entry.final_task_count,
                entry_index, entry.last_task_id,
        const task_count = @min(@as(usize, @intCast(entry.rebalanced_task_count)), max_task_batch_entries);
        for (0..task_count) |task_index| {
            const task_line = std.fmt.bufPrint(
                buffer[used..],
                "slot[{d}].task[{d}]={d}\n",
                .{ entry_index, task_index, RebalanceStorage.task_ids[entry.slot_index][task_index] },
            ) catch unreachable;
            used += task_line.len;
        }
    }
    return allocator.dupe(u8, buffer[0..used]);
}

pub fn renderDebtAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [4096]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
        buffer[used..],
        "last_round_debt_task_count={d}\ninitial_pending_task_count={d}\nlast_pending_task_count={d}\npeak_pending_task_count={d}\ndebt_task_budget={d}\ninitial_min_slot_task_count={d}\ninitial_max_slot_task_count={d}\ninitial_task_balance_gap={d}\nfinal_min_slot_task_count={d}\nfinal_max_slot_task_count={d}\nfinal_task_balance_gap={d}\ninitial_total_debt={d}\nremaining_total_debt={d}\ntotal_compensated_task_count={d}\nlast_round_compensated_task_count={d}\nlast_start_slot_index={d}\n",
        .{
            debt_state.last_round_debt_task_count,
            debt_state.initial_pending_task_count,
            debt_state.last_pending_task_count,
            debt_state.peak_pending_task_count,
            debt_state.debt_task_budget,
            debt_state.initial_min_slot_task_count,
            debt_state.initial_max_slot_task_count,
            debt_state.initial_task_balance_gap,
            debt_state.final_min_slot_task_count,
            debt_state.final_max_slot_task_count,
            debt_state.final_task_balance_gap,
            debt_state.initial_total_debt,
            debt_state.remaining_total_debt,
            debt_state.total_compensated_task_count,
            debt_state.last_round_compensated_task_count,
            debt_state.last_start_slot_index,
        },
    ) catch unreachable;
    used += tail.len;
    var entry_index: u16 = 0;
        "last_round_admitted_task_count={d}\nlast_round_debt_task_count={d}\ninitial_pending_task_count={d}\nlast_pending_task_count={d}\npeak_pending_task_count={d}\ntask_budget={d}\ninitial_min_slot_task_count={d}\ninitial_max_slot_task_count={d}\ninitial_task_balance_gap={d}\nfinal_min_slot_task_count={d}\nfinal_max_slot_task_count={d}\nfinal_task_balance_gap={d}\ninitial_total_debt={d}\nremaining_total_debt={d}\ntotal_compensated_task_count={d}\nlast_round_compensated_task_count={d}\nlast_start_slot_index={d}\n",
        .{
            admission_state.last_round_admitted_task_count,
            admission_state.last_round_debt_task_count,
            admission_state.initial_pending_task_count,
            admission_state.last_pending_task_count,
            admission_state.peak_pending_task_count,
            admission_state.task_budget,
            admission_state.initial_min_slot_task_count,
            admission_state.initial_max_slot_task_count,
            admission_state.initial_task_balance_gap,
            admission_state.final_min_slot_task_count,
            admission_state.final_max_slot_task_count,
            admission_state.final_task_balance_gap,
            admission_state.initial_total_debt,
            admission_state.remaining_total_debt,
            admission_state.total_compensated_task_count,
            admission_state.last_round_compensated_task_count,
            admission_state.last_start_slot_index,
        },
    ) catch unreachable;
    used += tail.len;
    var entry_index: u16 = 0;
            aging_state.initial_task_balance_gap,
            aging_state.final_min_slot_task_count,
            aging_state.final_max_slot_task_count,
            aging_state.final_task_balance_gap,
            aging_state.initial_total_debt,
            aging_state.remaining_total_debt,
            aging_state.total_compensated_task_count,
            aging_state.last_round_compensated_task_count,
            aging_state.total_aged_task_count,
            aging_state.last_round_aged_task_count,
            aging_state.total_promoted_task_count,
            fairshare_state.initial_task_balance_gap,
            fairshare_state.final_min_slot_task_count,
            fairshare_state.final_max_slot_task_count,
            fairshare_state.final_task_balance_gap,
            fairshare_state.initial_total_debt,
            fairshare_state.remaining_total_debt,
            fairshare_state.total_compensated_task_count,
            fairshare_state.last_round_compensated_task_count,
            fairshare_state.total_aged_task_count,
            fairshare_state.last_round_aged_task_count,
            fairshare_state.total_promoted_task_count,
            fairshare_state.total_fairshare_task_count,
            quota_state.initial_task_balance_gap,
            quota_state.final_min_slot_task_count,
            quota_state.final_max_slot_task_count,
            quota_state.final_task_balance_gap,
            quota_state.initial_total_debt,
            quota_state.remaining_total_debt,
            quota_state.total_compensated_task_count,
            quota_state.last_round_compensated_task_count,
            quota_state.total_aged_task_count,
            quota_state.last_round_aged_task_count,
            quota_state.total_promoted_task_count,
            quota_state.total_quota_task_count,
    fairness_state.task_balance_gap = fairness_task_balance_gap;
    @memset(&fairness_entries, std.mem.zeroes(abi.BaremetalApFairnessEntry));
    slot_index = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const target_apic_id = readStateVar(slotTargetApicIdPtr(slot_index));
        const started = if (readStateVar(slotStartedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const halted = if (readStateVar(slotHaltedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const drained_task_count = FairnessStorage.task_count[slot_index];
        const dispatch_count = FairnessStorage.dispatch_count[slot_index];
        const total_drained_task_count = FairnessStorage.total_drained_task_count[slot_index];
        const total_accumulator = FairnessStorage.total_accumulator[slot_index];
        if (target_apic_id == 0 and
            drained_task_count == 0 and
            dispatch_count == 0 and
            total_drained_task_count == 0 and
            total_accumulator == 0 and
            started == 0 and
            halted == 0)
        {
            continue;
        }
    rebalance_state = zeroRebalanceState();
    rebalance_state.present = if (state.supported != 0) 1 else 0;
    rebalance_state.policy = rebalance_policy;
    rebalance_state.requested_cpu_count = topology.enabled_count;
    rebalance_state.logical_processor_count = lapic_state.logical_processor_count;
    rebalance_state.bsp_apic_id = lapic_state.current_apic_id;
    rebalance_state.peak_active_slot_count = rebalance_peak_active_slot_count;
    rebalance_state.last_round_active_slot_count = rebalance_last_round_active_slot_count;
    rebalance_state.drain_round_count = rebalance_drain_round_count;
    rebalance_state.last_round_rebalanced_task_count = rebalance_last_round_task_count;
    rebalance_state.initial_pending_task_count = rebalance_initial_pending_task_count;
    rebalance_state.last_pending_task_count = rebalance_last_pending_task_count;
    rebalance_state.peak_pending_task_count = rebalance_peak_pending_task_count;
    rebalance_state.rebalance_task_budget = rebalance_task_budget;
    rebalance_state.initial_min_slot_task_count = rebalance_initial_min_slot_task_count;
    rebalance_state.initial_max_slot_task_count = rebalance_initial_max_slot_task_count;
    rebalance_state.initial_task_balance_gap = rebalance_initial_task_balance_gap;
    rebalance_state.final_min_slot_task_count = rebalance_final_min_slot_task_count;
    rebalance_state.final_max_slot_task_count = rebalance_final_max_slot_task_count;
    rebalance_state.final_task_balance_gap = rebalance_final_task_balance_gap;
    rebalance_state.total_compensated_task_count = rebalance_total_compensated_task_count;
    rebalance_state.last_round_compensated_task_count = rebalance_last_round_compensated_task_count;
    rebalance_state.last_start_slot_index = rebalance_last_start_slot_index;
    @memset(&rebalance_entries, std.mem.zeroes(abi.BaremetalApRebalanceEntry));
    slot_index = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const target_apic_id = readStateVar(slotTargetApicIdPtr(slot_index));
        const started = if (readStateVar(slotStartedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const halted = if (readStateVar(slotHaltedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const rebalanced_task_count = RebalanceStorage.task_count[slot_index];
        const total_rebalanced_task_count = RebalanceStorage.total_rebalanced_task_count[slot_index];
        const seed_task_count = RebalanceStorage.seed_task_count[slot_index];
        const final_task_count = RebalanceStorage.final_task_count[slot_index];
        const total_accumulator = RebalanceStorage.total_accumulator[slot_index];
        const total_compensated_task_count = RebalanceStorage.total_compensated_task_count[slot_index];
        if (target_apic_id == 0 and
            rebalanced_task_count == 0 and
            total_rebalanced_task_count == 0 and
            seed_task_count == 0 and
            final_task_count == 0 and
            total_accumulator == 0 and
            total_compensated_task_count == 0 and
            started == 0 and
            halted == 0)
        {
            continue;
        }
        const dispatch_count = RebalanceStorage.dispatch_count[slot_index];
        const exported_index = rebalance_state.exported_count;
        rebalance_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .dispatch_count = dispatch_count,
            .rebalanced_task_count = rebalanced_task_count,
            .total_rebalanced_task_count = total_rebalanced_task_count,
            .seed_task_count = seed_task_count,
            .final_task_count = final_task_count,
            .last_task_id = RebalanceStorage.last_task_id[slot_index],
            .last_budget_ticks = RebalanceStorage.last_budget_ticks[slot_index],
            .last_batch_accumulator = RebalanceStorage.last_batch_accumulator[slot_index],
            .total_accumulator = total_accumulator,
            .compensated_task_count = RebalanceStorage.compensated_task_count[slot_index],
            .total_compensated_task_count = total_compensated_task_count,
            .started = started,
            .halted = halted,
            .slot_index = @as(u8, @intCast(slot_index)),
            .reserved0 = 0,
        };
        rebalance_state.exported_count += 1;
        if (started != 0 and halted == 0) rebalance_state.active_count +%= 1;
        rebalance_state.total_rebalanced_task_count +%= total_rebalanced_task_count;
        rebalance_state.total_dispatch_count +%= dispatch_count;
        rebalance_state.total_accumulator +%= total_accumulator;
    }
    if (rebalance_state.active_count > rebalance_peak_active_slot_count) {
        rebalance_peak_active_slot_count = rebalance_state.active_count;
    }
    rebalance_state.peak_active_slot_count = rebalance_peak_active_slot_count;
    if (rebalance_state.exported_count != 0 or rebalance_state.drain_round_count != 0) {
        rebalance_state.present = 1;
    }

    debt_state = zeroDebtState();
    debt_state.present = if (state.supported != 0) 1 else 0;
    debt_state.policy = debt_policy;
    debt_state.requested_cpu_count = topology.enabled_count;
    debt_state.logical_processor_count = lapic_state.logical_processor_count;
    debt_state.bsp_apic_id = lapic_state.current_apic_id;
    debt_state.peak_active_slot_count = debt_peak_active_slot_count;
    debt_state.last_round_active_slot_count = debt_last_round_active_slot_count;
    debt_state.drain_round_count = debt_drain_round_count;
    debt_state.last_round_debt_task_count = debt_last_round_task_count;
    debt_state.initial_pending_task_count = debt_initial_pending_task_count;
    debt_state.last_pending_task_count = debt_last_pending_task_count;
    debt_state.peak_pending_task_count = debt_peak_pending_task_count;
    debt_state.debt_task_budget = debt_task_budget;
    debt_state.initial_min_slot_task_count = debt_initial_min_slot_task_count;
    debt_state.initial_max_slot_task_count = debt_initial_max_slot_task_count;
    debt_state.initial_task_balance_gap = debt_initial_task_balance_gap;
    debt_state.final_min_slot_task_count = debt_final_min_slot_task_count;
    debt_state.final_max_slot_task_count = debt_final_max_slot_task_count;
    debt_state.final_task_balance_gap = debt_final_task_balance_gap;
    debt_state.initial_total_debt = debt_initial_total_debt;
    debt_state.remaining_total_debt = debt_remaining_total_debt;
    debt_state.total_compensated_task_count = debt_total_compensated_task_count;
    debt_state.last_round_compensated_task_count = debt_last_round_compensated_task_count;
    debt_state.last_start_slot_index = debt_last_start_slot_index;
    @memset(&debt_entries, std.mem.zeroes(abi.BaremetalApDebtEntry));
    slot_index = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const target_apic_id = readStateVar(slotTargetApicIdPtr(slot_index));
        const started = if (readStateVar(slotStartedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const halted = if (readStateVar(slotHaltedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const debt_task_count = DebtStorage.task_count[slot_index];
        const total_debt_task_count = DebtStorage.total_debt_task_count[slot_index];
        const seed_task_count = DebtStorage.seed_task_count[slot_index];
        const final_task_count = DebtStorage.final_task_count[slot_index];
        const total_accumulator = DebtStorage.total_accumulator[slot_index];
        const total_compensated_task_count = DebtStorage.total_compensated_task_count[slot_index];
        const remaining_debt = DebtStorage.remaining_debt[slot_index];
        if (target_apic_id == 0 and
            debt_task_count == 0 and
            total_debt_task_count == 0 and
            seed_task_count == 0 and
            final_task_count == 0 and
            total_accumulator == 0 and
            total_compensated_task_count == 0 and
            remaining_debt == 0 and
            started == 0 and
            halted == 0)
        {
            continue;
        }
        const dispatch_count = DebtStorage.dispatch_count[slot_index];
    admission_state.initial_task_balance_gap = admission_initial_task_balance_gap;
    admission_state.final_min_slot_task_count = admission_final_min_slot_task_count;
    admission_state.final_max_slot_task_count = admission_final_max_slot_task_count;
    admission_state.final_task_balance_gap = admission_final_task_balance_gap;
    admission_state.initial_total_debt = admission_initial_total_debt;
    admission_state.remaining_total_debt = admission_remaining_total_debt;
    admission_state.total_compensated_task_count = admission_total_compensated_task_count;
    admission_state.last_round_compensated_task_count = admission_last_round_compensated_task_count;
    admission_state.last_start_slot_index = admission_last_start_slot_index;
    @memset(&admission_entries, std.mem.zeroes(abi.BaremetalApAdmissionEntry));
    slot_index = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const target_apic_id = readStateVar(slotTargetApicIdPtr(slot_index));
        const started = if (readStateVar(slotStartedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const halted = if (readStateVar(slotHaltedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const admission_task_count = AdmissionStorage.admission_task_count[slot_index];
        const total_admitted_task_count = AdmissionStorage.total_admitted_task_count[slot_index];
        const debt_task_count = AdmissionStorage.debt_task_count[slot_index];
        const total_debt_task_count = AdmissionStorage.total_debt_task_count[slot_index];
        const seed_task_count = AdmissionStorage.seed_task_count[slot_index];
        const final_task_count = AdmissionStorage.final_task_count[slot_index];
        const total_accumulator = AdmissionStorage.total_accumulator[slot_index];
        const total_compensated_task_count = AdmissionStorage.total_compensated_task_count[slot_index];
        const remaining_debt = AdmissionStorage.remaining_debt[slot_index];
        if (target_apic_id == 0 and
            admission_task_count == 0 and
            total_admitted_task_count == 0 and
            debt_task_count == 0 and
            total_debt_task_count == 0 and
            seed_task_count == 0 and
            final_task_count == 0 and
            total_accumulator == 0 and
            total_compensated_task_count == 0 and
            remaining_debt == 0 and
            started == 0 and
            halted == 0)
        {
            continue;
        }
        const dispatch_count = AdmissionStorage.dispatch_count[slot_index];
    aging_state.initial_task_balance_gap = aging_initial_task_balance_gap;
    aging_state.final_min_slot_task_count = aging_final_min_slot_task_count;
    aging_state.final_max_slot_task_count = aging_final_max_slot_task_count;
    aging_state.final_task_balance_gap = aging_final_task_balance_gap;
    aging_state.initial_total_debt = aging_initial_total_debt;
    aging_state.remaining_total_debt = aging_remaining_total_debt;
    aging_state.total_compensated_task_count = aging_total_compensated_task_count;
    aging_state.last_round_compensated_task_count = aging_last_round_compensated_task_count;
    aging_state.total_aged_task_count = aging_total_aged_task_count;
    aging_state.last_round_aged_task_count = aging_last_round_aged_task_count;
    aging_state.total_promoted_task_count = aging_total_promoted_task_count;
    fairshare_state.initial_task_balance_gap = fairshare_initial_task_balance_gap;
    fairshare_state.final_min_slot_task_count = fairshare_final_min_slot_task_count;
    fairshare_state.final_max_slot_task_count = fairshare_final_max_slot_task_count;
    fairshare_state.final_task_balance_gap = fairshare_final_task_balance_gap;
    fairshare_state.initial_total_debt = fairshare_initial_total_debt;
    fairshare_state.remaining_total_debt = fairshare_remaining_total_debt;
    fairshare_state.total_compensated_task_count = fairshare_total_compensated_task_count;
    fairshare_state.last_round_compensated_task_count = fairshare_last_round_compensated_task_count;
    fairshare_state.total_aged_task_count = fairshare_total_aged_task_count;
    fairshare_state.last_round_aged_task_count = fairshare_last_round_aged_task_count;
    fairshare_state.total_promoted_task_count = fairshare_total_promoted_task_count;
    fairshare_state.total_fairshare_task_count = fairshare_total_fairshare_task_count;
    quota_state.initial_task_balance_gap = quota_initial_task_balance_gap;
    quota_state.final_min_slot_task_count = quota_final_min_slot_task_count;
    quota_state.final_max_slot_task_count = quota_final_max_slot_task_count;
    quota_state.final_task_balance_gap = quota_final_task_balance_gap;
    quota_state.initial_total_debt = quota_initial_total_debt;
    quota_state.remaining_total_debt = quota_remaining_total_debt;
    quota_state.total_compensated_task_count = quota_total_compensated_task_count;
    quota_state.last_round_compensated_task_count = quota_last_round_compensated_task_count;
    quota_state.total_aged_task_count = quota_total_aged_task_count;
    quota_state.last_round_aged_task_count = quota_last_round_aged_task_count;
    quota_state.total_promoted_task_count = quota_total_promoted_task_count;
    quota_state.total_quota_task_count = quota_total_quota_task_count;
    try std.testing.expectEqual(@as(u32, 0), snapshot.task_balance_gap);

    try std.testing.expectEqual(@as(u16, 4), fairnessEntryCount());
    const first_entry = fairnessEntry(0);
    const second_entry = fairnessEntry(1);
    const third_entry = fairnessEntry(2);
    const fourth_entry = fairnessEntry(3);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.drained_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.total_drained_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.last_task_id);
    try std.testing.expect(std.mem.indexOf(u8, fairness_render, "task_balance_gap=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairness_render, "slot[3].task[0]=1") != null);

    try haltApSlot(3);
    try haltApSlot(2);
    try haltApSlot(1);
    try haltApSlot(0);
}

    var rebalance_tasks: [6]abi.BaremetalTask = undefined;
    for (&rebalance_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast(index * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
    const snapshot = rebalanceStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u32, 6), snapshot.total_rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 5), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 21), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 2), snapshot.drain_round_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_round_rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 6), snapshot.initial_pending_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_pending_task_count);
    try std.testing.expectEqual(@as(u32, 6), snapshot.peak_pending_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.rebalance_task_budget);
    try std.testing.expectEqual(@as(u32, 2), snapshot.initial_min_slot_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.initial_max_slot_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.initial_task_balance_gap);
    try std.testing.expectEqual(@as(u32, 4), snapshot.final_min_slot_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.final_max_slot_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.final_task_balance_gap);
    try std.testing.expectEqual(@as(u32, 6), snapshot.total_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_round_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u16, 4), rebalanceEntryCount());
    const first_entry = rebalanceEntry(0);
    const second_entry = rebalanceEntry(1);
    const third_entry = rebalanceEntry(2);
    const fourth_entry = rebalanceEntry(3);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 0), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.total_rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.total_rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), third_entry.rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.total_rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.total_rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 2), RebalanceStorage.task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 1), RebalanceStorage.task_ids[@as(usize, third_entry.slot_index)][0]);

    const rebalance_render = try renderRebalanceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rebalance_render);
    try std.testing.expect(std.mem.indexOf(u8, rebalance_render, "total_rebalanced_task_count=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, rebalance_render, "total_dispatch_count=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, rebalance_render, "initial_task_balance_gap=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, rebalance_render, "final_task_balance_gap=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, rebalance_render, "total_compensated_task_count=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, rebalance_render, "slot[0].seed_task_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, rebalance_render, "slot[1].task[0]=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, rebalance_render, "slot[2].task[0]=1") != null);

    try haltApSlot(3);
    try haltApSlot(2);
    try haltApSlot(1);
    try haltApSlot(0);
}

    try std.testing.expectEqual(@as(u32, 2), snapshot.initial_task_balance_gap);
    try std.testing.expectEqual(@as(u32, 3), snapshot.final_min_slot_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.final_max_slot_task_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.final_task_balance_gap);
    try std.testing.expectEqual(@as(u32, 6), snapshot.initial_total_debt);
    try std.testing.expectEqual(@as(u32, 2), snapshot.remaining_total_debt);
    try std.testing.expectEqual(@as(u32, 4), snapshot.total_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_round_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u16, 4), debtEntryCount());
    const first_entry = debtEntry(0);
    const second_entry = debtEntry(1);
    const third_entry = debtEntry(2);
    const fourth_entry = debtEntry(3);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 0), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.debt_task_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), first_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 0), first_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 1), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), second_entry.debt_task_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 3), second_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 1), second_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 4), second_entry.last_task_id);
    try std.testing.expect(std.mem.indexOf(u8, debt_render, "final_task_balance_gap=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, debt_render, "initial_total_debt=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, debt_render, "remaining_total_debt=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, debt_render, "slot[2].task[0]=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, debt_render, "slot[3].task[0]=2") != null);

    try haltApSlot(3);
    try haltApSlot(2);
    try haltApSlot(1);
    try haltApSlot(0);
}

    try std.testing.expectEqual(@as(u32, 2), snapshot.initial_task_balance_gap);
    try std.testing.expectEqual(@as(u32, 4), snapshot.final_min_slot_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.final_max_slot_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.final_task_balance_gap);
    try std.testing.expectEqual(@as(u32, 6), snapshot.initial_total_debt);
    try std.testing.expectEqual(@as(u32, 0), snapshot.remaining_total_debt);
    try std.testing.expectEqual(@as(u32, 6), snapshot.total_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_round_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u16, 4), admissionEntryCount());
    const first_entry = admissionEntry(0);
    const second_entry = admissionEntry(1);
    const third_entry = admissionEntry(2);
    const fourth_entry = admissionEntry(3);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 0), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.total_admitted_task_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), first_entry.remaining_debt);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), second_entry.admission_task_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.total_admitted_task_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.debt_task_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), second_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_task_id);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "final_task_balance_gap=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "remaining_total_debt=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "slot[1].total_admitted_task_count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "slot[2].total_admitted_task_count=1") != null);

    try haltApSlot(3);
    try haltApSlot(2);
    try haltApSlot(1);
    try haltApSlot(0);
}

    try std.testing.expectEqual(@as(u32, 2), snapshot.initial_task_balance_gap);
    try std.testing.expectEqual(@as(u32, 4), snapshot.final_min_slot_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.final_max_slot_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.final_task_balance_gap);
    try std.testing.expectEqual(@as(u32, 6), snapshot.initial_total_debt);
    try std.testing.expectEqual(@as(u32, 0), snapshot.remaining_total_debt);
    try std.testing.expectEqual(@as(u32, 6), snapshot.total_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_round_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.total_aged_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_round_aged_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.total_promoted_task_count);
    try std.testing.expectEqual(@as(u32, 1), snapshot.initial_task_balance_gap);
    try std.testing.expectEqual(@as(u32, 4), snapshot.final_min_slot_task_count);
    try std.testing.expectEqual(@as(u32, 4), snapshot.final_max_slot_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.final_task_balance_gap);
    try std.testing.expectEqual(@as(u32, 3), snapshot.initial_total_debt);
    try std.testing.expectEqual(@as(u32, 0), snapshot.remaining_total_debt);
    try std.testing.expectEqual(@as(u32, 3), snapshot.total_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_round_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 24), snapshot.total_aged_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_round_aged_task_count);
    try std.testing.expectEqual(@as(u32, 8), snapshot.total_promoted_task_count);
    try std.testing.expectEqual(@as(u32, 7), snapshot.total_fairshare_task_count);
