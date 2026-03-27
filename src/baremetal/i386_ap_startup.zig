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
const max_owned_dispatch_entries: usize = max_ap_command_slots * max_task_batch_entries;
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
var fairness_task_balance_gap: u32 = 0;
var rebalance_drain_round_count: u32 = 0;
var rebalance_policy: u8 = abi.ap_ownership_policy_round_robin;
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
var aging_peak_effective_priority: u32 = 0;
var aging_last_start_slot_index: u32 = 0;
var fairshare_drain_round_count: u32 = 0;
var fairshare_aging_round_count: u32 = 0;
var fairshare_fairshare_round_count: u32 = 0;
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
var fairshare_peak_effective_priority: u32 = 0;
var fairshare_last_start_slot_index: u32 = 0;
const max_backfill_seen_tasks: usize = 128;
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
    var last_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_budget_ticks: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_batch_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var seen_task_ids: [max_backfill_seen_tasks]u32 = [_]u32{0} ** max_backfill_seen_tasks;
    var seen_task_count: usize = 0;
};
const WindowStorage = struct {
    var task_ids: [max_ap_command_slots][max_task_batch_entries]u32 = [_][max_task_batch_entries]u32{[_]u32{0} ** max_task_batch_entries} ** max_ap_command_slots;
    var task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var dispatch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_window_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_task_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_budget_ticks: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_batch_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
};
const FairnessStorage = struct {
    var task_ids: [max_ap_command_slots][max_task_batch_entries]u32 = [_][max_task_batch_entries]u32{[_]u32{0} ** max_task_batch_entries} ** max_ap_command_slots;
    var task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var dispatch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_drained_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_task_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_budget_ticks: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_batch_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
};
const RebalanceStorage = struct {
    var task_ids: [max_ap_command_slots][max_task_batch_entries]u32 = [_][max_task_batch_entries]u32{[_]u32{0} ** max_task_batch_entries} ** max_ap_command_slots;
    var task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var dispatch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_rebalanced_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var seed_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var final_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_task_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_budget_ticks: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_batch_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var compensated_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_compensated_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
};
const DebtStorage = struct {
    var task_ids: [max_ap_command_slots][max_task_batch_entries]u32 = [_][max_task_batch_entries]u32{[_]u32{0} ** max_task_batch_entries} ** max_ap_command_slots;
    var task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var dispatch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_debt_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var seed_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var final_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var initial_debt: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var remaining_debt: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_task_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_budget_ticks: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_batch_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var compensated_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_compensated_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
};
const AdmissionStorage = struct {
    var task_ids: [max_ap_command_slots][max_task_batch_entries]u32 = [_][max_task_batch_entries]u32{[_]u32{0} ** max_task_batch_entries} ** max_ap_command_slots;
    var task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var admission_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_admitted_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var debt_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_debt_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var dispatch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var seed_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var final_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var initial_debt: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var remaining_debt: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_task_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_budget_ticks: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_batch_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var compensated_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_compensated_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
};
const AgingStorage = struct {
    var task_ids: [max_ap_command_slots][max_task_batch_entries]u32 = [_][max_task_batch_entries]u32{[_]u32{0} ** max_task_batch_entries} ** max_ap_command_slots;
    var task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var waiting_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_waiting_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var debt_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_debt_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var dispatch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var seed_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var final_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var initial_debt: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var remaining_debt: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_task_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_effective_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var peak_effective_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_budget_ticks: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_batch_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var compensated_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_compensated_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var aged_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_aged_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
};
const FairshareStorage = struct {
    var task_ids: [max_ap_command_slots][max_task_batch_entries]u32 = [_][max_task_batch_entries]u32{[_]u32{0} ** max_task_batch_entries} ** max_ap_command_slots;
    var task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var waiting_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_waiting_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var debt_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_debt_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var fairshare_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_fairshare_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var dispatch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var seed_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var final_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var initial_debt: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var remaining_debt: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_task_id: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_effective_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var peak_effective_priority: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_budget_ticks: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var last_batch_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_accumulator: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var compensated_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_compensated_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var aged_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_aged_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
};
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

fn zeroOwnershipState() abi.BaremetalApOwnershipState {
    return .{
        .magic = abi.ap_ownership_magic,
        .api_version = abi.api_version,
        .present = 0,
        .policy = abi.ap_ownership_policy_round_robin,
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
        .policy = abi.ap_ownership_policy_round_robin,
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
        .policy = abi.ap_ownership_policy_round_robin,
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
        .task_balance_gap = 0,
    };
}

fn zeroRebalanceState() abi.BaremetalApRebalanceState {
    return .{
        .magic = abi.ap_rebalance_magic,
        .api_version = abi.api_version,
        .present = 0,
        .policy = abi.ap_ownership_policy_round_robin,
        .exported_count = 0,
        .active_count = 0,
        .peak_active_slot_count = 0,
        .last_round_active_slot_count = 0,
        .requested_cpu_count = 0,
        .logical_processor_count = 0,
        .reserved0 = 0,
        .bsp_apic_id = 0,
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
        .policy = abi.ap_ownership_policy_round_robin,
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
        .policy = abi.ap_ownership_policy_round_robin,
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
        .policy = abi.ap_ownership_policy_round_robin,
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
        .peak_effective_priority = 0,
        .last_start_slot_index = 0,
    };
}

fn zeroFairshareState() abi.BaremetalApFairshareState {
    return .{
        .magic = abi.ap_fairshare_magic,
        .api_version = abi.api_version,
        .present = 0,
        .policy = abi.ap_ownership_policy_round_robin,
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
        .peak_effective_priority = 0,
        .last_start_slot_index = 0,
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
    WindowStorage.last_priority[slot_index] = 0;
    WindowStorage.last_budget_ticks[slot_index] = 0;
    WindowStorage.last_batch_accumulator[slot_index] = 0;
    @memset(&WindowStorage.task_ids[slot_index], 0);
}

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
    FairnessStorage.last_priority[slot_index] = 0;
    FairnessStorage.last_budget_ticks[slot_index] = 0;
    FairnessStorage.last_batch_accumulator[slot_index] = 0;
    FairnessStorage.total_accumulator[slot_index] = 0;
    @memset(&FairnessStorage.task_ids[slot_index], 0);
}

fn resetFairnessState() void {
    fairness_state = zeroFairnessState();
    @memset(&fairness_entries, std.mem.zeroes(abi.BaremetalApFairnessEntry));
    fairness_drain_round_count = 0;
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
    RebalanceStorage.last_priority[slot_index] = 0;
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
    rebalance_policy = abi.ap_ownership_policy_round_robin;
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
    DebtStorage.last_priority[slot_index] = 0;
    DebtStorage.last_budget_ticks[slot_index] = 0;
    DebtStorage.last_batch_accumulator[slot_index] = 0;
    DebtStorage.total_accumulator[slot_index] = 0;
    DebtStorage.compensated_task_count[slot_index] = 0;
    DebtStorage.total_compensated_task_count[slot_index] = 0;
    @memset(&DebtStorage.task_ids[slot_index], 0);
}

fn resetAdmissionSlot(slot_index: usize) void {
    AdmissionStorage.task_count[slot_index] = 0;
    AdmissionStorage.admission_task_count[slot_index] = 0;
    AdmissionStorage.total_admitted_task_count[slot_index] = 0;
    AdmissionStorage.debt_task_count[slot_index] = 0;
    AdmissionStorage.total_debt_task_count[slot_index] = 0;
    AdmissionStorage.dispatch_count[slot_index] = 0;
    AdmissionStorage.seed_task_count[slot_index] = 0;
    AdmissionStorage.final_task_count[slot_index] = 0;
    AdmissionStorage.initial_debt[slot_index] = 0;
    AdmissionStorage.remaining_debt[slot_index] = 0;
    AdmissionStorage.last_task_id[slot_index] = 0;
    AdmissionStorage.last_priority[slot_index] = 0;
    AdmissionStorage.last_budget_ticks[slot_index] = 0;
    AdmissionStorage.last_batch_accumulator[slot_index] = 0;
    AdmissionStorage.total_accumulator[slot_index] = 0;
    AdmissionStorage.compensated_task_count[slot_index] = 0;
    AdmissionStorage.total_compensated_task_count[slot_index] = 0;
    @memset(&AdmissionStorage.task_ids[slot_index], 0);
}

fn resetAgingSlot(slot_index: usize) void {
    AgingStorage.task_count[slot_index] = 0;
    AgingStorage.waiting_task_count[slot_index] = 0;
    AgingStorage.total_waiting_task_count[slot_index] = 0;
    AgingStorage.debt_task_count[slot_index] = 0;
    AgingStorage.total_debt_task_count[slot_index] = 0;
    AgingStorage.dispatch_count[slot_index] = 0;
    AgingStorage.seed_task_count[slot_index] = 0;
    AgingStorage.final_task_count[slot_index] = 0;
    AgingStorage.initial_debt[slot_index] = 0;
    AgingStorage.remaining_debt[slot_index] = 0;
    AgingStorage.last_task_id[slot_index] = 0;
    AgingStorage.last_priority[slot_index] = 0;
    AgingStorage.last_effective_priority[slot_index] = 0;
    AgingStorage.peak_effective_priority[slot_index] = 0;
    AgingStorage.last_budget_ticks[slot_index] = 0;
    AgingStorage.last_batch_accumulator[slot_index] = 0;
    AgingStorage.total_accumulator[slot_index] = 0;
    AgingStorage.compensated_task_count[slot_index] = 0;
    AgingStorage.total_compensated_task_count[slot_index] = 0;
    AgingStorage.aged_task_count[slot_index] = 0;
    AgingStorage.total_aged_task_count[slot_index] = 0;
    @memset(&AgingStorage.task_ids[slot_index], 0);
}

fn resetFairshareSlot(slot_index: usize) void {
    FairshareStorage.task_count[slot_index] = 0;
    FairshareStorage.waiting_task_count[slot_index] = 0;
    FairshareStorage.total_waiting_task_count[slot_index] = 0;
    FairshareStorage.debt_task_count[slot_index] = 0;
    FairshareStorage.total_debt_task_count[slot_index] = 0;
    FairshareStorage.fairshare_task_count[slot_index] = 0;
    FairshareStorage.total_fairshare_task_count[slot_index] = 0;
    FairshareStorage.dispatch_count[slot_index] = 0;
    FairshareStorage.seed_task_count[slot_index] = 0;
    FairshareStorage.final_task_count[slot_index] = 0;
    FairshareStorage.initial_debt[slot_index] = 0;
    FairshareStorage.remaining_debt[slot_index] = 0;
    FairshareStorage.last_task_id[slot_index] = 0;
    FairshareStorage.last_priority[slot_index] = 0;
    FairshareStorage.last_effective_priority[slot_index] = 0;
    FairshareStorage.peak_effective_priority[slot_index] = 0;
    FairshareStorage.last_budget_ticks[slot_index] = 0;
    FairshareStorage.last_batch_accumulator[slot_index] = 0;
    FairshareStorage.total_accumulator[slot_index] = 0;
    FairshareStorage.compensated_task_count[slot_index] = 0;
    FairshareStorage.total_compensated_task_count[slot_index] = 0;
    FairshareStorage.aged_task_count[slot_index] = 0;
    FairshareStorage.total_aged_task_count[slot_index] = 0;
    @memset(&FairshareStorage.task_ids[slot_index], 0);
}

fn resetDebtState() void {
    debt_state = zeroDebtState();
    @memset(&debt_entries, std.mem.zeroes(abi.BaremetalApDebtEntry));
    debt_drain_round_count = 0;
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
    aging_peak_effective_priority = 0;
    aging_last_start_slot_index = 0;
    for (0..max_ap_command_slots) |slot_index| resetAgingSlot(slot_index);
}

fn resetFairshareState() void {
    fairshare_state = zeroFairshareState();
    @memset(&fairshare_entries, std.mem.zeroes(abi.BaremetalApFairshareEntry));
    fairshare_drain_round_count = 0;
    fairshare_aging_round_count = 0;
    fairshare_fairshare_round_count = 0;
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
    fairshare_peak_effective_priority = 0;
    fairshare_last_start_slot_index = 0;
    for (0..max_ap_command_slots) |slot_index| resetFairshareSlot(slot_index);
}

pub fn resetMultiState() void {
    multi_state = zeroMultiState();
    @memset(&multi_entries, std.mem.zeroes(abi.BaremetalApMultiEntry));
}

