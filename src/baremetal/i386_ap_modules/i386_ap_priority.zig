var aging_peak_effective_priority: u32 = 0;
var aging_last_start_slot_index: u32 = 0;
var fairshare_drain_round_count: u32 = 0;
var fairshare_aging_round_count: u32 = 0;
var fairshare_fairshare_round_count: u32 = 0;
var fairshare_peak_effective_priority: u32 = 0;
var fairshare_last_start_slot_index: u32 = 0;
var quota_drain_round_count: u32 = 0;
var quota_aging_round_count: u32 = 0;
var quota_quota_round_count: u32 = 0;
var quota_peak_effective_priority: u32 = 0;
var quota_last_start_slot_index: u32 = 0;
const max_backfill_seen_tasks: usize = 128;
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
const QuotaStorage = struct {
    var task_ids: [max_ap_command_slots][max_task_batch_entries]u32 = [_][max_task_batch_entries]u32{[_]u32{0} ** max_task_batch_entries} ** max_ap_command_slots;
    var task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var waiting_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_waiting_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var debt_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_debt_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var quota_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var total_quota_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var dispatch_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var seed_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var final_task_count: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var configured_quota: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
    var remaining_quota: [max_ap_command_slots]u32 = [_]u32{0} ** max_ap_command_slots;
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
        .peak_effective_priority = 0,
        .last_start_slot_index = 0,
    };
}

fn zeroFairshareState() abi.BaremetalApFairshareState {
    return .{
        .magic = abi.ap_fairshare_magic,
        .api_version = abi.api_version,
        .present = 0,
        .peak_effective_priority = 0,
        .last_start_slot_index = 0,
    };
}

