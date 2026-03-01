# Phase Checklist

## Phase 1 - Foundation
- [ ] Initialize Zig workspace layout (`cmd`, `internal`, `pkg` equivalent)
- [ ] Add build/test commands (`zig build`, CI smoke)
- [ ] Add config parser + env override skeleton
- [ ] Add `/health` endpoint

## Phase 2 - Protocol + Gateway Core
- [ ] Implement JSON-RPC envelope parsing/serialization
- [ ] Build method registry and dispatcher
- [ ] Implement HTTP RPC route + graceful shutdown
- [ ] Add contract tests for error codes and method routing

## Phase 3 - Runtime + Tooling
- [ ] Add runtime state/session primitives
- [ ] Implement initial tool runtime actions (`exec`, file read/write)
- [ ] Add queue/worker scaffolding for async jobs
- [ ] Add integration tests for request lifecycle

## Phase 4 - Security + Diagnostics
- [ ] Port core guard flow (prompt/tool policy checks)
- [ ] Implement `doctor` and `security.audit` base commands
- [ ] Add remediation/reporting contract outputs

## Phase 5 - Browser/Auth/Channels
- [ ] Implement web login manager (`start/wait/complete/status`)
- [ ] Implement browser completion bridge contract
- [ ] Implement Telegram command/reply surface
- [ ] Add smoke coverage for auth + reply loops

## Phase 6 - Memory + Edge
- [ ] Port memory persistence primitives
- [ ] Port edge handler contracts
- [ ] Port wasm runtime/sandbox lifecycle contracts

## Phase 7 - Validation + Release
- [ ] Run full parity diff against Go baseline
- [ ] Run full test matrix and smoke checks
- [ ] Build release binaries + checksums
- [ ] Publish first Zig preview release