pub fn resetOwnershipState() void {
    ownership_state = zeroOwnershipState();
    failover_state = zeroFailoverState();
    backfill_state = zeroBackfillState();
    resetWindowState();
    resetFairnessState();
    resetRebalanceState();
    resetDebtState();
    resetAdmissionState();
    resetAgingState();
    resetFairshareState();
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

fn clearOwnershipRoundTelemetry() void {
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

fn clearWindowRoundTelemetry() void {
    window_state = zeroWindowState();
    @memset(&window_entries, std.mem.zeroes(abi.BaremetalApWindowEntry));
    window_last_round_active_slot_count = 0;
    window_last_round_task_count = 0;
    window_last_round_dispatch_count = 0;
    window_last_round_accumulator = 0;
    window_last_deferred_task_count = 0;
    window_last_start_slot_index = 0;
    for (0..max_ap_command_slots) |slot_index| clearWindowRoundSlot(slot_index);
}

fn previousTaskOwner(
    previous_owned_task_ids: [max_ap_command_slots][max_task_batch_entries]u32,
    previous_owned_task_count: [max_ap_command_slots]u32,
    task_id: u32,
) ?usize {
    var slot_index: usize = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const owned_count = @min(@as(usize, @intCast(previous_owned_task_count[slot_index])), max_task_batch_entries);
        var task_index: usize = 0;
        while (task_index < owned_count) : (task_index += 1) {
            if (previous_owned_task_ids[slot_index][task_index] == task_id) return slot_index;
        }
    }
    return null;
}

fn taskSliceContains(tasks: []const abi.BaremetalTask, task_id: u32) bool {
    for (tasks) |task| {
        if (task.task_id == task_id) return true;
    }
    return false;
}

fn countRemovedOwnedTasks(
    previous_owned_task_ids: [max_ap_command_slots][max_task_batch_entries]u32,
    previous_owned_task_count: [max_ap_command_slots]u32,
    current_tasks: []const abi.BaremetalTask,
) u32 {
    var removed_count: u32 = 0;
    var slot_index: usize = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const owned_count = @min(@as(usize, @intCast(previous_owned_task_count[slot_index])), max_task_batch_entries);
        var task_index: usize = 0;
        while (task_index < owned_count) : (task_index += 1) {
            const task_id = previous_owned_task_ids[slot_index][task_index];
            if (task_id == 0) continue;
            if (!taskSliceContains(current_tasks, task_id)) removed_count +%= 1;
        }
    }
    return removed_count;
}

fn hasSeenOwnedTask(task_id: u32) bool {
    var index: usize = 0;
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
                while (insert_index > 0 and current.priority > ordered[insert_index - 1].priority) : (insert_index -= 1) {
                    ordered[insert_index] = ordered[insert_index - 1];
                }
                ordered[insert_index] = current;
            }
        },
        else => unreachable,
    }
    return ordered[0..runnable_count];
}

fn dispatchOwnedSchedulerTasksByPolicyFromOffset(
    tasks: []const abi.BaremetalTask,
    policy: u8,
    start_slot_offset: usize,
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
    clearOwnershipRoundTelemetry();
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

    clearWindowRoundTelemetry();
    window_policy = policy;
    window_dispatch_round_count +%= 1;
    window_last_round_active_slot_count = @as(u8, @intCast(active_slot_count));
    if (window_peak_active_slot_count < window_last_round_active_slot_count) {
        window_peak_active_slot_count = window_last_round_active_slot_count;
    }

    const initial_slot_cursor = start_slot_offset % active_slot_count;
    window_last_start_slot_index = @as(u32, @intCast(initial_slot_cursor));
    var task_cursor = @as(usize, @intCast(window_task_cursor));
    if (task_cursor >= ordered_tasks.len) task_cursor = 0;
    const selected_count = @min(task_budget, ordered_tasks.len - task_cursor);
    const selected_tasks = ordered_tasks[task_cursor .. task_cursor + selected_count];
    const deferred_count = @as(u32, @intCast(ordered_tasks.len - selected_tasks.len));
    window_last_round_task_count = @as(u32, @intCast(selected_tasks.len));
    window_last_deferred_task_count = deferred_count;
    window_total_deferred_task_count +%= deferred_count;
    window_task_budget = @as(u32, @intCast(task_budget));

    var slot_cursor: usize = initial_slot_cursor;
    for (selected_tasks) |task| {
        const slot_index = @as(usize, active_slots[slot_cursor]);
        const current_count = @as(usize, WindowStorage.task_count[slot_index]);
        if (current_count >= max_task_batch_entries) return error.TooManyOwnedTasks;
        WindowStorage.task_ids[slot_index][current_count] = task.task_id;
        WindowStorage.task_count[slot_index] = @as(u32, @intCast(current_count + 1));
        WindowStorage.total_window_task_count[slot_index] +%= 1;
        WindowStorage.last_task_id[slot_index] = task.task_id;
        WindowStorage.last_priority[slot_index] = @as(u32, task.priority);
        WindowStorage.last_budget_ticks[slot_index] = task.budget_ticks;
        slot_cursor = (slot_cursor + 1) % active_slot_count;
    }

    var total_accumulator: u32 = 0;
    var round_dispatch_count: u32 = 0;
    var active_slot_cursor: usize = 0;
    while (active_slot_cursor < active_slot_count) : (active_slot_cursor += 1) {
        const slot_index = @as(usize, active_slots[active_slot_cursor]);
        const owned_count = @as(usize, WindowStorage.task_count[slot_index]);
        if (owned_count == 0) continue;
        const accumulator = try dispatchWorkBatchToApSlot(
            active_slots[active_slot_cursor],
            WindowStorage.task_ids[slot_index][0..owned_count],
        );
        WindowStorage.dispatch_count[slot_index] +%= 1;
        WindowStorage.last_batch_accumulator[slot_index] = accumulator;
        WindowStorage.total_accumulator[slot_index] +%= accumulator;
        total_accumulator +%= accumulator;
        round_dispatch_count +%= 1;
    }
    window_last_round_dispatch_count = round_dispatch_count;
    window_last_round_accumulator = total_accumulator;
    task_cursor += selected_tasks.len;
    if (task_cursor >= ordered_tasks.len) {
        task_cursor = 0;
        window_wrap_count +%= 1;
    }
    window_task_cursor = @as(u32, @intCast(task_cursor));
    refreshState();
    return total_accumulator;
}

pub fn dispatchWindowedSchedulerTasksPriorityFromOffset(
    tasks: []const abi.BaremetalTask,
    start_slot_offset: usize,
    task_budget: usize,
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
    fairness_task_balance_gap = if (have_active_slot) max_slot_task_count - fairness_min_slot_task_count else 0;

    for (0..max_ap_command_slots) |slot_index| {
        FairnessStorage.task_count[slot_index] = WindowStorage.task_count[slot_index];
        FairnessStorage.dispatch_count[slot_index] = WindowStorage.dispatch_count[slot_index];
        FairnessStorage.total_drained_task_count[slot_index] = WindowStorage.total_window_task_count[slot_index];
        FairnessStorage.total_accumulator[slot_index] = WindowStorage.total_accumulator[slot_index];
        if (WindowStorage.task_count[slot_index] != 0) {
            FairnessStorage.last_task_id[slot_index] = WindowStorage.last_task_id[slot_index];
            FairnessStorage.last_priority[slot_index] = WindowStorage.last_priority[slot_index];
            FairnessStorage.last_budget_ticks[slot_index] = WindowStorage.last_budget_ticks[slot_index];
            FairnessStorage.last_batch_accumulator[slot_index] = WindowStorage.last_batch_accumulator[slot_index];
            @memcpy(
                FairnessStorage.task_ids[slot_index][0..],
                WindowStorage.task_ids[slot_index][0..],
            );
        } else {
            @memset(&FairnessStorage.task_ids[slot_index], 0);
        }
    }
}

pub fn dispatchWindowedSchedulerTasksPriorityUntilDrainedFromOffset(
    tasks: []const abi.BaremetalTask,
    start_slot_offset: usize,
    task_budget: usize,
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
        const round_accumulator = try dispatchWindowedSchedulerTasksPriorityFromOffset(tasks, round_start_slot, task_budget);
        total_accumulator +%= round_accumulator;
        fairness_drain_round_count +%= 1;
        fairness_last_round_task_count = @as(u32, @intCast(round_task_count));
        fairness_last_start_slot_index = @as(u32, @intCast(round_start_slot));
        task_cursor += round_task_count;
        fairness_last_pending_task_count = @as(u32, @intCast(ordered_tasks.len - task_cursor));
        snapshotFairnessFromWindow(active_slots[0..active_slot_count]);
    }

    snapshotFairnessFromWindow(active_slots[0..active_slot_count]);
    refreshState();
    return total_accumulator;
}

