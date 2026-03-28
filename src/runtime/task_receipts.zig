const state = @import("state.zig");
const tool_contract = @import("tool_contract.zig");
const delegate_task = @import("../gateway/delegate_task.zig");

pub fn recordBatch(
    runtime_state: *state.RuntimeState,
    batch: *const delegate_task.BatchResult,
) !void {
    for (batch.results) |task| {
        const created_at_ms = if (task.events.len > 0) task.events[0].atMs else 0;
        const updated_at_ms = if (task.events.len > 0) task.events[task.events.len - 1].atMs else created_at_ms;

        try runtime_state.recordTaskReceipt(
            task.taskId,
            task.goal,
            task.context,
            task.sessionId,
            task.cwd,
            task.status,
            task.summary,
            task.completedSteps,
            task.totalSteps,
            task.successCount,
            task.failureCount,
            task.approvalRequiredCount,
            created_at_ms,
            updated_at_ms,
        );

        for (task.events) |event| {
            _ = try runtime_state.recordTaskEvent(
                task.taskId,
                task.sessionId,
                event.atMs,
                event.kind,
                event.stepIndex,
                event.toolCallId,
                event.tool,
                event.status,
                event.preview,
            );
            if (task.sessionId.len > 0) {
                _ = try runtime_state.recordSessionEvent(
                    task.sessionId,
                    task.taskId,
                    null,
                    event.atMs,
                    event.kind,
                    null,
                    event.toolCallId,
                    event.tool,
                    if (event.tool) |tool| tool_contract.toolKindForMethod(tool) else null,
                    event.status,
                    event.preview,
                );
            }
        }

        if (task.sessionId.len > 0 and runtime_state.getSession(task.sessionId) == null) {
            const seed_message = if (task.summary.len > 0)
                task.summary
            else if (task.goal.len > 0)
                task.goal
            else
                task.status;
            try runtime_state.upsertSession(task.sessionId, seed_message, updated_at_ms);
        }
    }
}
