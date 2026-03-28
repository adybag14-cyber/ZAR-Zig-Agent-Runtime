# ACP registry scaffold

This directory mirrors the registry layout used in Hermes so ZAR can be packaged with ACP-oriented metadata.

Current scope:
- registry descriptor: `agent.json`
- icon asset: `icon.svg`
- runtime launch target: `openclaw-zig --serve`

This is intentionally a **scaffold**, not a claim of full ACP protocol parity. The live Zig runtime currently exposes its tool surface over JSON-RPC HTTP at `/rpc`, including the Zig-native `delegate_task` batch runner. See `docs/acp-setup.md` for the execution-approval flow, delegated-task events, and the Hermes-inspired tool-kind metadata exposed by `tools.catalog`.