fn clearRebalanceRoundTelemetry() void {
    for (0..max_ap_command_slots) |slot_index| {
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

pub fn dispatchRebalancedSchedulerTasksPriorityUntilDrainedFromOffset(
    tasks: []const abi.BaremetalTask,
    start_slot_offset: usize,
    task_budget: usize,
) OwnershipError!u32 {
    if (task_budget == 0) return error.InvalidWorkBatch;

    var active_slots: [max_ap_command_slots]u16 = undefined;
    const active_slot_count = activeOwnershipSlots(&active_slots);
    if (active_slot_count == 0) return error.ApNotStarted;

    var ordered_tasks_storage: [max_owned_dispatch_entries]abi.BaremetalTask = undefined;
    const ordered_tasks = try collectOwnedRunnableTasksOrdered(tasks, abi.ap_ownership_policy_priority, &ordered_tasks_storage);

    resetRebalanceState();
    rebalance_policy = abi.ap_ownership_policy_priority;
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
        clearRebalanceRoundTelemetry();
        const round_start_slot = (start_slot_offset + round_index) % active_slot_count;
        const remaining_task_count = ordered_tasks.len - task_cursor;
        const round_task_count = @min(task_budget, remaining_task_count);
        const selected_tasks = ordered_tasks[task_cursor .. task_cursor + round_task_count];
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
            RebalanceStorage.last_priority[slot_index] = @as(u32, task.priority);
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

fn clearDebtRoundTelemetry() void {
    for (0..max_ap_command_slots) |slot_index| {
        DebtStorage.task_count[slot_index] = 0;
        DebtStorage.compensated_task_count[slot_index] = 0;
        @memset(&DebtStorage.task_ids[slot_index], 0);
    }
}

fn snapshotDebtLoadRange(active_slots: []const u16, final: bool) void {
    var min_slot_task_count: u32 = std.math.maxInt(u32);
    var max_slot_task_count: u32 = 0;
    var have_active_slot = false;
    for (active_slots) |slot| {
        const slot_index = @as(usize, slot);
        const load = if (final) DebtStorage.final_task_count[slot_index] else DebtStorage.seed_task_count[slot_index];
        if (load < min_slot_task_count) min_slot_task_count = load;
        if (load > max_slot_task_count) max_slot_task_count = load;
        have_active_slot = true;
    }
    const min_value = if (have_active_slot) min_slot_task_count else 0;
    const gap_value = if (have_active_slot) max_slot_task_count - min_value else 0;
    if (final) {
        debt_final_min_slot_task_count = min_value;
        debt_final_max_slot_task_count = max_slot_task_count;
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

fn clearAdmissionRoundTelemetry() void {
    for (0..max_ap_command_slots) |slot_index| {
        AdmissionStorage.task_count[slot_index] = 0;
        AdmissionStorage.admission_task_count[slot_index] = 0;
        AdmissionStorage.debt_task_count[slot_index] = 0;
        AdmissionStorage.compensated_task_count[slot_index] = 0;
        @memset(&AdmissionStorage.task_ids[slot_index], 0);
    }
}

fn snapshotAdmissionLoadRange(active_slots: []const u16, final: bool) void {
    var min_slot_task_count: u32 = std.math.maxInt(u32);
    var max_slot_task_count: u32 = 0;
    var have_active_slot = false;
    for (active_slots) |slot| {
        const slot_index = @as(usize, slot);
        const load = if (final) AdmissionStorage.final_task_count[slot_index] else AdmissionStorage.seed_task_count[slot_index];
        if (load < min_slot_task_count) min_slot_task_count = load;
        if (load > max_slot_task_count) max_slot_task_count = load;
        have_active_slot = true;
    }
    const min_value = if (have_active_slot) min_slot_task_count else 0;
    const gap_value = if (have_active_slot) max_slot_task_count - min_value else 0;
    if (final) {
        admission_final_min_slot_task_count = min_value;
        admission_final_max_slot_task_count = max_slot_task_count;
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
    effective_priority: u32,
    waiting_age_rounds: u32,
    kind: AgingCandidateKind,
};

fn clearAgingRoundTelemetry() void {
    for (0..max_ap_command_slots) |slot_index| {
        AgingStorage.task_count[slot_index] = 0;
        AgingStorage.waiting_task_count[slot_index] = 0;
        AgingStorage.debt_task_count[slot_index] = 0;
        AgingStorage.compensated_task_count[slot_index] = 0;
        AgingStorage.aged_task_count[slot_index] = 0;
        @memset(&AgingStorage.task_ids[slot_index], 0);
    }
}

fn snapshotAgingLoadRange(active_slots: []const u16, final: bool) void {
    var min_slot_task_count: u32 = std.math.maxInt(u32);
    var max_slot_task_count: u32 = 0;
    var have_active_slot = false;
    for (active_slots) |slot| {
        const slot_index = @as(usize, slot);
        const load = if (final) AgingStorage.final_task_count[slot_index] else AgingStorage.seed_task_count[slot_index];
        if (load < min_slot_task_count) min_slot_task_count = load;
        if (load > max_slot_task_count) max_slot_task_count = load;
        have_active_slot = true;
    }
    const min_value = if (have_active_slot) min_slot_task_count else 0;
    const gap_value = if (have_active_slot) max_slot_task_count - min_value else 0;
    if (final) {
        aging_final_min_slot_task_count = min_value;
        aging_final_max_slot_task_count = max_slot_task_count;
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
            const previous_priority = previous.effective_priority;
            const current_priority = current.effective_priority;
            if (current_priority < previous_priority) break;
            if (current_priority == previous_priority) {
                const previous_base_priority = @as(u32, previous.task.priority);
                const current_base_priority = @as(u32, current.task.priority);
                if (current_base_priority < previous_base_priority) break;
                if (current_base_priority == previous_base_priority and current.task.task_id >= previous.task.task_id) break;
            }
            candidates[insert_index] = previous;
        }
        candidates[insert_index] = current;
    }
}

pub fn dispatchDebtAwareSchedulerTasksPriorityWithAdmissionFromOffset(
    debt_tasks: []const abi.BaremetalTask,
    admitted_tasks: []const abi.BaremetalTask,
    start_slot_offset: usize,
    task_budget: usize,
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
        clearAdmissionRoundTelemetry();
        const round_start_slot = (start_slot_offset + round_index) % active_slot_count;
        const remaining_task_count = ordered_tasks.len - task_cursor;
        const round_task_count = @min(task_budget, remaining_task_count);
        const selected_tasks = ordered_tasks[task_cursor .. task_cursor + round_task_count];
        admission_drain_round_count +%= 1;
        admission_last_round_admitted_task_count = 0;
        admission_last_round_debt_task_count = 0;
        admission_last_round_compensated_task_count = 0;
        admission_last_start_slot_index = @as(u32, @intCast(round_start_slot));

        for (selected_tasks, 0..) |task, task_index| {
            const slot = selectHighestAdmissionDebtSlot(active_slots[0..active_slot_count], round_start_slot + task_index);
            const slot_index = @as(usize, slot);
            const current_count = @as(usize, AdmissionStorage.task_count[slot_index]);
            if (current_count >= max_task_batch_entries) return error.TooManyOwnedTasks;
            const debt_before = AdmissionStorage.remaining_debt[slot_index];
            const admitted = taskSliceContainsTaskId(admitted_tasks, task.task_id);
            AdmissionStorage.task_ids[slot_index][current_count] = task.task_id;
            AdmissionStorage.task_count[slot_index] = @as(u32, @intCast(current_count + 1));
            AdmissionStorage.final_task_count[slot_index] +%= 1;
            AdmissionStorage.last_task_id[slot_index] = task.task_id;
            AdmissionStorage.last_priority[slot_index] = @as(u32, task.priority);
            AdmissionStorage.last_budget_ticks[slot_index] = task.budget_ticks;
            if (admitted) {
                AdmissionStorage.admission_task_count[slot_index] +%= 1;
                AdmissionStorage.total_admitted_task_count[slot_index] +%= 1;
                admission_last_round_admitted_task_count +%= 1;
            } else {
                AdmissionStorage.debt_task_count[slot_index] +%= 1;
                AdmissionStorage.total_debt_task_count[slot_index] +%= 1;
                admission_last_round_debt_task_count +%= 1;
            }
            if (debt_before != 0) {
                AdmissionStorage.remaining_debt[slot_index] = debt_before - 1;
                AdmissionStorage.compensated_task_count[slot_index] +%= 1;
                AdmissionStorage.total_compensated_task_count[slot_index] +%= 1;
                admission_remaining_total_debt -%= 1;
                admission_total_compensated_task_count +%= 1;
                admission_last_round_compensated_task_count +%= 1;
            }
        }

        var round_accumulator: u32 = 0;
        for (active_slots[0..active_slot_count]) |slot| {
            const slot_index = @as(usize, slot);
            const owned_count = @as(usize, AdmissionStorage.task_count[slot_index]);
            if (owned_count == 0) continue;
            const accumulator = try dispatchWorkBatchToApSlot(slot, AdmissionStorage.task_ids[slot_index][0..owned_count]);
            AdmissionStorage.dispatch_count[slot_index] +%= 1;
            AdmissionStorage.last_batch_accumulator[slot_index] = accumulator;
            AdmissionStorage.total_accumulator[slot_index] +%= accumulator;
            round_accumulator +%= accumulator;
        }

        total_accumulator +%= round_accumulator;
        task_cursor += round_task_count;
        admission_last_pending_task_count = @as(u32, @intCast(ordered_tasks.len - task_cursor));
        snapshotAdmissionLoadRange(active_slots[0..active_slot_count], true);
    }

    snapshotAdmissionLoadRange(active_slots[0..active_slot_count], true);
    refreshState();
    return total_accumulator;
}

pub fn dispatchDebtAwareSchedulerTasksPriorityWithAgingFromOffset(
    debt_tasks: []const abi.BaremetalTask,
    waiting_tasks: []const abi.BaremetalTask,
    start_slot_offset: usize,
    task_budget: usize,
    aging_step: u32,
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
        clearAgingRoundTelemetry();
        const round_start_slot = (start_slot_offset + round_index) % active_slot_count;
        const candidate_count = remaining_debt_count + remaining_waiting_count;
        var candidates: [max_owned_dispatch_entries]AgingCandidate = undefined;
        var built_count: usize = 0;
        for (remaining_debt_storage[0..remaining_debt_count]) |task| {
            candidates[built_count] = .{
                .task = task,
                .effective_priority = @as(u32, task.priority),
                .waiting_age_rounds = 0,
                .kind = .debt,
            };
            built_count += 1;
        }
        for (remaining_waiting_storage[0..remaining_waiting_count], 0..) |task, waiting_index| {
            const rounds = waiting_age_rounds[waiting_index];
            const effective_priority = @as(u32, task.priority) +| (rounds * aging_step);
            candidates[built_count] = .{
                .task = task,
                .effective_priority = effective_priority,
                .waiting_age_rounds = rounds,
                .kind = .waiting,
            };
            if (aging_peak_effective_priority < effective_priority) aging_peak_effective_priority = effective_priority;
            built_count += 1;
        }
        std.debug.assert(built_count == candidate_count);
        sortAgingCandidates(candidates[0..candidate_count]);

        const round_task_count = @min(task_budget, candidate_count);
        const selected_candidates = candidates[0..round_task_count];
        aging_drain_round_count +%= 1;
        aging_last_round_waiting_task_count = 0;
        aging_last_round_debt_task_count = 0;
        aging_last_round_compensated_task_count = 0;
        aging_last_round_aged_task_count = 0;
        aging_last_start_slot_index = @as(u32, @intCast(round_start_slot));

        for (selected_candidates, 0..) |candidate, task_index| {
            const slot = selectHighestAgingDebtSlot(active_slots[0..active_slot_count], round_start_slot + task_index);
            const slot_index = @as(usize, slot);
            const current_count = @as(usize, AgingStorage.task_count[slot_index]);
            if (current_count >= max_task_batch_entries) return error.TooManyOwnedTasks;
            const debt_before = AgingStorage.remaining_debt[slot_index];
            const aged = candidate.waiting_age_rounds != 0;
            AgingStorage.task_ids[slot_index][current_count] = candidate.task.task_id;
            AgingStorage.task_count[slot_index] = @as(u32, @intCast(current_count + 1));
            AgingStorage.final_task_count[slot_index] +%= 1;
            AgingStorage.last_task_id[slot_index] = candidate.task.task_id;
            AgingStorage.last_priority[slot_index] = @as(u32, candidate.task.priority);
            AgingStorage.last_effective_priority[slot_index] = candidate.effective_priority;
            AgingStorage.last_budget_ticks[slot_index] = candidate.task.budget_ticks;
            if (AgingStorage.peak_effective_priority[slot_index] < candidate.effective_priority) {
                AgingStorage.peak_effective_priority[slot_index] = candidate.effective_priority;
            }
            if (candidate.kind == .waiting) {
                AgingStorage.waiting_task_count[slot_index] +%= 1;
                AgingStorage.total_waiting_task_count[slot_index] +%= 1;
                aging_last_round_waiting_task_count +%= 1;
                if (aged) {
                    AgingStorage.aged_task_count[slot_index] +%= 1;
                    AgingStorage.total_aged_task_count[slot_index] +%= 1;
                    aging_total_promoted_task_count +%= 1;
                }
            } else {
                AgingStorage.debt_task_count[slot_index] +%= 1;
                AgingStorage.total_debt_task_count[slot_index] +%= 1;
                aging_last_round_debt_task_count +%= 1;
            }
            if (debt_before != 0) {
                AgingStorage.remaining_debt[slot_index] = debt_before - 1;
                AgingStorage.compensated_task_count[slot_index] +%= 1;
                AgingStorage.total_compensated_task_count[slot_index] +%= 1;
                aging_remaining_total_debt -%= 1;
                aging_total_compensated_task_count +%= 1;
                aging_last_round_compensated_task_count +%= 1;
            }
        }

        var round_accumulator: u32 = 0;
        for (active_slots[0..active_slot_count]) |slot| {
            const slot_index = @as(usize, slot);
            const owned_count = @as(usize, AgingStorage.task_count[slot_index]);
            if (owned_count == 0) continue;
            const accumulator = try dispatchWorkBatchToApSlot(slot, AgingStorage.task_ids[slot_index][0..owned_count]);
            AgingStorage.dispatch_count[slot_index] +%= 1;
            AgingStorage.last_batch_accumulator[slot_index] = accumulator;
            AgingStorage.total_accumulator[slot_index] +%= accumulator;
            round_accumulator +%= accumulator;
        }
        total_accumulator +%= round_accumulator;

        var next_debt_count: usize = 0;
        for (remaining_debt_storage[0..remaining_debt_count]) |task| {
            if (containsAgingCandidateTaskId(selected_candidates, task.task_id)) continue;
            remaining_debt_storage[next_debt_count] = task;
            next_debt_count += 1;
        }
        remaining_debt_count = next_debt_count;

        var next_waiting_count: usize = 0;
        var aged_this_round: u32 = 0;
        for (remaining_waiting_storage[0..remaining_waiting_count], 0..) |task, waiting_index| {
            if (containsAgingCandidateTaskId(selected_candidates, task.task_id)) continue;
            remaining_waiting_storage[next_waiting_count] = task;
            waiting_age_rounds[next_waiting_count] = waiting_age_rounds[waiting_index] + 1;
            next_waiting_count += 1;
            aged_this_round +%= 1;
        }
        remaining_waiting_count = next_waiting_count;
        if (aged_this_round != 0) {
            aging_round_count +%= 1;
            aging_total_aged_task_count +%= aged_this_round;
            aging_last_round_aged_task_count = aged_this_round;
        }

        aging_last_pending_task_count = @as(u32, @intCast(remaining_debt_count + remaining_waiting_count));
        snapshotAgingLoadRange(active_slots[0..active_slot_count], true);
    }

    snapshotAgingLoadRange(active_slots[0..active_slot_count], true);
    refreshState();
    return total_accumulator;
}

fn clearFairshareRoundTelemetry() void {
    for (0..max_ap_command_slots) |slot_index| {
        FairshareStorage.task_count[slot_index] = 0;
        FairshareStorage.waiting_task_count[slot_index] = 0;
        FairshareStorage.debt_task_count[slot_index] = 0;
        FairshareStorage.fairshare_task_count[slot_index] = 0;
        FairshareStorage.compensated_task_count[slot_index] = 0;
        FairshareStorage.aged_task_count[slot_index] = 0;
        @memset(&FairshareStorage.task_ids[slot_index], 0);
    }
}

fn snapshotFairshareLoadRange(active_slots: []const u16, final: bool) void {
    var min_slot_task_count: u32 = std.math.maxInt(u32);
    var max_slot_task_count: u32 = 0;
    var have_active_slot = false;
    for (active_slots) |slot| {
        const slot_index = @as(usize, slot);
        const load = if (final) FairshareStorage.final_task_count[slot_index] else FairshareStorage.seed_task_count[slot_index];
        if (load < min_slot_task_count) min_slot_task_count = load;
        if (load > max_slot_task_count) max_slot_task_count = load;
        have_active_slot = true;
    }
    const min_value = if (have_active_slot) min_slot_task_count else 0;
    const gap_value = if (have_active_slot) max_slot_task_count - min_value else 0;
    if (final) {
        fairshare_final_min_slot_task_count = min_value;
        fairshare_final_max_slot_task_count = max_slot_task_count;
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

pub fn dispatchDebtAwareSchedulerTasksPriorityWithFairshareFromOffset(
    debt_tasks: []const abi.BaremetalTask,
    waiting_tasks: []const abi.BaremetalTask,
    start_slot_offset: usize,
    task_budget: usize,
    aging_step: u32,
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
        clearFairshareRoundTelemetry();
        const round_start_slot = (start_slot_offset + round_index) % active_slot_count;
        const round_is_fairshare = fairshare_remaining_total_debt == 0;
        const candidate_count = remaining_debt_count + remaining_waiting_count;
        var candidates: [max_owned_dispatch_entries]AgingCandidate = undefined;
        var built_count: usize = 0;
        for (remaining_debt_storage[0..remaining_debt_count]) |task| {
            candidates[built_count] = .{
                .task = task,
                .effective_priority = @as(u32, task.priority),
                .waiting_age_rounds = 0,
                .kind = .debt,
            };
            built_count += 1;
        }
        for (remaining_waiting_storage[0..remaining_waiting_count], 0..) |task, waiting_index| {
            const rounds = waiting_age_rounds[waiting_index];
            const effective_priority = @as(u32, task.priority) +| (rounds * aging_step);
            candidates[built_count] = .{
                .task = task,
                .effective_priority = effective_priority,
                .waiting_age_rounds = rounds,
                .kind = .waiting,
            };
            if (fairshare_peak_effective_priority < effective_priority) fairshare_peak_effective_priority = effective_priority;
            built_count += 1;
        }
        std.debug.assert(built_count == candidate_count);
        sortAgingCandidates(candidates[0..candidate_count]);

        const round_task_count = @min(task_budget, candidate_count);
        const selected_candidates = candidates[0..round_task_count];
        fairshare_drain_round_count +%= 1;
        fairshare_last_round_waiting_task_count = 0;
        fairshare_last_round_debt_task_count = 0;
        fairshare_last_round_fairshare_task_count = 0;
        fairshare_last_round_compensated_task_count = 0;
        fairshare_last_round_aged_task_count = 0;
        fairshare_last_start_slot_index = @as(u32, @intCast(round_start_slot));

        for (selected_candidates, 0..) |candidate, task_index| {
            const slot = selectHighestFairshareDebtSlot(active_slots[0..active_slot_count], round_start_slot + task_index);
            const slot_index = @as(usize, slot);
            const current_count = @as(usize, FairshareStorage.task_count[slot_index]);
            if (current_count >= max_task_batch_entries) return error.TooManyOwnedTasks;
            const debt_before = FairshareStorage.remaining_debt[slot_index];
            const aged = candidate.waiting_age_rounds != 0;
            FairshareStorage.task_ids[slot_index][current_count] = candidate.task.task_id;
            FairshareStorage.task_count[slot_index] = @as(u32, @intCast(current_count + 1));
            FairshareStorage.final_task_count[slot_index] +%= 1;
            FairshareStorage.last_task_id[slot_index] = candidate.task.task_id;
            FairshareStorage.last_priority[slot_index] = @as(u32, candidate.task.priority);
            FairshareStorage.last_effective_priority[slot_index] = candidate.effective_priority;
            FairshareStorage.last_budget_ticks[slot_index] = candidate.task.budget_ticks;
            if (FairshareStorage.peak_effective_priority[slot_index] < candidate.effective_priority) {
                FairshareStorage.peak_effective_priority[slot_index] = candidate.effective_priority;
            }
            if (candidate.kind == .waiting) {
                FairshareStorage.waiting_task_count[slot_index] +%= 1;
                FairshareStorage.total_waiting_task_count[slot_index] +%= 1;
                fairshare_last_round_waiting_task_count +%= 1;
                if (aged) {
                    FairshareStorage.aged_task_count[slot_index] +%= 1;
                    FairshareStorage.total_aged_task_count[slot_index] +%= 1;
                    fairshare_total_promoted_task_count +%= 1;
                }
                if (round_is_fairshare) {
                    FairshareStorage.fairshare_task_count[slot_index] +%= 1;
                    FairshareStorage.total_fairshare_task_count[slot_index] +%= 1;
                    fairshare_total_fairshare_task_count +%= 1;
                    fairshare_last_round_fairshare_task_count +%= 1;
                }
            } else {
                FairshareStorage.debt_task_count[slot_index] +%= 1;
                FairshareStorage.total_debt_task_count[slot_index] +%= 1;
                fairshare_last_round_debt_task_count +%= 1;
            }
            if (debt_before != 0) {
                FairshareStorage.remaining_debt[slot_index] = debt_before - 1;
                FairshareStorage.compensated_task_count[slot_index] +%= 1;
                FairshareStorage.total_compensated_task_count[slot_index] +%= 1;
                fairshare_remaining_total_debt -%= 1;
                fairshare_total_compensated_task_count +%= 1;
                fairshare_last_round_compensated_task_count +%= 1;
            }
        }
        if (round_is_fairshare and fairshare_last_round_fairshare_task_count != 0) {
            fairshare_fairshare_round_count +%= 1;
        }

        var round_accumulator: u32 = 0;
        for (active_slots[0..active_slot_count]) |slot| {
            const slot_index = @as(usize, slot);
            const owned_count = @as(usize, FairshareStorage.task_count[slot_index]);
            if (owned_count == 0) continue;
            const accumulator = try dispatchWorkBatchToApSlot(slot, FairshareStorage.task_ids[slot_index][0..owned_count]);
            FairshareStorage.dispatch_count[slot_index] +%= 1;
            FairshareStorage.last_batch_accumulator[slot_index] = accumulator;
            FairshareStorage.total_accumulator[slot_index] +%= accumulator;
            round_accumulator +%= accumulator;
        }
        total_accumulator +%= round_accumulator;

        var next_debt_count: usize = 0;
        for (remaining_debt_storage[0..remaining_debt_count]) |task| {
            if (containsAgingCandidateTaskId(selected_candidates, task.task_id)) continue;
            remaining_debt_storage[next_debt_count] = task;
            next_debt_count += 1;
        }
        remaining_debt_count = next_debt_count;

        var next_waiting_count: usize = 0;
        var aged_this_round: u32 = 0;
        for (remaining_waiting_storage[0..remaining_waiting_count], 0..) |task, waiting_index| {
            if (containsAgingCandidateTaskId(selected_candidates, task.task_id)) continue;
            remaining_waiting_storage[next_waiting_count] = task;
            waiting_age_rounds[next_waiting_count] = waiting_age_rounds[waiting_index] + 1;
            next_waiting_count += 1;
            aged_this_round +%= 1;
        }
        remaining_waiting_count = next_waiting_count;
        if (aged_this_round != 0) {
            fairshare_aging_round_count +%= 1;
            fairshare_total_aged_task_count +%= aged_this_round;
            fairshare_last_round_aged_task_count = aged_this_round;
        }

        fairshare_last_pending_task_count = @as(u32, @intCast(remaining_debt_count + remaining_waiting_count));
        snapshotFairshareLoadRange(active_slots[0..active_slot_count], true);
    }

    snapshotFairshareLoadRange(active_slots[0..active_slot_count], true);
    refreshState();
    return total_accumulator;
}

pub fn dispatchDebtAwareSchedulerTasksPriorityUntilDrainedFromOffset(
    tasks: []const abi.BaremetalTask,
    start_slot_offset: usize,
    task_budget: usize,
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
        clearDebtRoundTelemetry();
        const round_start_slot = (start_slot_offset + round_index) % active_slot_count;
        const remaining_task_count = ordered_tasks.len - task_cursor;
        const round_task_count = @min(task_budget, remaining_task_count);
        const selected_tasks = ordered_tasks[task_cursor .. task_cursor + round_task_count];
        debt_drain_round_count +%= 1;
        debt_last_round_task_count = @as(u32, @intCast(round_task_count));
        debt_last_start_slot_index = @as(u32, @intCast(round_start_slot));
        debt_last_round_compensated_task_count = 0;

        for (selected_tasks, 0..) |task, task_index| {
            const slot = selectHighestDebtSlot(active_slots[0..active_slot_count], round_start_slot + task_index);
            const slot_index = @as(usize, slot);
            const current_count = @as(usize, DebtStorage.task_count[slot_index]);
            if (current_count >= max_task_batch_entries) return error.TooManyOwnedTasks;
            const debt_before = DebtStorage.remaining_debt[slot_index];
            DebtStorage.task_ids[slot_index][current_count] = task.task_id;
            DebtStorage.task_count[slot_index] = @as(u32, @intCast(current_count + 1));
            DebtStorage.total_debt_task_count[slot_index] +%= 1;
            DebtStorage.final_task_count[slot_index] +%= 1;
            DebtStorage.last_task_id[slot_index] = task.task_id;
            DebtStorage.last_priority[slot_index] = @as(u32, task.priority);
            DebtStorage.last_budget_ticks[slot_index] = task.budget_ticks;
            if (debt_before != 0) {
                DebtStorage.remaining_debt[slot_index] = debt_before - 1;
                DebtStorage.compensated_task_count[slot_index] +%= 1;
                DebtStorage.total_compensated_task_count[slot_index] +%= 1;
                debt_remaining_total_debt -%= 1;
                debt_total_compensated_task_count +%= 1;
                debt_last_round_compensated_task_count +%= 1;
            }
        }

        var round_accumulator: u32 = 0;
        for (active_slots[0..active_slot_count]) |slot| {
            const slot_index = @as(usize, slot);
            const owned_count = @as(usize, DebtStorage.task_count[slot_index]);
            if (owned_count == 0) continue;
            const accumulator = try dispatchWorkBatchToApSlot(slot, DebtStorage.task_ids[slot_index][0..owned_count]);
            DebtStorage.dispatch_count[slot_index] +%= 1;
            DebtStorage.last_batch_accumulator[slot_index] = accumulator;
            DebtStorage.total_accumulator[slot_index] +%= accumulator;
            round_accumulator +%= accumulator;
        }

        total_accumulator +%= round_accumulator;
        task_cursor += round_task_count;
        debt_last_pending_task_count = @as(u32, @intCast(ordered_tasks.len - task_cursor));
        snapshotDebtLoadRange(active_slots[0..active_slot_count], true);
    }

    snapshotDebtLoadRange(active_slots[0..active_slot_count], true);
    refreshState();
    return total_accumulator;
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

pub fn retireApSlot(slot_index: u16) Error!void {
    const slot_usize: usize = slot_index;
    if (slot_usize >= max_ap_command_slots) return error.NoSecondaryCpu;
    const was_started = readStateVar(slotStartedPtr(slot_usize)) != 0;
    const was_halted = readStateVar(slotHaltedPtr(slot_usize)) != 0;
    if (!was_started or was_halted) return error.ApNotStarted;
    try haltApSlot(slot_index);
    failover_retired_slot_event_count +%= 1;
    failover_last_retired_slot_index = @as(u8, @intCast(slot_usize));
    refreshState();
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

pub fn renderOwnershipAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [3072]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
        buffer[used..],
        "present={d}\npolicy={d}\nexported_count={d}\nactive_count={d}\npeak_active_slot_count={d}\nrequested_cpu_count={d}\nlogical_processor_count={d}\nbsp_apic_id={d}\ntotal_owned_task_count={d}\ntotal_dispatch_count={d}\ntotal_accumulator={d}\ndispatch_round_count={d}\n",
        .{
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
            "slot[{d}].target_apic_id={d}\nslot[{d}].dispatch_count={d}\nslot[{d}].owned_task_count={d}\nslot[{d}].total_owned_task_count={d}\nslot[{d}].redistributed_task_count={d}\nslot[{d}].total_redistributed_task_count={d}\nslot[{d}].last_task_id={d}\nslot[{d}].last_priority={d}\nslot[{d}].last_budget_ticks={d}\nslot[{d}].last_batch_accumulator={d}\nslot[{d}].total_accumulator={d}\nslot[{d}].started={d}\nslot[{d}].halted={d}\nslot[{d}].slot_index={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.dispatch_count,
                entry_index, entry.owned_task_count,
                entry_index, entry.total_owned_task_count,
                entry_index, entry.redistributed_task_count,
                entry_index, entry.total_redistributed_task_count,
                entry_index, entry.last_task_id,
                entry_index, entry.last_priority,
                entry_index, entry.last_budget_ticks,
                entry_index, entry.last_batch_accumulator,
                entry_index, entry.total_accumulator,
                entry_index, entry.started,
                entry_index, entry.halted,
                entry_index, entry.slot_index,
            },
        ) catch unreachable;
        used += line.len;
        const task_count = @min(@as(usize, @intCast(entry.owned_task_count)), max_task_batch_entries);
        for (0..task_count) |task_index| {
            const task_line = std.fmt.bufPrint(
                buffer[used..],
                "slot[{d}].task[{d}]={d}\n",
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
            "slot[{d}].target_apic_id={d}\nslot[{d}].dispatch_count={d}\nslot[{d}].owned_task_count={d}\nslot[{d}].total_owned_task_count={d}\nslot[{d}].redistributed_task_count={d}\nslot[{d}].total_redistributed_task_count={d}\nslot[{d}].backfilled_task_count={d}\nslot[{d}].total_backfilled_task_count={d}\nslot[{d}].last_task_id={d}\nslot[{d}].last_priority={d}\nslot[{d}].last_budget_ticks={d}\nslot[{d}].last_batch_accumulator={d}\nslot[{d}].total_accumulator={d}\nslot[{d}].started={d}\nslot[{d}].halted={d}\nslot[{d}].slot_index={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.dispatch_count,
                entry_index, entry.owned_task_count,
                entry_index, entry.total_owned_task_count,
                entry_index, entry.redistributed_task_count,
                entry_index, entry.total_redistributed_task_count,
                entry_index, entry.backfilled_task_count,
                entry_index, entry.total_backfilled_task_count,
                entry_index, entry.last_task_id,
                entry_index, entry.last_priority,
                entry_index, entry.last_budget_ticks,
                entry_index, entry.last_batch_accumulator,
                entry_index, entry.total_accumulator,
                entry_index, entry.started,
                entry_index, entry.halted,
                entry_index, entry.slot_index,
            },
        ) catch unreachable;
        used += line.len;
    }
    return allocator.dupe(u8, buffer[0..used]);
}

pub fn renderWindowAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [4096]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
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
            "slot[{d}].target_apic_id={d}\nslot[{d}].dispatch_count={d}\nslot[{d}].window_task_count={d}\nslot[{d}].total_window_task_count={d}\nslot[{d}].last_task_id={d}\nslot[{d}].last_priority={d}\nslot[{d}].last_budget_ticks={d}\nslot[{d}].last_batch_accumulator={d}\nslot[{d}].total_accumulator={d}\nslot[{d}].started={d}\nslot[{d}].halted={d}\nslot[{d}].slot_index={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.dispatch_count,
                entry_index, entry.window_task_count,
                entry_index, entry.total_window_task_count,
                entry_index, entry.last_task_id,
                entry_index, entry.last_priority,
                entry_index, entry.last_budget_ticks,
                entry_index, entry.last_batch_accumulator,
                entry_index, entry.total_accumulator,
                entry_index, entry.started,
                entry_index, entry.halted,
                entry_index, entry.slot_index,
            },
        ) catch unreachable;
        used += line.len;
        const task_count = @min(@as(usize, @intCast(entry.window_task_count)), max_task_batch_entries);
        for (0..task_count) |task_index| {
            const task_line = std.fmt.bufPrint(
                buffer[used..],
                "slot[{d}].task[{d}]={d}\n",
                .{ entry_index, task_index, WindowStorage.task_ids[entry.slot_index][task_index] },
            ) catch unreachable;
            used += task_line.len;
        }
    }
    return allocator.dupe(u8, buffer[0..used]);
}

