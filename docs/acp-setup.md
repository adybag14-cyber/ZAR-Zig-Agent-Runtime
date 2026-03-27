# ACP Setup

This page documents the Hermes-inspired ACP scaffolding, delegated-task receipts/events, and polling seam now present in ZAR.

## Current scope

ZAR is **not** full ACP parity yet. The current slice ports the parts that fit ZAR's existing Zig runtime cleanly:

- ACP-style registry scaffold in `acp_registry/agent.json`
- Hermes-style tool typing in `tools.catalog`
  - each tool now advertises a `kind`
  - execution-heavy tools also advertise `approvalSensitive`
  - the catalog now also advertises `supportedOnHosted`, `supportedOnBaremetal`, `currentRuntimeSupported`, and top-level `runtimeTarget` posture so ACP-shaped adapters can reason about hosted vs bare-metal availability
- shared `acp.describe` metadata in Zig with:
  - runtime target labeling
  - polling delivery posture (`tasks.events` + `tasks.get`)
  - ACP-shaped capability flags
  - shared portable tool catalog exposure
- Zig-native `delegate_task` batches with:
  - isolated session scopes
  - delegated toolset gating
  - runtime-support gating using the shared hosted/bare-metal tool contract
  - persisted delegated task receipts and events in shared runtime state
  - per-step `task.start`, `tool.call.start`, `tool.call.result`, and `task.complete` events
  - approval propagation when delegated execution hits `prompt` policy
- end-to-end execution approvals for:
  - `exec.run`
  - `execute_code`
  - `process.start`

## Launching the runtime

Build and run the Zig server:

```bash
zig build -Doptimize=Debug
./zig-out/bin/openclaw-zig --serve
```

The runtime serves JSON-RPC over HTTP on `/rpc`. The same portable runtime contract now also reaches the bare-metal service path through `RUNTIMECALL`, so catalog/ACP metadata/delegation/task receipts/session receipts stay aligned across both runtime profiles.

## ACP description and tool metadata

`acp.describe` now returns Hermes-guided ACP metadata so an adapter or UI can discover the runtime target, polling delivery posture, and task/session capability set without guessing. `tools.catalog` returns Hermes-inspired tool categories so an ACP adapter or UI can distinguish between read/edit/search/fetch/execute style tools. It also returns per-tool support posture for hosted vs bare-metal targets plus the current runtime target label.

Examples:

- `file.read` -> `read`
- `file.write`, `file.patch` -> `edit`
- `file.search`, `sessions.search`, `tasks.search` -> `search`
- `web.search`, `web.extract`, `browser.open` -> `fetch`
- `exec.run`, `execute_code`, `process.start` -> `execute`

The shared task polling seam is:

- `tasks.list` -> list persisted delegated task receipts
- `tasks.get` -> load a delegated task receipt + latest event cursor
- `tasks.events` -> poll delegated task events by task or session
- `tasks.search` -> search delegated task receipts by goal/summary/session

## Approval-sensitive execution flow

Global approval mode:

```json
{ "method": "exec.approvals.set", "params": { "mode": "allow" } }
```

Node-scoped override:

```json
{ "method": "exec.approvals.node.set", "params": { "nodeId": "node-hermes-approval", "mode": "prompt" } }
```

When `prompt` is active, calling an approval-sensitive method returns a structured result instead of executing immediately:

```json
{
  "ok": false,
  "state": "approval_required",
  "approval": {
    "approvalId": "approval-000001",
    "status": "pending"
  }
}
```

Resolve the pending approval:

```json
{ "method": "exec.approval.resolve", "params": { "approvalId": "approval-000001", "status": "approved" } }
```

Then re-run the original request with `approvalId` included.

## Smoke coverage

`scripts/hermes-port-rpc-smoke.mjs` now verifies:

- typed `tools.catalog` metadata
- `acp.describe` polling metadata (`tasks.events`, `tasks.get`)
- prompt -> pending approval -> approved re-run
- deny-mode blocking for `process.start`
- delegated file-step execution through `delegate_task`
- delegated approval blocking through `delegate_task`
- persisted task receipt polling via `tasks.list|get|events|search`
- the earlier file/web/process/session/execute coding-agent path

## What is still missing

The scaffold does **not** yet include:

- a dedicated ACP protocol adapter
- full Hermes child-agent / LLM subagent parity
- richer push/stream ACP delivery beyond the current polling-based delegated task envelopes

Those remain good next slices, but the shared ACP metadata + delegated task receipt/event path is now live in Zig end to end.