fn zeroQuotaState() abi.BaremetalApQuotaState {
    return .{
        .magic = abi.ap_quota_magic,
        .api_version = abi.api_version,
        .present = 0,
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

    WindowStorage.last_priority[slot_index] = 0;
    WindowStorage.last_budget_ticks[slot_index] = 0;
    WindowStorage.last_batch_accumulator[slot_index] = 0;
    @memset(&WindowStorage.task_ids[slot_index], 0);
}

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
    RebalanceStorage.last_priority[slot_index] = 0;
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

fn resetQuotaSlot(slot_index: usize) void {
    QuotaStorage.task_count[slot_index] = 0;
    QuotaStorage.waiting_task_count[slot_index] = 0;
    QuotaStorage.total_waiting_task_count[slot_index] = 0;
    QuotaStorage.debt_task_count[slot_index] = 0;
    QuotaStorage.total_debt_task_count[slot_index] = 0;
    QuotaStorage.quota_task_count[slot_index] = 0;
    QuotaStorage.total_quota_task_count[slot_index] = 0;
    QuotaStorage.dispatch_count[slot_index] = 0;
    QuotaStorage.seed_task_count[slot_index] = 0;
    QuotaStorage.final_task_count[slot_index] = 0;
    QuotaStorage.configured_quota[slot_index] = 0;
    QuotaStorage.remaining_quota[slot_index] = 0;
    QuotaStorage.initial_debt[slot_index] = 0;
    QuotaStorage.remaining_debt[slot_index] = 0;
    QuotaStorage.last_task_id[slot_index] = 0;
    QuotaStorage.last_priority[slot_index] = 0;
    QuotaStorage.last_effective_priority[slot_index] = 0;
    QuotaStorage.peak_effective_priority[slot_index] = 0;
    QuotaStorage.last_budget_ticks[slot_index] = 0;
    QuotaStorage.last_batch_accumulator[slot_index] = 0;
    QuotaStorage.total_accumulator[slot_index] = 0;
    QuotaStorage.compensated_task_count[slot_index] = 0;
    QuotaStorage.total_compensated_task_count[slot_index] = 0;
    QuotaStorage.aged_task_count[slot_index] = 0;
    QuotaStorage.total_aged_task_count[slot_index] = 0;
    @memset(&QuotaStorage.task_ids[slot_index], 0);
}

fn resetDebtState() void {
    debt_state = zeroDebtState();
    @memset(&debt_entries, std.mem.zeroes(abi.BaremetalApDebtEntry));
    debt_drain_round_count = 0;
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
    fairshare_peak_effective_priority = 0;
    fairshare_last_start_slot_index = 0;
    for (0..max_ap_command_slots) |slot_index| resetFairshareSlot(slot_index);
}

fn resetQuotaState() void {
    quota_state = zeroQuotaState();
    @memset(&quota_entries, std.mem.zeroes(abi.BaremetalApQuotaEntry));
    quota_drain_round_count = 0;
    quota_aging_round_count = 0;
    quota_quota_round_count = 0;
    quota_peak_effective_priority = 0;
    quota_last_start_slot_index = 0;
    for (0..max_ap_command_slots) |slot_index| resetQuotaSlot(slot_index);
}

pub fn resetMultiState() void {
    multi_state = zeroMultiState();
    @memset(&multi_entries, std.mem.zeroes(abi.BaremetalApMultiEntry));
}

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

pub fn dispatchRebalancedSchedulerTasksPriorityUntilDrainedFromOffset(
    tasks: []const abi.BaremetalTask,
    start_slot_offset: usize,
    task_budget: usize,
            RebalanceStorage.last_priority[slot_index] = @as(u32, task.priority);
    effective_priority: u32,
    waiting_age_rounds: u32,
    kind: AgingCandidateKind,
};

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

pub fn dispatchDebtAwareSchedulerTasksPriorityWithFairshareFromOffset(
    debt_tasks: []const abi.BaremetalTask,
    waiting_tasks: []const abi.BaremetalTask,
    start_slot_offset: usize,
    task_budget: usize,
    aging_step: u32,
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

pub fn dispatchDebtAwareSchedulerTasksPriorityWithQuotaFromOffset(
    debt_tasks: []const abi.BaremetalTask,
    waiting_tasks: []const abi.BaremetalTask,
    start_slot_offset: usize,
    task_budget: usize,
    aging_step: u32,
    quotas: []const u8,
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
            if (quota_peak_effective_priority < effective_priority) quota_peak_effective_priority = effective_priority;
            built_count += 1;
        }
        std.debug.assert(built_count == candidate_count);
        sortAgingCandidates(candidates[0..candidate_count]);

        const round_task_count = @min(task_budget, candidate_count);
        const selected_candidates = candidates[0..round_task_count];
        quota_drain_round_count +%= 1;
        quota_last_round_waiting_task_count = 0;
        quota_last_round_debt_task_count = 0;
        quota_last_round_quota_task_count = 0;
        quota_last_round_compensated_task_count = 0;
        quota_last_round_aged_task_count = 0;
        quota_last_start_slot_index = @as(u32, @intCast(round_start_slot));

        for (selected_candidates, 0..) |candidate, task_index| {
            const slot = if (round_is_quota)
                selectHighestQuotaSlot(active_slots[0..active_slot_count], round_start_slot + task_index)
            else
                selectHighestQuotaDebtSlot(active_slots[0..active_slot_count], round_start_slot + task_index);
            const slot_index = @as(usize, slot);
            const current_count = @as(usize, QuotaStorage.task_count[slot_index]);
            if (current_count >= max_task_batch_entries) return error.TooManyOwnedTasks;
            const debt_before = QuotaStorage.remaining_debt[slot_index];
            const aged = candidate.waiting_age_rounds != 0;
            if (round_is_quota and QuotaStorage.remaining_quota[slot_index] == 0) return error.InvalidWorkBatch;
            QuotaStorage.task_ids[slot_index][current_count] = candidate.task.task_id;
            QuotaStorage.task_count[slot_index] = @as(u32, @intCast(current_count + 1));
            QuotaStorage.final_task_count[slot_index] +%= 1;
            QuotaStorage.last_task_id[slot_index] = candidate.task.task_id;
            QuotaStorage.last_priority[slot_index] = @as(u32, candidate.task.priority);
            QuotaStorage.last_effective_priority[slot_index] = candidate.effective_priority;
            QuotaStorage.last_budget_ticks[slot_index] = candidate.task.budget_ticks;
            if (QuotaStorage.peak_effective_priority[slot_index] < candidate.effective_priority) {
                QuotaStorage.peak_effective_priority[slot_index] = candidate.effective_priority;
            }
            if (candidate.kind == .waiting) {
                QuotaStorage.waiting_task_count[slot_index] +%= 1;
                QuotaStorage.total_waiting_task_count[slot_index] +%= 1;
                quota_last_round_waiting_task_count +%= 1;
                if (aged) {
                    QuotaStorage.aged_task_count[slot_index] +%= 1;
                    QuotaStorage.total_aged_task_count[slot_index] +%= 1;
                    quota_total_promoted_task_count +%= 1;
                }
                if (round_is_quota) {
                    QuotaStorage.quota_task_count[slot_index] +%= 1;
                    QuotaStorage.total_quota_task_count[slot_index] +%= 1;
                    QuotaStorage.remaining_quota[slot_index] -%= 1;
                    quota_total_quota_task_count +%= 1;
                    quota_last_round_quota_task_count +%= 1;
                }
            } else {
                QuotaStorage.debt_task_count[slot_index] +%= 1;
                QuotaStorage.total_debt_task_count[slot_index] +%= 1;
                quota_last_round_debt_task_count +%= 1;
            }
            if (debt_before != 0) {
                QuotaStorage.remaining_debt[slot_index] = debt_before - 1;
                QuotaStorage.compensated_task_count[slot_index] +%= 1;
                QuotaStorage.total_compensated_task_count[slot_index] +%= 1;
                quota_remaining_total_debt -%= 1;
                quota_total_compensated_task_count +%= 1;
                quota_last_round_compensated_task_count +%= 1;
            }
        }
        if (round_is_quota and quota_last_round_quota_task_count != 0) {
            quota_quota_round_count +%= 1;
        }

        var round_accumulator: u32 = 0;
        for (active_slots[0..active_slot_count]) |slot| {
            const slot_index = @as(usize, slot);
            const owned_count = @as(usize, QuotaStorage.task_count[slot_index]);
            if (owned_count == 0) continue;
            const accumulator = try dispatchWorkBatchToApSlot(slot, QuotaStorage.task_ids[slot_index][0..owned_count]);
            QuotaStorage.dispatch_count[slot_index] +%= 1;
            QuotaStorage.last_batch_accumulator[slot_index] = accumulator;
            QuotaStorage.total_accumulator[slot_index] +%= accumulator;
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
            quota_aging_round_count +%= 1;
            quota_total_aged_task_count +%= aged_this_round;
            quota_last_round_aged_task_count = aged_this_round;
        }

        quota_last_pending_task_count = @as(u32, @intCast(remaining_debt_count + remaining_waiting_count));
        snapshotQuotaLoadRange(active_slots[0..active_slot_count], true);
    }

    snapshotQuotaLoadRange(active_slots[0..active_slot_count], true);
    refreshState();
    return total_accumulator;
}