pub fn renderFairnessAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [4096]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
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
    while (entry_index < fairness_state.exported_count) : (entry_index += 1) {
        const entry = fairness_entries[entry_index];
        const line = std.fmt.bufPrint(
            buffer[used..],
            "slot[{d}].target_apic_id={d}\nslot[{d}].dispatch_count={d}\nslot[{d}].drained_task_count={d}\nslot[{d}].total_drained_task_count={d}\nslot[{d}].last_task_id={d}\nslot[{d}].last_priority={d}\nslot[{d}].last_budget_ticks={d}\nslot[{d}].last_batch_accumulator={d}\nslot[{d}].total_accumulator={d}\nslot[{d}].started={d}\nslot[{d}].halted={d}\nslot[{d}].slot_index={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.dispatch_count,
                entry_index, entry.drained_task_count,
                entry_index, entry.total_drained_task_count,
                entry_index, entry.last_task_id,
                entry_index, entry.last_priority,
                entry_index, entry.last_budget_ticks,
                entry_index, entry.last_batch_accumulator,
                entry_index, entry.total_accumulator,
                entry_index, entry.started,
                entry_index, entry.halted,
                entry_index, entry.slot_index,
            },
        ) catch unreachable;
        used += line.len;
        const task_count = @min(@as(usize, @intCast(entry.drained_task_count)), max_task_batch_entries);
        for (0..task_count) |task_index| {
            const task_line = std.fmt.bufPrint(
                buffer[used..],
                "slot[{d}].task[{d}]={d}\n",
                .{ entry_index, task_index, FairnessStorage.task_ids[entry.slot_index][task_index] },
            ) catch unreachable;
            used += task_line.len;
        }
    }
    return allocator.dupe(u8, buffer[0..used]);
}

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
            "slot[{d}].target_apic_id={d}\nslot[{d}].dispatch_count={d}\nslot[{d}].rebalanced_task_count={d}\nslot[{d}].total_rebalanced_task_count={d}\nslot[{d}].seed_task_count={d}\nslot[{d}].final_task_count={d}\nslot[{d}].last_task_id={d}\nslot[{d}].last_priority={d}\nslot[{d}].last_budget_ticks={d}\nslot[{d}].last_batch_accumulator={d}\nslot[{d}].total_accumulator={d}\nslot[{d}].compensated_task_count={d}\nslot[{d}].total_compensated_task_count={d}\nslot[{d}].started={d}\nslot[{d}].halted={d}\nslot[{d}].slot_index={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.dispatch_count,
                entry_index, entry.rebalanced_task_count,
                entry_index, entry.total_rebalanced_task_count,
                entry_index, entry.seed_task_count,
                entry_index, entry.final_task_count,
                entry_index, entry.last_task_id,
                entry_index, entry.last_priority,
                entry_index, entry.last_budget_ticks,
                entry_index, entry.last_batch_accumulator,
                entry_index, entry.total_accumulator,
                entry_index, entry.compensated_task_count,
                entry_index, entry.total_compensated_task_count,
                entry_index, entry.started,
                entry_index, entry.halted,
                entry_index, entry.slot_index,
            },
        ) catch unreachable;
        used += line.len;
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
            "slot[{d}].last_priority={d}\nslot[{d}].last_budget_ticks={d}\nslot[{d}].last_batch_accumulator={d}\nslot[{d}].total_accumulator={d}\nslot[{d}].compensated_task_count={d}\nslot[{d}].total_compensated_task_count={d}\nslot[{d}].started={d}\nslot[{d}].halted={d}\nslot[{d}].slot_index={d}\n",
            .{
                entry_index, entry.last_priority,
                entry_index, entry.last_budget_ticks,
                entry_index, entry.last_batch_accumulator,
                entry_index, entry.total_accumulator,
                entry_index, entry.compensated_task_count,
                entry_index, entry.total_compensated_task_count,
                entry_index, entry.started,
                entry_index, entry.halted,
                entry_index, entry.slot_index,
            },
        ) catch unreachable;
        used += line_b.len;
        const task_count = @min(@as(usize, @intCast(entry.debt_task_count)), max_task_batch_entries);
        for (0..task_count) |task_index| {
            const task_line = std.fmt.bufPrint(
                buffer[used..],
                "slot[{d}].task[{d}]={d}\n",
                .{ entry_index, task_index, DebtStorage.task_ids[entry.slot_index][task_index] },
            ) catch unreachable;
            used += task_line.len;
        }
    }
    return allocator.dupe(u8, buffer[0..used]);
}

