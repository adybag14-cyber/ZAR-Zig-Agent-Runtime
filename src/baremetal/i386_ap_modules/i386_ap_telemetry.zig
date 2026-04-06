fn clearOwnershipRoundTelemetry() void {
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
    clearOwnershipRoundTelemetry();
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
fn clearRebalanceRoundTelemetry() void {
    for (0..max_ap_command_slots) |slot_index| {
        clearRebalanceRoundTelemetry();
        const round_start_slot = (start_slot_offset + round_index) % active_slot_count;
        const remaining_task_count = ordered_tasks.len - task_cursor;
        const round_task_count = @min(task_budget, remaining_task_count);
        const selected_tasks = ordered_tasks[task_cursor .. task_cursor + round_task_count];
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
        clearAgingRoundTelemetry();
        const round_start_slot = (start_slot_offset + round_index) % active_slot_count;
        const candidate_count = remaining_debt_count + remaining_waiting_count;
        var candidates: [max_owned_dispatch_entries]AgingCandidate = undefined;
        var built_count: usize = 0;
        for (remaining_debt_storage[0..remaining_debt_count]) |task| {
            candidates[built_count] = .{
                .task = task,
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
fn clearQuotaRoundTelemetry() void {
    for (0..max_ap_command_slots) |slot_index| {
        QuotaStorage.task_count[slot_index] = 0;
        QuotaStorage.waiting_task_count[slot_index] = 0;
        QuotaStorage.debt_task_count[slot_index] = 0;
        QuotaStorage.quota_task_count[slot_index] = 0;
        QuotaStorage.compensated_task_count[slot_index] = 0;
        QuotaStorage.aged_task_count[slot_index] = 0;
        @memset(&QuotaStorage.task_ids[slot_index], 0);
    }
}

fn snapshotQuotaLoadRange(active_slots: []const u16, final: bool) void {
    var min_slot_task_count: u32 = std.math.maxInt(u32);
    var max_slot_task_count: u32 = 0;
    var have_active_slot = false;
    for (active_slots) |slot| {
        const slot_index = @as(usize, slot);
        const load = if (final) QuotaStorage.final_task_count[slot_index] else QuotaStorage.seed_task_count[slot_index];
        if (load < min_slot_task_count) min_slot_task_count = load;
        if (load > max_slot_task_count) max_slot_task_count = load;
        have_active_slot = true;
    }
    const min_value = if (have_active_slot) min_slot_task_count else 0;
    const gap_value = if (have_active_slot) max_slot_task_count - min_value else 0;
    if (final) {
        quota_final_min_slot_task_count = min_value;
        quota_final_max_slot_task_count = max_slot_task_count;
        clearFairshareRoundTelemetry();
        const round_start_slot = (start_slot_offset + round_index) % active_slot_count;
        const round_is_fairshare = fairshare_remaining_total_debt == 0;
        const candidate_count = remaining_debt_count + remaining_waiting_count;
        var candidates: [max_owned_dispatch_entries]AgingCandidate = undefined;
        var built_count: usize = 0;
        for (remaining_debt_storage[0..remaining_debt_count]) |task| {
            candidates[built_count] = .{
                .task = task,
        clearQuotaRoundTelemetry();
        const round_start_slot = (start_slot_offset + round_index) % active_slot_count;
        const round_is_quota = quota_remaining_total_debt == 0;
        if (round_is_quota) {
            var remaining_quota_total: u32 = 0;
            for (active_slots[0..active_slot_count]) |slot| {
                remaining_quota_total +%= QuotaStorage.remaining_quota[@as(usize, slot)];
            }
            if (remaining_quota_total == 0) {
                for (active_slots[0..active_slot_count]) |slot| {
                    const slot_index = @as(usize, slot);
                    QuotaStorage.remaining_quota[slot_index] = QuotaStorage.configured_quota[slot_index];
                }
            }
        }
        const candidate_count = remaining_debt_count + remaining_waiting_count;
        var candidates: [max_owned_dispatch_entries]AgingCandidate = undefined;
        var built_count: usize = 0;
        for (remaining_debt_storage[0..remaining_debt_count]) |task| {
            candidates[built_count] = .{
                .task = task,
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