pub fn dispatchDebtAwareSchedulerTasksPriorityUntilDrainedFromOffset(
    tasks: []const abi.BaremetalTask,
    start_slot_offset: usize,
    task_budget: usize,
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

            "slot[{d}].target_apic_id={d}\nslot[{d}].dispatch_count={d}\nslot[{d}].rebalanced_task_count={d}\nslot[{d}].total_rebalanced_task_count={d}\nslot[{d}].seed_task_count={d}\nslot[{d}].final_task_count={d}\nslot[{d}].last_task_id={d}\nslot[{d}].last_priority={d}\nslot[{d}].last_budget_ticks={d}\nslot[{d}].last_batch_accumulator={d}\nslot[{d}].total_accumulator={d}\nslot[{d}].compensated_task_count={d}\nslot[{d}].total_compensated_task_count={d}\nslot[{d}].started={d}\nslot[{d}].halted={d}\nslot[{d}].slot_index={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.dispatch_count,
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
            aging_state.peak_effective_priority,
            aging_state.last_start_slot_index,
        },
    ) catch unreachable;
    used += tail.len;
    var entry_index: u16 = 0;
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
            fairshare_state.peak_effective_priority,
            fairshare_state.last_start_slot_index,
        },
    ) catch unreachable;
    used += tail.len;
    var entry_index: u16 = 0;
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