pub fn renderAdmissionAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [4608]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
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
            "slot[{d}].last_priority={d}\nslot[{d}].last_budget_ticks={d}\nslot[{d}].last_batch_accumulator={d}\nslot[{d}].total_accumulator={d}\nslot[{d}].compensated_task_count={d}\nslot[{d}].total_compensated_task_count={d}\nslot[{d}].started={d}\nslot[{d}].halted={d}\nslot[{d}].slot_index={d}\n",
            .{
                entry_index, entry.last_priority,
                entry_index, entry.last_budget_ticks,
                entry_index, entry.last_batch_accumulator,
                entry_index, entry.total_accumulator,
                entry_index, entry.compensated_task_count,
                entry_index, entry.total_compensated_task_count,
                entry_index, entry.started,
                entry_index, entry.halted,
                entry_index, entry.slot_index,
            },
        ) catch unreachable;
        used += line_b.len;
        const task_count = @min(@as(usize, @intCast(entry.admission_task_count + entry.debt_task_count)), max_task_batch_entries);
        for (0..task_count) |task_index| {
            const task_line = std.fmt.bufPrint(
                buffer[used..],
                "slot[{d}].task[{d}]={d}\n",
                .{ entry_index, task_index, AdmissionStorage.task_ids[entry.slot_index][task_index] },
            ) catch unreachable;
            used += task_line.len;
        }
    }
    return allocator.dupe(u8, buffer[0..used]);
}

pub fn renderAgingAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [5120]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
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
        "last_round_waiting_task_count={d}\nlast_round_debt_task_count={d}\ninitial_pending_task_count={d}\nlast_pending_task_count={d}\npeak_pending_task_count={d}\ntask_budget={d}\naging_step={d}\ninitial_min_slot_task_count={d}\ninitial_max_slot_task_count={d}\ninitial_task_balance_gap={d}\nfinal_min_slot_task_count={d}\nfinal_max_slot_task_count={d}\nfinal_task_balance_gap={d}\ninitial_total_debt={d}\nremaining_total_debt={d}\ntotal_compensated_task_count={d}\nlast_round_compensated_task_count={d}\ntotal_aged_task_count={d}\nlast_round_aged_task_count={d}\ntotal_promoted_task_count={d}\npeak_effective_priority={d}\nlast_start_slot_index={d}\n",
        .{
            aging_state.last_round_waiting_task_count,
            aging_state.last_round_debt_task_count,
            aging_state.initial_pending_task_count,
            aging_state.last_pending_task_count,
            aging_state.peak_pending_task_count,
            aging_state.task_budget,
            aging_state.aging_step,
            aging_state.initial_min_slot_task_count,
            aging_state.initial_max_slot_task_count,
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
            aging_state.peak_effective_priority,
            aging_state.last_start_slot_index,
        },
    ) catch unreachable;
    used += tail.len;
    var entry_index: u16 = 0;
    while (entry_index < aging_state.exported_count) : (entry_index += 1) {
        const entry = aging_entries[entry_index];
        const line_a = std.fmt.bufPrint(
            buffer[used..],
            "slot[{d}].target_apic_id={d}\nslot[{d}].dispatch_count={d}\nslot[{d}].waiting_task_count={d}\nslot[{d}].total_waiting_task_count={d}\nslot[{d}].debt_task_count={d}\nslot[{d}].total_debt_task_count={d}\nslot[{d}].seed_task_count={d}\nslot[{d}].final_task_count={d}\nslot[{d}].initial_debt={d}\nslot[{d}].remaining_debt={d}\nslot[{d}].last_task_id={d}\nslot[{d}].last_priority={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.dispatch_count,
                entry_index, entry.waiting_task_count,
                entry_index, entry.total_waiting_task_count,
                entry_index, entry.debt_task_count,
                entry_index, entry.total_debt_task_count,
                entry_index, entry.seed_task_count,
                entry_index, entry.final_task_count,
                entry_index, entry.initial_debt,
                entry_index, entry.remaining_debt,
                entry_index, entry.last_task_id,
                entry_index, entry.last_priority,
            },
        ) catch unreachable;
        used += line_a.len;
        const line_b = std.fmt.bufPrint(
            buffer[used..],
            "slot[{d}].last_effective_priority={d}\nslot[{d}].peak_effective_priority={d}\nslot[{d}].last_budget_ticks={d}\nslot[{d}].last_batch_accumulator={d}\nslot[{d}].total_accumulator={d}\nslot[{d}].compensated_task_count={d}\nslot[{d}].total_compensated_task_count={d}\nslot[{d}].aged_task_count={d}\nslot[{d}].total_aged_task_count={d}\nslot[{d}].started={d}\nslot[{d}].halted={d}\nslot[{d}].slot_index={d}\n",
            .{
                entry_index, entry.last_effective_priority,
                entry_index, entry.peak_effective_priority,
                entry_index, entry.last_budget_ticks,
                entry_index, entry.last_batch_accumulator,
                entry_index, entry.total_accumulator,
                entry_index, entry.compensated_task_count,
                entry_index, entry.total_compensated_task_count,
                entry_index, entry.aged_task_count,
                entry_index, entry.total_aged_task_count,
                entry_index, entry.started,
                entry_index, entry.halted,
                entry_index, entry.slot_index,
            },
        ) catch unreachable;
        used += line_b.len;
        const task_count = @min(@as(usize, @intCast(entry.waiting_task_count + entry.debt_task_count)), max_task_batch_entries);
        for (0..task_count) |task_index| {
            const task_line = std.fmt.bufPrint(
                buffer[used..],
                "slot[{d}].task[{d}]={d}\n",
                .{ entry_index, task_index, AgingStorage.task_ids[entry.slot_index][task_index] },
            ) catch unreachable;
            used += task_line.len;
        }
    }
    return allocator.dupe(u8, buffer[0..used]);
}

