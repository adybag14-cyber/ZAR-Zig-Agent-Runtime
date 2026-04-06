# ZAR-Zig-Agent-Runtime Documentation

Full documentation for ZAR-Zig-Agent-Runtime, the Zig runtime port of OpenClaw.

## Status Snapshot

- RPC surface in Zig: `207` methods
- Pinned tri-baseline parity gate:
  - Go baseline (`v2.14.0-go`): `134/134`
  - Original OpenClaw baseline (`v2026.3.13-1`): `100/100`
  - Original OpenClaw beta baseline (`v2026.3.13-beta.1`): `100/100`
  - Union baseline: `141/141` (`MISSING_IN_ZIG=0`)
  - Gateway events union baseline: `19/19` (`UNION_EVENTS_MISSING_IN_ZIG=0`)
- Latest upstream release snapshot (docs drift gate reference):
  - Original OpenClaw baseline (`v2026.3.13-1`): `100/100`
  - Original OpenClaw beta baseline (`v2026.3.13-beta.1`): `100/100`
  - Union baseline: `141/141` (`MISSING_IN_ZIG=0`)
- Latest local validation: `zig build test --summary all` -> `1068 passed; 3 skipped; 0 failed`
- Current edge release target tag: `v0.2.0-zig-edge.32`
- License posture: repo-wide `GPL-2.0-only` with Linux-style SPDX headers on repo-owned source and script files
- Toolchain lane: Codeberg `master` is canonical; `adybag14-cyber/zig` provides rolling `latest-master` and immutable `upstream-<sha>` Windows releases for refresh and reproducibility.
- Recent Hermes/ZAR runtime progress (2026-03-28):
  - shared ACP handshake/auth now ships in Zig through `acp.initialize` and `acp.authenticate` on both hosted `/rpc` and bare-metal `RUNTIMECALL`
  - `acp.sessions.updates` now exposes ACP-shaped polling updates derived from durable session events, and `acp.sessions.search` now searches session metadata, transcripts, event previews, and task summaries from shared Zig runtime state
  - `acp.describe` now advertises authentication methods plus the broader ACP session update/search seam beside the earlier session, prompt, and task receipt/event surfaces
  - latest local validation still covers hosted plus both bare-metal images with `1068` passing tests (`3` skipped)

## Documentation Map

- Getting started and local development workflow
- Architecture and runtime composition
- Package publishing, registry configuration, and install fallbacks
- Full feature coverage by domain
- Strict FS2 provider/channel matrix
- Strict FS3 memory/knowledge matrix
- Strict FS4 security/trust matrix
- Strict FS5 edge/wasm/finetune matrix
- RPC method family reference
- Security, diagnostics, and remediation model
- Browser/auth integration model (Lightpanda-only)
- Telegram command and polling behavior
- Memory and edge capability surfaces
- CI/release flows and deployment operations
- GitHub Pages publishing workflow
- FS5.6 repo-wide license refresh

## Project Links

- Repository: <https://github.com/adybag14-cyber/ZAR-Zig-Agent-Runtime>
- Tracking issue: <https://github.com/adybag14-cyber/ZAR-Zig-Agent-Runtime/issues/1>
- Package publishing guide: [package-publishing.md](package-publishing.md)
- Strict FS2 matrix: [zig-port/FS2_PROVIDER_CHANNEL_MATRIX.md](zig-port/FS2_PROVIDER_CHANNEL_MATRIX.md)
- Strict FS3 matrix: [zig-port/FS3_MEMORY_KNOWLEDGE_MATRIX.md](zig-port/FS3_MEMORY_KNOWLEDGE_MATRIX.md)
- Strict FS4 matrix: [zig-port/FS4_SECURITY_TRUST_MATRIX.md](zig-port/FS4_SECURITY_TRUST_MATRIX.md)
- Strict FS5 matrix: [zig-port/FS5_EDGE_WASM_FINETUNE_MATRIX.md](zig-port/FS5_EDGE_WASM_FINETUNE_MATRIX.md)
- FS5.6 license refresh: [zig-port/FS5_6_LICENSE_REFRESH.md](zig-port/FS5_6_LICENSE_REFRESH.md)
- Method registry source: [`src/gateway/registry.zig`](https://github.com/adybag14-cyber/ZAR-Zig-Agent-Runtime/blob/main/src/gateway/registry.zig)
