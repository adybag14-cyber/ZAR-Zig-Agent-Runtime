# Feature Coverage

This page summarizes functional coverage across all major OpenClaw Zig runtime domains.

## Runtime Profiles

- OS-hosted profile:
  - full HTTP + JSON-RPC gateway and complete OpenClaw feature surface
- bare-metal profile:
  - freestanding runtime image (`zig build baremetal`)
  - freestanding i386 runtime image (`zig build baremetal-i386`)
  - exported lifecycle hooks for firmware/bootloader integration (`_start`, `oc_tick`, `oc_tick_n`, `oc_status_ptr`)
  - exported command/mailbox ABI (`oc_command_ptr`, `oc_submit_command`, `oc_kernel_info_ptr`, `kernel_info`)
  - exported x86 descriptor/interrupt bootstrap ABI (`oc_gdtr_ptr`, `oc_idtr_ptr`, `oc_gdt_ptr`, `oc_idt_ptr`, `oc_interrupt_stub`, `oc_interrupt_count`, `oc_last_interrupt_vector`)
  - shared portable runtime contract also reaches the bare-metal service path through `RUNTIMECALL`
  - Multiboot2 header embedded for loader compatibility checks

## Protocol and Gateway

- `connect`, `health`, `status`, `shutdown`
- HTTP route surface:
  - `GET /health`
  - `POST /rpc`
- dispatcher coverage test ensures every registered method is dispatchable

## Runtime and Tooling

- tool runtime:
  - shared Zig portable tool contract now lives in `src/runtime/tool_contract.zig` and is consumed by both the hosted `/rpc` gateway and the bare-metal `RUNTIMECALL` bridge
  - `acp.describe` now exposes Hermes-guided ACP metadata, capabilities, polling delivery posture, session lifecycle methods, and prompt semantics from shared Zig runtime code
  - `acp.sessions.list`, `acp.sessions.new`, `acp.sessions.get`, `acp.sessions.messages`, and `acp.sessions.fork` now expose shared ACP session lifecycle plus durable transcript lookup on both hosted and bare-metal paths
  - `acp.prompt` now records ACP session messages in shared runtime state and can either return a direct assistant message or launch delegated work with persisted task receipts/events
  - `exec.run`
  - `execute_code` for constrained hosted snippet execution (`javascript`, `python`, `zig`, `bash`, `shell`)
  - `delegate_task` for Hermes-guided delegated step batches with isolated session scopes, toolset gating, runtime-support gating, persisted receipts/events, per-step events, and approval propagation
  - end-to-end approval enforcement for `exec.run`, `execute_code`, and `process.start`
  - `tools.catalog` now exposes Hermes-guided `kind` + `approvalSensitive` metadata plus `supportedOnHosted`, `supportedOnBaremetal`, `currentRuntimeSupported`, and top-level `runtimeTarget` posture
  - `file.read`
  - `file.write`
  - `file.search`
  - `file.patch`
  - portable runtime ACP/session/task surfaces: `acp.sessions.list`, `acp.sessions.new`, `acp.sessions.get`, `acp.sessions.messages`, `acp.sessions.fork`, `acp.prompt`, `sessions.history`, `sessions.search`, `tasks.list`, `tasks.get`, `tasks.events`, `tasks.search`
  - web discovery and extraction: `web.search`, `web.extract`
  - background process lifecycle: `process.start`, `process.list`, `process.poll`, `process.read`, `process.wait`, `process.kill`
  - Hermes-style hosted coding-agent smoke proof exists via `scripts/hermes-port-rpc-smoke.mjs`
  - bare-metal command/service tests now prove `tools.catalog`, `acp.describe`, `acp.sessions.list|new|get|messages|fork`, `acp.prompt`, `delegate_task`, `sessions.history`, `sessions.search`, `tasks.list`, `tasks.get`, `tasks.events`, and `tasks.search` over `RUNTIMECALL`
  - hosted gateway smoke wrapper exists via `scripts/hermes-port-runtime-smoke-check.ps1` (full process/execute path on POSIX, bounded fallback on Windows)
- session and history lifecycle:
  - list/preview/status
  - patch/resolve/reset/delete/compact
  - usage, timeseries, logs
  - `sessions.history`, `sessions.search`, `chat.history`

## Security and Diagnostics

- guard and loop-guard pipelines
- audit and doctor surfaces:
  - `security.audit`
  - `doctor`
  - `doctor.memory.status`
- secret-store surfaces:
  - `secrets.store.status`
  - `secrets.store.set|get|delete|list`
  - explicit backend support classification for `env`, `encrypted-file`, native fallback requests, and unsupported backend requests
- gateway auth/rate-limit posture:
  - safe public-bind posture
  - unsafe public-bind posture
  - invalid enabled-threshold posture
- remediation:
  - audit `--fix` path
- strict FS4 gate source:
  - [`docs/zig-port/FS4_SECURITY_TRUST_MATRIX.md`](zig-port/FS4_SECURITY_TRUST_MATRIX.md)
- strict FS4 secret/auth smoke proof:
  - `scripts/security-secret-store-smoke-check.ps1`