pub fn renderFairshareAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [5632]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
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
        "last_round_waiting_task_count={d}\nlast_round_debt_task_count={d}\nlast_round_fairshare_task_count={d}\ninitial_pending_task_count={d}\nlast_pending_task_count={d}\npeak_pending_task_count={d}\ntask_budget={d}\naging_step={d}\ninitial_min_slot_task_count={d}\ninitial_max_slot_task_count={d}\ninitial_task_balance_gap={d}\nfinal_min_slot_task_count={d}\nfinal_max_slot_task_count={d}\nfinal_task_balance_gap={d}\ninitial_total_debt={d}\nremaining_total_debt={d}\ntotal_compensated_task_count={d}\nlast_round_compensated_task_count={d}\ntotal_aged_task_count={d}\nlast_round_aged_task_count={d}\ntotal_promoted_task_count={d}\ntotal_fairshare_task_count={d}\npeak_effective_priority={d}\nlast_start_slot_index={d}\n",
        .{
            fairshare_state.last_round_waiting_task_count,
            fairshare_state.last_round_debt_task_count,
            fairshare_state.last_round_fairshare_task_count,
            fairshare_state.initial_pending_task_count,
            fairshare_state.last_pending_task_count,
            fairshare_state.peak_pending_task_count,
            fairshare_state.task_budget,
            fairshare_state.aging_step,
            fairshare_state.initial_min_slot_task_count,
            fairshare_state.initial_max_slot_task_count,
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
            fairshare_state.peak_effective_priority,
            fairshare_state.last_start_slot_index,
        },
    ) catch unreachable;
    used += tail.len;
    var entry_index: u16 = 0;
    while (entry_index < fairshare_state.exported_count) : (entry_index += 1) {
        const entry = fairshare_entries[entry_index];
        const line_a = std.fmt.bufPrint(
            buffer[used..],
            "slot[{d}].target_apic_id={d}\nslot[{d}].dispatch_count={d}\nslot[{d}].waiting_task_count={d}\nslot[{d}].total_waiting_task_count={d}\nslot[{d}].debt_task_count={d}\nslot[{d}].total_debt_task_count={d}\nslot[{d}].fairshare_task_count={d}\nslot[{d}].total_fairshare_task_count={d}\nslot[{d}].seed_task_count={d}\nslot[{d}].final_task_count={d}\nslot[{d}].initial_debt={d}\nslot[{d}].remaining_debt={d}\nslot[{d}].last_task_id={d}\nslot[{d}].last_priority={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.dispatch_count,
                entry_index, entry.waiting_task_count,
                entry_index, entry.total_waiting_task_count,
                entry_index, entry.debt_task_count,
                entry_index, entry.total_debt_task_count,
                entry_index, entry.fairshare_task_count,
                entry_index, entry.total_fairshare_task_count,
                entry_index, entry.seed_task_count,
                entry_index, entry.final_task_count,
                entry_index, entry.initial_debt,
                entry_index, entry.remaining_debt,
                entry_index, entry.last_task_id,
                entry_index, entry.last_priority,
            },
        ) catch unreachable;
        used += line_a.len;
        const line_b = std.fmt.bufPrint(
            buffer[used..],
            "slot[{d}].last_effective_priority={d}\nslot[{d}].peak_effective_priority={d}\nslot[{d}].last_budget_ticks={d}\nslot[{d}].last_batch_accumulator={d}\nslot[{d}].total_accumulator={d}\nslot[{d}].compensated_task_count={d}\nslot[{d}].total_compensated_task_count={d}\nslot[{d}].aged_task_count={d}\nslot[{d}].total_aged_task_count={d}\nslot[{d}].started={d}\nslot[{d}].halted={d}\nslot[{d}].slot_index={d}\n",
            .{
                entry_index, entry.last_effective_priority,
                entry_index, entry.peak_effective_priority,
                entry_index, entry.last_budget_ticks,
                entry_index, entry.last_batch_accumulator,
                entry_index, entry.total_accumulator,
                entry_index, entry.compensated_task_count,
                entry_index, entry.total_compensated_task_count,
                entry_index, entry.aged_task_count,
                entry_index, entry.total_aged_task_count,
                entry_index, entry.started,
                entry_index, entry.halted,
                entry_index, entry.slot_index,
            },
        ) catch unreachable;
        used += line_b.len;
        const task_count = @min(@as(usize, @intCast(entry.waiting_task_count + entry.debt_task_count)), max_task_batch_entries);
        for (0..task_count) |task_index| {
            const task_line = std.fmt.bufPrint(
                buffer[used..],
                "slot[{d}].task[{d}]={d}\n",
                .{ entry_index, task_index, FairshareStorage.task_ids[entry.slot_index][task_index] },
            ) catch unreachable;
            used += task_line.len;
        }
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
        if (slot_index >= backfill_state.exported_count) break;
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
        const exported_index = window_state.exported_count;
        window_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .dispatch_count = dispatch_count,
            .window_task_count = window_task_count,
            .total_window_task_count = total_window_task_count,
            .last_task_id = WindowStorage.last_task_id[slot_index],
            .last_priority = WindowStorage.last_priority[slot_index],
            .last_budget_ticks = WindowStorage.last_budget_ticks[slot_index],
            .last_batch_accumulator = WindowStorage.last_batch_accumulator[slot_index],
            .total_accumulator = total_accumulator,
            .started = started,
            .halted = halted,
            .slot_index = @as(u8, @intCast(slot_index)),
            .reserved0 = 0,
        };
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
        const exported_index = fairness_state.exported_count;
        fairness_entries[exported_index] = .{
            .target_apic_id = target_apic_id,
            .dispatch_count = dispatch_count,
            .drained_task_count = drained_task_count,
            .total_drained_task_count = total_drained_task_count,
            .last_task_id = FairnessStorage.last_task_id[slot_index],
            .last_priority = FairnessStorage.last_priority[slot_index],
            .last_budget_ticks = FairnessStorage.last_budget_ticks[slot_index],
            .last_batch_accumulator = FairnessStorage.last_batch_accumulator[slot_index],
            .total_accumulator = total_accumulator,
            .started = started,
            .halted = halted,
            .slot_index = @as(u8, @intCast(slot_index)),
            .reserved0 = 0,
        };
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
            .last_priority = RebalanceStorage.last_priority[slot_index],
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
            .last_priority = DebtStorage.last_priority[slot_index],
            .last_budget_ticks = DebtStorage.last_budget_ticks[slot_index],
            .last_batch_accumulator = DebtStorage.last_batch_accumulator[slot_index],
            .total_accumulator = total_accumulator,
            .compensated_task_count = DebtStorage.compensated_task_count[slot_index],
            .total_compensated_task_count = total_compensated_task_count,
            .started = started,
            .halted = halted,
            .slot_index = @as(u8, @intCast(slot_index)),
            .reserved0 = 0,
        };
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
            .last_priority = AdmissionStorage.last_priority[slot_index],
            .last_budget_ticks = AdmissionStorage.last_budget_ticks[slot_index],
            .last_batch_accumulator = AdmissionStorage.last_batch_accumulator[slot_index],
            .total_accumulator = total_accumulator,
            .compensated_task_count = AdmissionStorage.compensated_task_count[slot_index],
            .total_compensated_task_count = total_compensated_task_count,
            .started = started,
            .halted = halted,
            .slot_index = @as(u8, @intCast(slot_index)),
            .reserved0 = 0,
        };
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
    aging_state.peak_effective_priority = aging_peak_effective_priority;
    aging_state.last_start_slot_index = aging_last_start_slot_index;
    @memset(&aging_entries, std.mem.zeroes(abi.BaremetalApAgingEntry));
    slot_index = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const target_apic_id = readStateVar(slotTargetApicIdPtr(slot_index));
        const started = if (readStateVar(slotStartedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const halted = if (readStateVar(slotHaltedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const waiting_task_count = AgingStorage.waiting_task_count[slot_index];
        const total_waiting_task_count = AgingStorage.total_waiting_task_count[slot_index];
        const debt_task_count = AgingStorage.debt_task_count[slot_index];
        const total_debt_task_count = AgingStorage.total_debt_task_count[slot_index];
        const seed_task_count = AgingStorage.seed_task_count[slot_index];
        const final_task_count = AgingStorage.final_task_count[slot_index];
        const total_accumulator = AgingStorage.total_accumulator[slot_index];
        const total_compensated_task_count = AgingStorage.total_compensated_task_count[slot_index];
        const total_aged_task_count = AgingStorage.total_aged_task_count[slot_index];
        const remaining_debt = AgingStorage.remaining_debt[slot_index];
        if (target_apic_id == 0 and
            waiting_task_count == 0 and
            total_waiting_task_count == 0 and
            debt_task_count == 0 and
            total_debt_task_count == 0 and
            seed_task_count == 0 and
            final_task_count == 0 and
            total_accumulator == 0 and
            total_compensated_task_count == 0 and
            total_aged_task_count == 0 and
            remaining_debt == 0 and
            started == 0 and
            halted == 0)
        {
            continue;
        }
        const dispatch_count = AgingStorage.dispatch_count[slot_index];
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
            .last_priority = AgingStorage.last_priority[slot_index],
            .last_effective_priority = AgingStorage.last_effective_priority[slot_index],
            .peak_effective_priority = AgingStorage.peak_effective_priority[slot_index],
            .last_budget_ticks = AgingStorage.last_budget_ticks[slot_index],
            .last_batch_accumulator = AgingStorage.last_batch_accumulator[slot_index],
            .total_accumulator = total_accumulator,
            .compensated_task_count = AgingStorage.compensated_task_count[slot_index],
            .total_compensated_task_count = total_compensated_task_count,
            .aged_task_count = AgingStorage.aged_task_count[slot_index],
            .total_aged_task_count = total_aged_task_count,
            .started = started,
            .halted = halted,
            .slot_index = @as(u8, @intCast(slot_index)),
            .reserved0 = 0,
        };
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
    fairshare_state.peak_effective_priority = fairshare_peak_effective_priority;
    fairshare_state.last_start_slot_index = fairshare_last_start_slot_index;
    @memset(&fairshare_entries, std.mem.zeroes(abi.BaremetalApFairshareEntry));
    slot_index = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const target_apic_id = readStateVar(slotTargetApicIdPtr(slot_index));
        const started = if (readStateVar(slotStartedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const halted = if (readStateVar(slotHaltedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const waiting_task_count = FairshareStorage.waiting_task_count[slot_index];
        const total_waiting_task_count = FairshareStorage.total_waiting_task_count[slot_index];
        const debt_task_count = FairshareStorage.debt_task_count[slot_index];
        const total_debt_task_count = FairshareStorage.total_debt_task_count[slot_index];
        const fairshare_task_count = FairshareStorage.fairshare_task_count[slot_index];
        const total_fairshare_task_count = FairshareStorage.total_fairshare_task_count[slot_index];
        const seed_task_count = FairshareStorage.seed_task_count[slot_index];
        const final_task_count = FairshareStorage.final_task_count[slot_index];
        const total_accumulator = FairshareStorage.total_accumulator[slot_index];
        const total_compensated_task_count = FairshareStorage.total_compensated_task_count[slot_index];
        const total_aged_task_count = FairshareStorage.total_aged_task_count[slot_index];
        const remaining_debt = FairshareStorage.remaining_debt[slot_index];
        if (target_apic_id == 0 and
            waiting_task_count == 0 and
            total_waiting_task_count == 0 and
            debt_task_count == 0 and
            total_debt_task_count == 0 and
            fairshare_task_count == 0 and
            total_fairshare_task_count == 0 and
            seed_task_count == 0 and
            final_task_count == 0 and
            total_accumulator == 0 and
            total_compensated_task_count == 0 and
            total_aged_task_count == 0 and
            remaining_debt == 0 and
            started == 0 and
            halted == 0)
        {
            continue;
        }
        const dispatch_count = FairshareStorage.dispatch_count[slot_index];
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
            .last_priority = FairshareStorage.last_priority[slot_index],
            .last_effective_priority = FairshareStorage.last_effective_priority[slot_index],
            .peak_effective_priority = FairshareStorage.peak_effective_priority[slot_index],
            .last_budget_ticks = FairshareStorage.last_budget_ticks[slot_index],
            .last_batch_accumulator = FairshareStorage.last_batch_accumulator[slot_index],
            .total_accumulator = total_accumulator,
            .compensated_task_count = FairshareStorage.compensated_task_count[slot_index],
            .total_compensated_task_count = total_compensated_task_count,
            .aged_task_count = FairshareStorage.aged_task_count[slot_index],
            .total_aged_task_count = total_aged_task_count,
            .started = started,
            .halted = halted,
            .slot_index = @as(u8, @intCast(slot_index)),
            .reserved0 = 0,
        };
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
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 1, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 3, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
    };

    const total_accumulator = try dispatchOwnedSchedulerTasksRoundRobin(tasks[0..]);
    try std.testing.expectEqual(@as(u32, 15), total_accumulator);

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_round_robin), snapshot.policy);
    try std.testing.expectEqual(@as(u8, 2), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 2), snapshot.active_count);
    try std.testing.expectEqual(@as(u32, 5), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 15), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), snapshot.dispatch_round_count);

    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 1), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 5), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 7), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 13), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 9), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 3), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 11), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 6), second_entry.last_batch_accumulator);

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
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 1, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 3, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
    };

    try std.testing.expectEqual(@as(u32, 15), try dispatchOwnedSchedulerTasksRoundRobin(tasks[0..]));
    try std.testing.expectEqual(@as(u32, 15), try dispatchOwnedSchedulerTasksRoundRobinFromOffset(tasks[0..], 1));

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
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

    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 5), first_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 3), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 11), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 6), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 15), first_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 2), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 4), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][1]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 3), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 5), second_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 3), second_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 3), second_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 5), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 7), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 13), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 9), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 15), second_entry.total_accumulator);
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

test "i386 ap startup dispatches scheduler-owned tasks by priority policy" {
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
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 1, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 3, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
    };

    try std.testing.expectEqual(@as(u32, 15), try dispatchOwnedSchedulerTasksPriority(tasks[0..]));

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    try std.testing.expectEqual(@as(u8, 2), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 2), snapshot.active_count);
    try std.testing.expectEqual(@as(u32, 5), snapshot.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), snapshot.total_dispatch_count);
    try std.testing.expectEqual(@as(u32, 15), snapshot.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), snapshot.dispatch_round_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 0), snapshot.last_start_slot_index);

    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 1), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 5), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 6), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 3), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 2), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][1]);
    try std.testing.expectEqual(@as(u32, 1), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][2]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 3), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 11), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 9), second_entry.last_batch_accumulator);
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

test "i386 ap startup reprioritizes scheduler-owned tasks across priority rounds" {
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

    const tasks_round_one = [_]abi.BaremetalTask{
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 1, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 3, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
    };
    const tasks_round_two = [_]abi.BaremetalTask{
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 10, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 8, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 0, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
    };

    try std.testing.expectEqual(@as(u32, 15), try dispatchOwnedSchedulerTasksPriority(tasks_round_one[0..]));
    try std.testing.expectEqual(@as(u32, 15), try dispatchOwnedSchedulerTasksPriority(tasks_round_two[0..]));

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
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

    const first_entry = ownershipEntry(0);
    const second_entry = ownershipEntry(1);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 3), first_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 6), first_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 5), first_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 0), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 13), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 10), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 16), first_entry.total_accumulator);
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
    try std.testing.expectEqual(@as(u32, 5), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 5), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 14), second_entry.total_accumulator);
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

