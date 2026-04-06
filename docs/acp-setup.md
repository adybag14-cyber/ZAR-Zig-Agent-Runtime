# ACP Setup

This page documents the Hermes-inspired ACP scaffolding, shared session lifecycle, prompt/transcript seam, delegated-task receipts/events, and polling posture now present in ZAR.

## Current scope

ZAR is **not** full ACP parity yet. The current slice ports the parts that fit ZAR's Zig runtime cleanly and can stay portable across both runtime profiles:

- ACP-style registry scaffold in `acp_registry/agent.json`
- Hermes-style tool typing in `tools.catalog`
  - each tool advertises a `kind`
  - execution-heavy tools also advertise `approvalSensitive`
  - the catalog also advertises `supportedOnHosted`, `supportedOnBaremetal`, `currentRuntimeSupported`, and top-level `runtimeTarget` posture so ACP-shaped adapters can reason about hosted vs bare-metal availability
- shared `acp.describe` metadata in Zig with:
  - runtime target labeling
  - authentication discovery (`acp.initialize`, `acp.authenticate`)
  - polling delivery posture (`acp.sessions.events`, `acp.sessions.updates`, `tasks.events`, `tasks.get`)
  - ACP-shaped capability flags
  - session-lifecycle/update/search method discovery
  - prompt/content-block capability discovery
  - shared portable tool catalog exposure
- shared ACP handshake/auth in Zig with:
  - `acp.initialize`
  - `acp.authenticate`
  - provider/method posture discovery that stays aligned across hosted `/rpc` and bare-metal `RUNTIMECALL`
- shared ACP session lifecycle in Zig with:
  - `acp.sessions.list`
  - `acp.sessions.new`
  - `acp.sessions.load`
  - `acp.sessions.resume`
  - `acp.sessions.get`
  - `acp.sessions.messages`
  - `acp.sessions.events`
  - `acp.sessions.updates`
  - `acp.sessions.search`
  - `acp.sessions.fork`
  - `acp.sessions.cancel`
  - durable session metadata plus transcript and session-event storage in shared runtime state
- shared `acp.prompt` handling in Zig with:
  - durable user/assistant transcript recording
  - direct assistant-message replies when no delegated work is requested
  - delegated-task execution when prompt params carry work/toolsets/cwd/session defaults
  - task-summary replies that point back to shared task receipts/events
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

The runtime serves JSON-RPC over HTTP on `/rpc`. The same portable runtime contract now also reaches the bare-metal service path through `RUNTIMECALL`, so catalog metadata, ACP auth/session/prompt semantics, session updates/search, delegation, task receipts/events, and session transcripts stay aligned across both runtime profiles.

## ACP description and tool metadata

`acp.describe` now returns Hermes-guided ACP metadata so an adapter or UI can discover the runtime target, authentication methods, polling delivery posture, task/session capability set, session lifecycle/update/search methods, and prompt capability envelope without guessing.

`tools.catalog` returns Hermes-inspired tool categories so an ACP adapter or UI can distinguish between read/edit/search/fetch/execute style tools. It also returns per-tool support posture for hosted vs bare-metal targets plus the current runtime target label.

`acp.initialize` returns the advertised ACP authentication methods for the current runtime target. `acp.authenticate` accepts a method/provider id and returns the current runtime's best-effort auth posture (`authenticated`, `provider`, `runtimeTarget`, and a status message) without pretending credentials exist where they do not.

Examples:

- `file.read` -> `read`
- `file.write`, `file.patch` -> `edit`
- `file.search`, `sessions.search`, `tasks.search`, `acp.sessions.list` -> `search`
- `web.search`, `web.extract`, `browser.open` -> `fetch`
- `exec.run`, `execute_code`, `process.start`, `acp.prompt` -> `execute`

The shared ACP/session/task polling seam is:

- `acp.sessions.events` -> poll durable ACP session events by session
- `acp.sessions.updates` -> poll ACP-shaped update envelopes derived from those durable session events
- `acp.sessions.search` -> search ACP sessions by metadata, transcript text, event previews, and delegated task summaries
- `tasks.list` -> list persisted delegated task receipts
- `tasks.get` -> load a delegated task receipt + latest event cursor
- `tasks.events` -> poll delegated task events by task or session
- `tasks.search` -> search delegated task receipts by goal/summary/session