pub fn renderQuotaAlloc(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    refreshState();
    var buffer: [6144]u8 = undefined;
    var used: usize = 0;
    const head = std.fmt.bufPrint(
        buffer[used..],
        "last_round_waiting_task_count={d}\nlast_round_debt_task_count={d}\nlast_round_quota_task_count={d}\ninitial_pending_task_count={d}\nlast_pending_task_count={d}\npeak_pending_task_count={d}\ntask_budget={d}\naging_step={d}\nquota_budget_total={d}\ninitial_min_slot_task_count={d}\ninitial_max_slot_task_count={d}\ninitial_task_balance_gap={d}\nfinal_min_slot_task_count={d}\nfinal_max_slot_task_count={d}\nfinal_task_balance_gap={d}\ninitial_total_debt={d}\nremaining_total_debt={d}\ntotal_compensated_task_count={d}\nlast_round_compensated_task_count={d}\ntotal_aged_task_count={d}\nlast_round_aged_task_count={d}\ntotal_promoted_task_count={d}\ntotal_quota_task_count={d}\npeak_effective_priority={d}\nlast_start_slot_index={d}\n",
        .{
            quota_state.last_round_waiting_task_count,
            quota_state.last_round_debt_task_count,
            quota_state.last_round_quota_task_count,
            quota_state.initial_pending_task_count,
            quota_state.last_pending_task_count,
            quota_state.peak_pending_task_count,
            quota_state.task_budget,
            quota_state.aging_step,
            quota_state.quota_budget_total,
            quota_state.initial_min_slot_task_count,
            quota_state.initial_max_slot_task_count,
            quota_state.peak_effective_priority,
            quota_state.last_start_slot_index,
        },
    ) catch unreachable;
    used += tail.len;
    var entry_index: u16 = 0;
            "slot[{d}].target_apic_id={d}\nslot[{d}].dispatch_count={d}\nslot[{d}].waiting_task_count={d}\nslot[{d}].total_waiting_task_count={d}\nslot[{d}].debt_task_count={d}\nslot[{d}].total_debt_task_count={d}\nslot[{d}].quota_task_count={d}\nslot[{d}].total_quota_task_count={d}\nslot[{d}].seed_task_count={d}\nslot[{d}].final_task_count={d}\nslot[{d}].configured_quota={d}\nslot[{d}].remaining_quota={d}\nslot[{d}].initial_debt={d}\nslot[{d}].remaining_debt={d}\nslot[{d}].last_task_id={d}\nslot[{d}].last_priority={d}\n",
            .{
                entry_index, entry.target_apic_id,
                entry_index, entry.dispatch_count,
                entry_index, entry.waiting_task_count,
                entry_index, entry.total_waiting_task_count,
                entry_index, entry.debt_task_count,
                entry_index, entry.total_debt_task_count,
                entry_index, entry.quota_task_count,
                entry_index, entry.total_quota_task_count,
                entry_index, entry.seed_task_count,
                entry_index, entry.final_task_count,
                entry_index, entry.configured_quota,
                entry_index, entry.remaining_quota,
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
                .{ entry_index, task_index, QuotaStorage.task_ids[entry.slot_index][task_index] },
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
            .last_priority = WindowStorage.last_priority[slot_index],
            .last_budget_ticks = WindowStorage.last_budget_ticks[slot_index],
            .last_batch_accumulator = WindowStorage.last_batch_accumulator[slot_index],
            .total_accumulator = total_accumulator,
            .started = started,
            .halted = halted,
            .slot_index = @as(u8, @intCast(slot_index)),
            .reserved0 = 0,
        };
            .last_priority = FairnessStorage.last_priority[slot_index],
            .last_budget_ticks = FairnessStorage.last_budget_ticks[slot_index],
            .last_batch_accumulator = FairnessStorage.last_batch_accumulator[slot_index],
            .total_accumulator = total_accumulator,
            .started = started,
            .halted = halted,
            .slot_index = @as(u8, @intCast(slot_index)),
            .reserved0 = 0,
        };
            .last_priority = RebalanceStorage.last_priority[slot_index],
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
    quota_state.peak_effective_priority = quota_peak_effective_priority;
    quota_state.last_start_slot_index = quota_last_start_slot_index;
    @memset(&quota_entries, std.mem.zeroes(abi.BaremetalApQuotaEntry));
    slot_index = 0;
    while (slot_index < max_ap_command_slots) : (slot_index += 1) {
        const target_apic_id = readStateVar(slotTargetApicIdPtr(slot_index));
        const started = if (readStateVar(slotStartedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const halted = if (readStateVar(slotHaltedPtr(slot_index)) != 0) @as(u8, 1) else @as(u8, 0);
        const waiting_task_count = QuotaStorage.waiting_task_count[slot_index];
        const total_waiting_task_count = QuotaStorage.total_waiting_task_count[slot_index];
        const debt_task_count = QuotaStorage.debt_task_count[slot_index];
        const total_debt_task_count = QuotaStorage.total_debt_task_count[slot_index];
        const quota_task_count = QuotaStorage.quota_task_count[slot_index];
        const total_quota_task_count = QuotaStorage.total_quota_task_count[slot_index];
        const seed_task_count = QuotaStorage.seed_task_count[slot_index];
        const final_task_count = QuotaStorage.final_task_count[slot_index];
        const configured_quota = QuotaStorage.configured_quota[slot_index];
        const remaining_quota = QuotaStorage.remaining_quota[slot_index];
        const total_accumulator = QuotaStorage.total_accumulator[slot_index];
        const total_compensated_task_count = QuotaStorage.total_compensated_task_count[slot_index];
        const total_aged_task_count = QuotaStorage.total_aged_task_count[slot_index];
        const remaining_debt = QuotaStorage.remaining_debt[slot_index];
        if (target_apic_id == 0 and
            waiting_task_count == 0 and
            total_waiting_task_count == 0 and
            debt_task_count == 0 and
            total_debt_task_count == 0 and
            quota_task_count == 0 and
            total_quota_task_count == 0 and
            seed_task_count == 0 and
            final_task_count == 0 and
            configured_quota == 0 and
            remaining_quota == 0 and
            total_accumulator == 0 and
            total_compensated_task_count == 0 and
            total_aged_task_count == 0 and
            remaining_debt == 0 and
            started == 0 and
            halted == 0)
        {
            continue;
        }
        const dispatch_count = QuotaStorage.dispatch_count[slot_index];
            .last_priority = QuotaStorage.last_priority[slot_index],
            .last_effective_priority = QuotaStorage.last_effective_priority[slot_index],
            .peak_effective_priority = QuotaStorage.peak_effective_priority[slot_index],
            .last_budget_ticks = QuotaStorage.last_budget_ticks[slot_index],
            .last_batch_accumulator = QuotaStorage.last_batch_accumulator[slot_index],
            .total_accumulator = total_accumulator,
            .compensated_task_count = QuotaStorage.compensated_task_count[slot_index],
            .total_compensated_task_count = total_compensated_task_count,
            .aged_task_count = QuotaStorage.aged_task_count[slot_index],
            .total_aged_task_count = total_aged_task_count,
            .started = started,
            .halted = halted,
            .slot_index = @as(u8, @intCast(slot_index)),
            .reserved0 = 0,
        };
        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 1, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 3, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
    };

    const total_accumulator = try dispatchOwnedSchedulerTasksRoundRobin(tasks[0..]);
    try std.testing.expectEqual(@as(u32, 15), total_accumulator);

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

        .{ .task_id = 1, .state = abi.task_state_ready, .priority = 1, .reserved0 = 0, .run_count = 0, .budget_ticks = 5, .budget_remaining = 5, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 2, .state = abi.task_state_ready, .priority = 5, .reserved0 = 0, .run_count = 0, .budget_ticks = 7, .budget_remaining = 7, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 3, .state = abi.task_state_ready, .priority = 9, .reserved0 = 0, .run_count = 0, .budget_ticks = 9, .budget_remaining = 9, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 4, .state = abi.task_state_ready, .priority = 3, .reserved0 = 0, .run_count = 0, .budget_ticks = 11, .budget_remaining = 11, .created_tick = 0, .last_run_tick = 0 },
        .{ .task_id = 5, .state = abi.task_state_ready, .priority = 7, .reserved0 = 0, .run_count = 0, .budget_ticks = 13, .budget_remaining = 13, .created_tick = 0, .last_run_tick = 0 },
    };

    try std.testing.expectEqual(@as(u32, 15), try dispatchOwnedSchedulerTasksRoundRobin(tasks[0..]));
    try std.testing.expectEqual(@as(u32, 15), try dispatchOwnedSchedulerTasksRoundRobinFromOffset(tasks[0..], 1));

    try std.testing.expectEqual(@as(u32, 3), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 11), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 6), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 15), first_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 7), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 13), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 9), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 15), second_entry.total_accumulator);
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

    try std.testing.expectEqual(@as(u32, 1), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 5), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 6), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 3), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 11), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 9), second_entry.last_batch_accumulator);
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

    try std.testing.expectEqual(@as(u32, 0), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 13), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 10), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 16), first_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 5), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 5), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 14), second_entry.total_accumulator);
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

    try std.testing.expectEqual(@as(u32, 0), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 17), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 13), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 36), first_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 5), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 10), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 38), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 13), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 34), third_entry.total_accumulator);
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

    try std.testing.expectEqual(@as(u32, 9), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 17), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 12), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 46), first_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 9), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 34), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 0), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 11), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 5), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 38), third_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 10), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 19), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 10), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 26), fourth_entry.total_accumulator);
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

    try std.testing.expectEqual(@as(u32, 3), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 36), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 136), first_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 2), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 32), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 136), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 5), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 28), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 136), third_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 4), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 11), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 40), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 136), fourth_entry.total_accumulator);
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

    try std.testing.expectEqual(@as(u32, 2), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 33), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 36), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 200), first_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 35), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 40), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 208), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 4), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 29), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 28), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 200), third_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 31), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 32), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 208), fourth_entry.total_accumulator);
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

    try std.testing.expectEqual(@as(u32, 2), first_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), first_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 40), first_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 227), first_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 5), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 51), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 232), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 3), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 45), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 221), third_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 136), fourth_entry.total_accumulator);
    try std.testing.expectEqual(@as(u8, 1), fourth_entry.started);
    try std.testing.expectEqual(@as(u8, 1), fourth_entry.halted);

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

    try std.testing.expectEqual(@as(u32, 2), second_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 7), second_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 2), second_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 8), second_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), second_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), second_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 3), third_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 2), third_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 5), third_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 1), third_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 6), third_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 1), third_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), third_entry.total_compensated_task_count);

    try std.testing.expectEqual(@as(u32, 4), fourth_entry.target_apic_id);
    try std.testing.expectEqual(@as(u32, 1), fourth_entry.dispatch_count);
    try std.testing.expectEqual(@as(u32, 3), fourth_entry.last_priority);
    try std.testing.expectEqual(@as(u32, 9), fourth_entry.last_budget_ticks);
    try std.testing.expectEqual(@as(u32, 7), fourth_entry.last_batch_accumulator);
    try std.testing.expectEqual(@as(u32, 7), fourth_entry.total_accumulator);
    try std.testing.expectEqual(@as(u32, 0), fourth_entry.compensated_task_count);
    try std.testing.expectEqual(@as(u32, 2), fourth_entry.total_compensated_task_count);

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

test "i386 debt-aware priority scheduler drains bounded quota backlog after carried debt" {
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
    const quotas = [_]u8{ 3, 2, 2, 1 };
    const total_accumulator = try dispatchDebtAwareSchedulerTasksPriorityWithQuotaFromOffset(
        debt_tasks[0..],
        waiting_tasks[0..],
        0,
        3,
        2,
        quotas[0..],
    );
    try std.testing.expect(total_accumulator > 0);

    const snapshot = quotaStatePtr().*;
    try std.testing.expectEqual(@as(u8, 1), snapshot.present);