## Browser and Auth

- web login lifecycle:
  - `web.login.start`
  - `web.login.wait`
  - `web.login.complete`
  - `web.login.status`
- OAuth compatibility aliases:
  - `auth.oauth.providers|start|wait|complete|logout|import`
- browser request/open:
  - `browser.request`
  - `browser.open`
- browser completion execution:
  - completion mode is triggered by `messages` or prompt fallbacks (`prompt|message|text`)
  - endpoint aliases supported: `endpoint|bridgeEndpoint|lightpandaEndpoint`
  - timeout aliases supported: `requestTimeoutMs|timeoutMs`
  - completion payload aliases supported: `max_tokens|maxTokens`, `loginSessionId|login_session_id`, `apiKey|api_key`
  - response includes structured `bridgeCompletion` telemetry (`requested`, `ok`, `requestUrl`, `statusCode`, `assistantText`, `latencyMs`, `error`)
  - top-level `ok/status` follows completion execution outcome (`completed` or `failed`)
  - strict bridge smoke proof exists via `scripts/browser-request-success-smoke-check.ps1`
- strict direct-provider smoke proof exists via `scripts/browser-request-direct-provider-success-smoke-check.ps1`
- provider-specific direct-provider success proofs also exist via:
  - `scripts/browser-request-openrouter-direct-provider-success-smoke-check.ps1`
  - `scripts/browser-request-opencode-direct-provider-success-smoke-check.ps1`
- strict Telegram ingress and outbound delivery proofs also exist via:
  - `scripts/telegram-webhook-receive-smoke-check.ps1`
  - `scripts/telegram-bot-send-delivery-smoke-check.ps1`
- provider breadth includes chatgpt/codex/claude/gemini/openrouter/opencode and guest-capable qwen/zai/inception flows
- strict FS2 gate source:
  - [`docs/zig-port/FS2_PROVIDER_CHANNEL_MATRIX.md`](zig-port/FS2_PROVIDER_CHANNEL_MATRIX.md)

## Channels and Telegram

- channel methods:
  - `channels.status`
  - `channels.logout`
  - `send`, `chat.send`, `sessions.send`
  - `poll`
- telegram command surface:
  - `/auth` family
  - `/model` family
- queue behavior:
  - bounded retention
  - FIFO-preserving single-pass compaction
- strict FS2 gate source:
  - [`docs/zig-port/FS2_PROVIDER_CHANNEL_MATRIX.md`](zig-port/FS2_PROVIDER_CHANNEL_MATRIX.md)

## Memory

- persistent store with append/history/stats
- memory-backed doctor status, session/chat history retrieval, and semantic session recall
- efficient trim and session removal with linear compaction
- strict FS3 gate source:
  - [`docs/zig-port/FS3_MEMORY_KNOWLEDGE_MATRIX.md`](zig-port/FS3_MEMORY_KNOWLEDGE_MATRIX.md)
- strict FS3 consumer proofs:
  - `scripts/browser-request-memory-context-smoke-check.ps1`
  - `scripts/telegram-reply-memory-context-smoke-check.ps1`

## Edge and Advanced Surfaces

- wasm lifecycle:
  - marketplace list/install/execute/remove
  - strict FS5 WASM proof: `scripts/edge-wasm-lifecycle-smoke-check.ps1`
  - strict FS5 matrix source: [`docs/zig-port/FS5_EDGE_WASM_FINETUNE_MATRIX.md`](zig-port/FS5_EDGE_WASM_FINETUNE_MATRIX.md)
- planning and acceleration:
  - router, acceleration, swarm, collaboration
- multimodal and voice:
  - multimodal inspect, voice transcribe
- enclave/mesh/homomorphic:
  - enclave status/prove, mesh status, homomorphic compute
- finetune:
  - run/status/job get/cancel/cluster plan
  - strict finetune proof: `scripts/edge-finetune-lifecycle-smoke-check.ps1`
- additional edge contracts:
  - identity trust, personality, handoff, revenue preview, alignment, quantum

## Operations and Compat Coverage

- agents/skills
- cron
- device pairing and token rotation/revoke
- node flows and execution approval workflows
- Hermes-style ACP scaffolding via `acp_registry/agent.json` and [`docs/acp-setup.md`](acp-setup.md)
- Hermes-inspired ACP session lifecycle plus prompt/transcript slice now ships as shared Zig runtime code across hosted `/rpc` and bare-metal `RUNTIMECALL`
- Hermes-inspired delegation slice continues to ship as Zig-native `delegate_task` rather than a stubbed ACP placeholder
- tts/voicewake/talk and heartbeat/presence control surfaces
- update lifecycle:
  - `update.plan`
  - `update.status`
  - `update.run`
- npm ecosystem surface:
  - publishable JS client package `@adybag14-cyber/openclaw-zig-rpc-client`
  - npm release pipeline via GitHub Actions

For the complete method set, see [`src/gateway/registry.zig`](https://github.com/adybag14-cyber/ZAR-Zig-Agent-Runtime/blob/main/src/gateway/registry.zig).