test "i386 ap startup rotates priority-owned tasks across three slots and rounds" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..3) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }

    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    errdefer {
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    const tasks_round_one = [_]abi.BaremetalTask{
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 1, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 3, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 6, .state = abi.task_state_ready, .priority = 2, .reserved0 = 0, .run_count = 0, .budget_ticks = 15, .budget_remaining = 15, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 7, .state = abi.task_state_ready, .priority = 8, .reserved0 = 0, .run_count = 0, .budget_ticks = 17, .budget_remaining = 17, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 8, .state = abi.task_state_ready, .priority = 4, .reserved0 = 0, .run_count = 0, .budget_ticks = 19, .budget_remaining = 19, .created_tick = 0, .last_run_tick = 0 },
    };
    const tasks_round_two = [_]abi.BaremetalTask{
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 10, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 6, .state = abi.task_state_ready, .priority = 2, .reserved0 = 0, .run_count = 0, .budget_ticks = 15, .budget_remaining = 15, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 7, .state = abi.task_state_ready, .priority = 0, .reserved0 = 0, .run_count = 0, .budget_ticks = 17, .budget_remaining = 17, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 8, .state = abi.task_state_ready, .priority = 4, .reserved0 = 0, .run_count = 0, .budget_ticks = 19, .budget_remaining = 19, .created_tick = 0, .last_run_tick = 0 },
    };
    const tasks_round_three = [_]abi.BaremetalTask{
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 10, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 1, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 6, .state = abi.task_state_ready, .priority = 11, .reserved0 = 0, .run_count = 0, .budget_ticks = 15, .budget_remaining = 15, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 7, .state = abi.task_state_ready, .priority = 0, .reserved0 = 0, .run_count = 0, .budget_ticks = 17, .budget_remaining = 17, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 8, .state = abi.task_state_ready, .priority = 10, .reserved0 = 0, .run_count = 0, .budget_ticks = 19, .budget_remaining = 19, .created_tick = 0, .last_run_tick = 0 },
    };

    try std.testing.expectEqual(@as(u32, 36), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_one[0..], 0));
    try std.testing.expectEqual(@as(u32, 36), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_two[0..], 1));
    try std.testing.expectEqual(@as(u32, 36), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_three[0..], 2));

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
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
    try std.testing.expectEqual(@as(u32, 0), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 17), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 13), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 36), first_entry.total_accumulator);
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
    try std.testing.expectEqual(@as(u32, 5), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 10), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 38), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 8), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 2), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][1]);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 3), third_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 8), third_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 5), third_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 3), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 13), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 34), third_entry.total_accumulator);
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

test "i386 ap startup rotates priority-owned tasks across four slots and rounds" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..4) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }

    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    const responder3 = try std.Thread.spawn(.{}, testApSlotResponder, .{3});
    defer responder3.join();
    errdefer {
        _ = haltApSlot(3) catch {};
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    const tasks_round_one = [_]abi.BaremetalTask{
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 1, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 3, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 6, .state = abi.task_state_ready, .priority = 2, .reserved0 = 0, .run_count = 0, .budget_ticks = 15, .budget_remaining = 15, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 7, .state = abi.task_state_ready, .priority = 8, .reserved0 = 0, .run_count = 0, .budget_ticks = 17, .budget_remaining = 17, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 8, .state = abi.task_state_ready, .priority = 4, .reserved0 = 0, .run_count = 0, .budget_ticks = 19, .budget_remaining = 19, .created_tick = 0, .last_run_tick = 0 },
    };
    const tasks_round_two = [_]abi.BaremetalTask{
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 10, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 6, .state = abi.task_state_ready, .priority = 2, .reserved0 = 0, .run_count = 0, .budget_ticks = 15, .budget_remaining = 15, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 7, .state = abi.task_state_ready, .priority = 0, .reserved0 = 0, .run_count = 0, .budget_ticks = 17, .budget_remaining = 17, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 8, .state = abi.task_state_ready, .priority = 4, .reserved0 = 0, .run_count = 0, .budget_ticks = 19, .budget_remaining = 19, .created_tick = 0, .last_run_tick = 0 },
    };
    const tasks_round_three = [_]abi.BaremetalTask{
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 10, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 1, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 6, .state = abi.task_state_ready, .priority = 11, .reserved0 = 0, .run_count = 0, .budget_ticks = 15, .budget_remaining = 15, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 7, .state = abi.task_state_ready, .priority = 0, .reserved0 = 0, .run_count = 0, .budget_ticks = 17, .budget_remaining = 17, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 8, .state = abi.task_state_ready, .priority = 10, .reserved0 = 0, .run_count = 0, .budget_ticks = 19, .budget_remaining = 19, .created_tick = 0, .last_run_tick = 0 },
    };
    const tasks_round_four = [_]abi.BaremetalTask{
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 10, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 12, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 1, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 0, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 11, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 6, .state = abi.task_state_ready, .priority = 11, .reserved0 = 0, .run_count = 0, .budget_ticks = 15, .budget_remaining = 15, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 7, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 17, .budget_remaining = 17, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 8, .state = abi.task_state_ready, .priority = 10, .reserved0 = 0, .run_count = 0, .budget_ticks = 19, .budget_remaining = 19, .created_tick = 0, .last_run_tick = 0 },
    };

    try std.testing.expectEqual(@as(u32, 36), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_one[0..], 0));
    try std.testing.expectEqual(@as(u32, 36), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_two[0..], 1));
    try std.testing.expectEqual(@as(u32, 36), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_three[0..], 2));
    try std.testing.expectEqual(@as(u32, 36), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_four[0..], 3));

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
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
    try std.testing.expectEqual(@as(u32, 9), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 17), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 12), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 46), first_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 5), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 7), OwnershipStorage.owned_task_ids[@as(usize, first_entry.slot_index)][1]);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 8), second_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 6), second_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 3), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 9), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 34), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 6), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 3), OwnershipStorage.owned_task_ids[@as(usize, second_entry.slot_index)][1]);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 8), third_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 6), third_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 0), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 11), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 5), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 38), third_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 4), OwnershipStorage.owned_task_ids[@as(usize, third_entry.slot_index)][1]);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.owned_task_count);
    try std.testing.expectEqual(@as(u32, 8), fourth_entry.total_owned_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 5), fourth_entry.total_redistributed_task_count);
    try std.testing.expectEqual(@as(u32, 8), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 10), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 19), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 10), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 26), fourth_entry.total_accumulator);
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

test "i386 ap startup saturates priority-owned tasks across four slots" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..4) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }

    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    const responder3 = try std.Thread.spawn(.{}, testApSlotResponder, .{3});
    defer responder3.join();
    errdefer {
        _ = haltApSlot(3) catch {};
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    var tasks: [16]abi.BaremetalTask = undefined;
    for (&tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const priority = @as(u8, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast(index * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = priority,
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks[0..], 0));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks[0..], 1));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks[0..], 2));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks[0..], 3));

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
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
    try std.testing.expectEqual(@as(u32, 3), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 36), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 136), first_entry.total_accumulator);
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
    try std.testing.expectEqual(@as(u32, 2), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 32), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 136), second_entry.total_accumulator);
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
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 5), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 28), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 136), third_entry.total_accumulator);
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
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 11), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 40), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 136), fourth_entry.total_accumulator);
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

test "i386 ap startup reprioritizes saturated priority-owned tasks across four slots" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..4) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }

    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    const responder3 = try std.Thread.spawn(.{}, testApSlotResponder, .{3});
    defer responder3.join();
    errdefer {
        _ = haltApSlot(3) catch {};
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    var tasks_round_one: [16]abi.BaremetalTask = undefined;
    var tasks_round_five: [16]abi.BaremetalTask = undefined;
    for (&tasks_round_one, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast(index * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(index + 1)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }
    for (&tasks_round_five, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast(index * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(tasks_round_five.len - index)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_one[0..], 0));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_one[0..], 1));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_one[0..], 2));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_one[0..], 3));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_five[0..], 0));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks_round_five[0..], 2));

    var snapshot = ownershipStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
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
    try std.testing.expectEqual(@as(u32, 2), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 33), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 36), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 200), first_entry.total_accumulator);
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
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 35), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 40), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 208), second_entry.total_accumulator);
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
    try std.testing.expectEqual(@as(u32, 4), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 29), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 28), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 200), third_entry.total_accumulator);
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
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 31), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 32), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 208), fourth_entry.total_accumulator);
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

test "i386 ap startup fails over saturated priority-owned tasks after slot retirement" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..4) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }

    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    const responder3 = try std.Thread.spawn(.{}, testApSlotResponder, .{3});
    defer responder3.join();
    errdefer {
        _ = haltApSlot(3) catch {};
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    var tasks: [16]abi.BaremetalTask = undefined;
    for (&tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast(index * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(index + 1)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks[0..], 0));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks[0..], 1));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks[0..], 2));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks[0..], 3));
    try retireApSlot(3);
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks[0..], 0));
    try std.testing.expectEqual(@as(u32, 136), try dispatchOwnedSchedulerTasksPriorityFromOffset(tasks[0..], 1));

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
    try std.testing.expectEqual(@as(u32, 2), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 40), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 227), first_entry.total_accumulator);
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
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 5), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 51), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 232), second_entry.total_accumulator);
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
    try std.testing.expectEqual(@as(u32, 3), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 45), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 221), third_entry.total_accumulator);
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
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 136), fourth_entry.total_accumulator);
    try std.testing.expectEqual(@as(u8, 1), fourth_entry.started);
    try std.testing.expectEqual(@as(u8, 1), fourth_entry.halted);

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

test "i386 ap startup dispatches bounded priority window tasks across four slots" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..4) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }

    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    const responder3 = try std.Thread.spawn(.{}, testApSlotResponder, .{3});
    defer responder3.join();
    errdefer {
        _ = haltApSlot(3) catch {};
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    var tasks: [16]abi.BaremetalTask = undefined;
    for (&tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast(index * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(index + 1)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    try std.testing.expectEqual(@as(u32, 81), try dispatchWindowedSchedulerTasksPriorityFromOffset(tasks[0..], 0, 6));
    try std.testing.expectEqual(@as(u32, 45), try dispatchWindowedSchedulerTasksPriorityFromOffset(tasks[0..], 1, 6));
    try std.testing.expectEqual(@as(u32, 10), try dispatchWindowedSchedulerTasksPriorityFromOffset(tasks[0..], 2, 6));

    const snapshot = windowStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
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

test "i386 ap startup drains bounded priority windows fairly across four slots" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..4) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }

    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    const responder3 = try std.Thread.spawn(.{}, testApSlotResponder, .{3});
    defer responder3.join();
    errdefer {
        _ = haltApSlot(3) catch {};
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    var tasks: [16]abi.BaremetalTask = undefined;
    for (&tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast(index * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(index + 1)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    try std.testing.expectEqual(@as(u32, 136), try dispatchWindowedSchedulerTasksPriorityUntilDrainedFromOffset(tasks[0..], 0, 5));

    const snapshot = fairnessStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
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
    try std.testing.expectEqual(@as(u32, 4), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 11), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 4), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 40), first_entry.total_accumulator);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), second_entry.drained_task_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.total_drained_task_count);
    try std.testing.expectEqual(@as(u32, 3), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 3), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 3), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 36), second_entry.total_accumulator);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), third_entry.drained_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.total_drained_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 2), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 8), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 32), third_entry.total_accumulator);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.drained_task_count);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.total_drained_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 5), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 28), fourth_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), FairnessStorage.task_ids[@as(usize, fourth_entry.slot_index)][0]);

    const fairness_render = try renderFairnessAlloc(std.testing.allocator);
    defer std.testing.allocator.free(fairness_render);
    try std.testing.expect(std.mem.indexOf(u8, fairness_render, "total_drained_task_count=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairness_render, "total_dispatch_count=13") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairness_render, "drain_round_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairness_render, "last_pending_task_count=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairness_render, "task_balance_gap=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairness_render, "slot[3].task[0]=1") != null);

    try haltApSlot(3);
    try haltApSlot(2);
    try haltApSlot(1);
    try haltApSlot(0);
}

test "i386 ap startup rebalances bounded priority backlog from skewed seed totals" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..4) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }

    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    const responder3 = try std.Thread.spawn(.{}, testApSlotResponder, .{3});
    defer responder3.join();
    errdefer {
        _ = haltApSlot(3) catch {};
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    var preload_tasks: [10]abi.BaremetalTask = undefined;
    for (&preload_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 7));
        const budget_ticks = @as(u32, @intCast((task_id - 1) * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(task_id)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    var rebalance_tasks: [6]abi.BaremetalTask = undefined;
    for (&rebalance_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast(index * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(task_id)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    resetWindowState();
    try std.testing.expectEqual(@as(u32, 70), try dispatchWindowedSchedulerTasksPriorityFromOffset(preload_tasks[0..], 0, 5));
    try std.testing.expectEqual(@as(u32, 45), try dispatchWindowedSchedulerTasksPriorityFromOffset(preload_tasks[0..], 0, 5));
    try std.testing.expectEqual(@as(u32, 21), try dispatchRebalancedSchedulerTasksPriorityUntilDrainedFromOffset(rebalance_tasks[0..], 0, 4));

    const snapshot = rebalanceStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
    try std.testing.expectEqual(@as(u8, 4), snapshot.exported_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.active_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.peak_active_slot_count);
    try std.testing.expectEqual(@as(u8, 4), snapshot.last_round_active_slot_count);
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
    try std.testing.expectEqual(@as(u32, 2), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 2), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 8), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), second_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.total_rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 5), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 6), third_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), third_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.total_rebalanced_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 7), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 7), fourth_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.total_compensated_task_count);

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