## ACP session lifecycle

The shared ACP session lifecycle now lives in Zig runtime state and is available through both hosted `/rpc` and bare-metal `RUNTIMECALL`:

- `acp.sessions.new` -> create a new ACP session with optional title/cwd metadata
- `acp.sessions.load` -> load an existing ACP session and refresh cwd/title metadata
- `acp.sessions.resume` -> resume an ACP session, clearing a prior cancel request and creating the session if missing
- `acp.sessions.list` -> list ACP sessions with message/task/event counters
- `acp.sessions.get` -> fetch one ACP session plus latest transcript/task/event cursor state
- `acp.sessions.messages` -> read the durable ACP transcript for one session
- `acp.sessions.events` -> poll durable ACP session events for session lifecycle, messages, and mirrored delegated task progress
- `acp.sessions.updates` -> poll ACP-shaped update envelopes derived from those durable session events
- `acp.sessions.search` -> search ACP sessions by metadata, transcript text, event previews, task goals, and task summaries
- `acp.sessions.fork` -> clone an ACP session into a child session with copied transcript state
- `acp.sessions.cancel` -> mark an ACP session canceled so new prompts are blocked until resume

Transcript messages are stored in shared runtime state with per-message ids, roles, kinds, timestamps, and content-block text payloads. Forked sessions preserve lineage through `sourceSessionId` so adapters can reconstruct parent/child flows.

## Prompt flow

`acp.prompt` now runs through shared Zig runtime code instead of a hosted-only shim.

Two main paths exist:

1. **Direct message path**
   - append the user prompt to the ACP transcript
   - return an assistant message immediately when the prompt carries no delegated work
   - append that assistant message to the same durable transcript

2. **Delegated work path**
   - append the user prompt to the ACP transcript
   - derive delegated defaults such as session id, goal, and cwd
   - run `delegate_task` with the supplied toolsets / steps / prompt payload
   - persist task receipts and per-step events into shared runtime state
   - append an assistant `task_summary` transcript message that points back to the delegated task receipt

This means ACP prompts, session cancel/resume state, delegated work, task receipts/events, mirrored ACP session events, and transcript history now line up across both runtime modes.

## Delegated tool gating

`acp.prompt` is advertised as approval-sensitive and executable, but it is **not** delegated back into the `memory/sessions/search` or `inspect` toolsets. That is intentional.

The shared tool contract allows delegated tasks to inspect ACP metadata and ACP session reads where appropriate:

- `acp`
- `acp.initialize`
- `acp.authenticate`
- `acp.describe`
- `acp.sessions.list`
- `acp.sessions.get`
- `acp.sessions.messages`
- `acp.sessions.events`
- `acp.sessions.updates`
- `acp.sessions.search`

But it does **not** allow delegated tasks to call `acp.prompt` recursively. This prevents nested capability escalation inside delegated batches while still letting delegated flows inspect ACP metadata and read transcript history.

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
- `acp.describe` authentication + polling + session-lifecycle/update/search metadata
- `acp.initialize`
- `acp.authenticate`
- `acp.sessions.new|load|cancel|resume`
- direct-message `acp.prompt`
- durable transcript lookup through `acp.sessions.messages`
- ACP session-event polling through `acp.sessions.events`
- ACP update polling through `acp.sessions.updates`
- ACP session search through `acp.sessions.search`
- session cloning through `acp.sessions.fork`
- delegated `acp.prompt` execution that produces a persisted task receipt, mirrored ACP session events/updates, and a transcript summary
- persisted task receipt polling via `tasks.list|get|events|search`
- prompt -> pending approval -> approved re-run
- deny-mode blocking for `process.start`
- the earlier file/web/process/session/execute coding-agent path

## What is still missing

The scaffold still does **not** include:

- a dedicated ACP transport adapter
- full Hermes child-agent / LLM subagent parity
- richer push/stream ACP delivery beyond the current polling-based delegated task envelopes
- native bare-metal implementations for hosted-heavy tools such as `execute_code`, `web.search|extract`, and `process.*`

Those remain good next slices, but the shared ACP metadata + session lifecycle + prompt/transcript seam + delegated task receipt/event path is now live in Zig end to end.