test "i386 ap startup carries bounded priority debt across rounds" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..4) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }

    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    const responder3 = try std.Thread.spawn(.{}, testApSlotResponder, .{3});
    defer responder3.join();
    errdefer {
        _ = haltApSlot(3) catch {};
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    var preload_tasks: [10]abi.BaremetalTask = undefined;
    for (&preload_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 7));
        const budget_ticks = @as(u32, @intCast((task_id - 1) * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(task_id)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    var debt_tasks: [4]abi.BaremetalTask = undefined;
    for (&debt_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast(index * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(task_id)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    resetWindowState();
    try std.testing.expectEqual(@as(u32, 70), try dispatchWindowedSchedulerTasksPriorityFromOffset(preload_tasks[0..], 0, 5));
    try std.testing.expectEqual(@as(u32, 45), try dispatchWindowedSchedulerTasksPriorityFromOffset(preload_tasks[0..], 0, 5));
    try std.testing.expectEqual(@as(u32, 10), try dispatchDebtAwareSchedulerTasksPriorityUntilDrainedFromOffset(debt_tasks[0..], 0, 2));

    const snapshot = debtStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
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
    try std.testing.expectEqual(@as(u32, 4), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 11), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 4), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 4), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 0), second_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.debt_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), third_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 5), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 4), third_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), third_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.debt_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 1), DebtStorage.task_ids[@as(usize, third_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 2), DebtStorage.task_ids[@as(usize, fourth_entry.slot_index)][0]);

    const debt_render = try renderDebtAlloc(std.testing.allocator);
    defer std.testing.allocator.free(debt_render);
    try std.testing.expect(std.mem.indexOf(u8, debt_render, "total_debt_task_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, debt_render, "total_dispatch_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, debt_render, "total_accumulator=10") != null);
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

test "i386 debt-aware priority scheduler admits higher-priority tasks into carried debt state" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..4) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }
    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    const responder3 = try std.Thread.spawn(.{}, testApSlotResponder, .{3});
    defer responder3.join();
    errdefer {
        _ = haltApSlot(3) catch {};
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    var preload_tasks: [10]abi.BaremetalTask = undefined;
    for (&preload_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 7));
        const budget_ticks = @as(u32, @intCast((task_id - 1) * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(task_id)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    var debt_tasks: [4]abi.BaremetalTask = undefined;
    for (&debt_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast(index * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(task_id)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    const admitted_tasks = [_]abi.BaremetalTask{
        .{
            .task_id = 5,
            .state = abi.task_state_ready,
            .priority = 20,
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = 13,
            .budget_remaining = 13,
            .created_tick = 0,
            .last_run_tick = 0,
        },
        .{
            .task_id = 6,
            .state = abi.task_state_ready,
            .priority = 19,
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = 15,
            .budget_remaining = 15,
            .created_tick = 0,
            .last_run_tick = 0,
        },
    };

    resetWindowState();
    try std.testing.expectEqual(@as(u32, 70), try dispatchWindowedSchedulerTasksPriorityFromOffset(preload_tasks[0..], 0, 5));
    try std.testing.expectEqual(@as(u32, 45), try dispatchWindowedSchedulerTasksPriorityFromOffset(preload_tasks[0..], 0, 5));
    try std.testing.expectEqual(@as(u32, 21), try dispatchDebtAwareSchedulerTasksPriorityWithAdmissionFromOffset(
        debt_tasks[0..],
        admitted_tasks[0..],
        0,
        2,
    ));

    const snapshot = admissionStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
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
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 5), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 6), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), second_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), third_entry.admission_task_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.total_admitted_task_count);
    try std.testing.expectEqual(@as(u32, 0), third_entry.debt_task_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), third_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 3), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 3), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 3), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 9), third_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 0), third_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.admission_task_count);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.total_admitted_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.debt_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 6), fourth_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 1), AdmissionStorage.task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 2), AdmissionStorage.task_ids[@as(usize, fourth_entry.slot_index)][0]);

    const admission_render = try renderAdmissionAlloc(std.testing.allocator);
    defer std.testing.allocator.free(admission_render);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "total_admitted_task_count=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "total_debt_task_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "total_dispatch_count=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "total_accumulator=21") != null);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "final_task_balance_gap=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "remaining_total_debt=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "slot[1].total_admitted_task_count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, admission_render, "slot[2].total_admitted_task_count=1") != null);

    try haltApSlot(3);
    try haltApSlot(2);
    try haltApSlot(1);
    try haltApSlot(0);
}

test "i386 debt-aware priority scheduler ages waiting tasks into carried debt state" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..4) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }
    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    const responder3 = try std.Thread.spawn(.{}, testApSlotResponder, .{3});
    defer responder3.join();
    errdefer {
        _ = haltApSlot(3) catch {};
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    var preload_tasks: [10]abi.BaremetalTask = undefined;
    for (&preload_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 7));
        const budget_ticks = @as(u32, @intCast((task_id - 1) * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(task_id)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    var debt_tasks: [4]abi.BaremetalTask = undefined;
    for (&debt_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast(index * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(task_id)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    const waiting_tasks = [_]abi.BaremetalTask{
        .{
            .task_id = 5,
            .state = abi.task_state_ready,
            .priority = 0,
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = 13,
            .budget_remaining = 13,
            .created_tick = 0,
            .last_run_tick = 0,
        },
        .{
            .task_id = 6,
            .state = abi.task_state_ready,
            .priority = 0,
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = 15,
            .budget_remaining = 15,
            .created_tick = 0,
            .last_run_tick = 0,
        },
    };

    resetWindowState();
    try std.testing.expectEqual(@as(u32, 70), try dispatchWindowedSchedulerTasksPriorityFromOffset(preload_tasks[0..], 0, 5));
    try std.testing.expectEqual(@as(u32, 45), try dispatchWindowedSchedulerTasksPriorityFromOffset(preload_tasks[0..], 0, 5));
    try std.testing.expectEqual(@as(u32, 21), try dispatchDebtAwareSchedulerTasksPriorityWithAgingFromOffset(
        debt_tasks[0..],
        waiting_tasks[0..],
        0,
        2,
        3,
    ));

    const snapshot = agingStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
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
    try std.testing.expectEqual(@as(u32, 3), snapshot.peak_effective_priority);
    try std.testing.expectEqual(@as(u32, 2), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u16, 4), agingEntryCount());
    const first_entry = agingEntry(0);
    const second_entry = agingEntry(1);
    const third_entry = agingEntry(2);
    const fourth_entry = agingEntry(3);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 0), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.total_waiting_task_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), first_entry.remaining_debt);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), second_entry.waiting_task_count);
    try std.testing.expectEqual(@as(u32, 0), second_entry.total_waiting_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), second_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_effective_priority);
    try std.testing.expectEqual(@as(u32, 4), second_entry.peak_effective_priority);
    try std.testing.expectEqual(@as(u32, 5), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 2), second_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), third_entry.waiting_task_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.total_waiting_task_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), third_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 6), third_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 0), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 3), third_entry.last_effective_priority);
    try std.testing.expectEqual(@as(u32, 3), third_entry.peak_effective_priority);
    try std.testing.expectEqual(@as(u32, 9), third_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 2), third_entry.total_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.total_aged_task_count);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.waiting_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.total_waiting_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.total_debt_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.last_effective_priority);
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.peak_effective_priority);
    try std.testing.expectEqual(@as(u32, 7), fourth_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.total_compensated_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.total_aged_task_count);

    try std.testing.expectEqual(@as(u32, 1), AgingStorage.task_ids[@as(usize, second_entry.slot_index)][0]);
    try std.testing.expectEqual(@as(u32, 2), AgingStorage.task_ids[@as(usize, fourth_entry.slot_index)][0]);

    const aging_render = try renderAgingAlloc(std.testing.allocator);
    defer std.testing.allocator.free(aging_render);
    try std.testing.expect(std.mem.indexOf(u8, aging_render, "total_waiting_task_count=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, aging_render, "total_debt_task_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, aging_render, "total_dispatch_count=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, aging_render, "total_accumulator=21") != null);
    try std.testing.expect(std.mem.indexOf(u8, aging_render, "aging_round_count=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, aging_render, "total_aged_task_count=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, aging_render, "total_promoted_task_count=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, aging_render, "remaining_total_debt=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, aging_render, "slot[1].task[0]=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, aging_render, "slot[3].task[0]=2") != null);

    try haltApSlot(3);
    try haltApSlot(2);
    try haltApSlot(1);
    try haltApSlot(0);
}

test "i386 debt-aware priority scheduler drains broader fairshare backlog after carried debt" {
    resetForTest();
    acpi.resetForTest();
    try acpi.probeSyntheticImage(true);

    for (0..4) |slot_index| {
        writeStateVar(slotStartedPtr(slot_index), 1);
        writeStateVar(slotStagePtr(slot_index), 4);
        writeStateVar(slotReportedApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotTargetApicIdPtr(slot_index), @as(u32, @intCast(slot_index + 1)));
        writeStateVar(slotHeartbeatPtr(slot_index), 1);
    }

    const responder0 = try std.Thread.spawn(.{}, testApSlotResponder, .{0});
    defer responder0.join();
    const responder1 = try std.Thread.spawn(.{}, testApSlotResponder, .{1});
    defer responder1.join();
    const responder2 = try std.Thread.spawn(.{}, testApSlotResponder, .{2});
    defer responder2.join();
    const responder3 = try std.Thread.spawn(.{}, testApSlotResponder, .{3});
    defer responder3.join();
    errdefer {
        _ = haltApSlot(3) catch {};
        _ = haltApSlot(2) catch {};
        _ = haltApSlot(1) catch {};
        _ = haltApSlot(0) catch {};
    }

    var preload_tasks: [5]abi.BaremetalTask = undefined;
    for (&preload_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 12));
        const budget_ticks = @as(u32, @intCast((task_id - 1) * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(task_id)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    var debt_tasks: [3]abi.BaremetalTask = undefined;
    for (&debt_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 9));
        const budget_ticks = @as(u32, @intCast((task_id - 1) * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(task_id)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    var waiting_tasks: [8]abi.BaremetalTask = undefined;
    for (&waiting_tasks, 0..) |*task, index| {
        const task_id = @as(u32, @intCast(index + 1));
        const budget_ticks = @as(u32, @intCast((task_id - 1) * 2 + 5));
        task.* = .{
            .task_id = task_id,
            .state = abi.task_state_ready,
            .priority = @as(u8, @intCast(task_id)),
            .reserved0 = 0,
            .run_count = 0,
            .budget_ticks = budget_ticks,
            .budget_remaining = budget_ticks,
            .created_tick = 0,
            .last_run_tick = 0,
        };
    }

    resetWindowState();
    try std.testing.expectEqual(@as(u32, 70), try dispatchWindowedSchedulerTasksPriorityFromOffset(preload_tasks[0..], 0, 5));
    try std.testing.expectEqual(@as(u32, 66), try dispatchDebtAwareSchedulerTasksPriorityWithFairshareFromOffset(
        debt_tasks[0..],
        waiting_tasks[0..],
        0,
        2,
        2,
    ));

    const snapshot = fairshareStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
    try std.testing.expectEqual(@as(u8, abi.ap_ownership_policy_priority), snapshot.policy);
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
    try std.testing.expectEqual(@as(u32, 11), snapshot.peak_effective_priority);
    try std.testing.expectEqual(@as(u32, 1), snapshot.last_start_slot_index);

    try std.testing.expectEqual(@as(u16, 4), fairshareEntryCount());
    const first_entry = fairshareEntry(0);
    const second_entry = fairshareEntry(1);
    const third_entry = fairshareEntry(2);
    const fourth_entry = fairshareEntry(3);
    try std.testing.expectEqual(@as(u32, 1), first_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), first_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 2), first_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), first_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 0), first_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), first_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 1), first_entry.started);
    try std.testing.expectEqual(@as(u32, 0), first_entry.halted);

    try std.testing.expectEqual(@as(u32, 2), second_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), second_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), second_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 1), second_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), second_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 1), second_entry.started);
    try std.testing.expectEqual(@as(u32, 0), second_entry.halted);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), third_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), third_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 1), third_entry.started);
    try std.testing.expectEqual(@as(u32, 0), third_entry.halted);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.waiting_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.fairshare_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.seed_task_count);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.final_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.initial_debt);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.remaining_debt);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.last_task_id);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.aged_task_count);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.started);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.halted);

    try std.testing.expectEqual(@as(u32, 1), FairshareStorage.task_ids[@as(usize, fourth_entry.slot_index)][0]);

    const fairshare_render = try renderFairshareAlloc(std.testing.allocator);
    defer std.testing.allocator.free(fairshare_render);
    try std.testing.expect(std.mem.indexOf(u8, fairshare_render, "total_waiting_task_count=8") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairshare_render, "total_debt_task_count=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairshare_render, "total_dispatch_count=11") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairshare_render, "total_accumulator=66") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairshare_render, "aging_round_count=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairshare_render, "fairshare_round_count=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairshare_render, "total_aged_task_count=24") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairshare_render, "total_promoted_task_count=8") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairshare_render, "total_fairshare_task_count=7") != null);
    try std.testing.expect(std.mem.indexOf(u8, fairshare_render, "slot[3].task[0]=1") != null);

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
