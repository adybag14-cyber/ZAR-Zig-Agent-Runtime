# FS3 Memory and Knowledge Matrix

This document is the strict source of truth for FS3 memory/knowledge completion.

Only directly verified local evidence counts:

- `src/memory/store.zig` tests
- hosted dispatcher and Telegram runtime regressions
- explicit smoke scripts proving browser and Telegram consumer memory injection from persisted state
- green `zig-ci` and `docs-pages` on the pushed head

Status legend:

- `PASS`: the listed pass criteria are fully satisfied by current local evidence
- `PARTIAL`: implementation exists, but one or more strict pass criteria are still missing
- `FAIL`: required behavior is currently broken

## Dependency Rules

FS3 depends on already-closed hosted prerequisites:

- FS1 runtime/core consolidation
- FS2 provider/channel completion
- FS4 security/trust hardening

FS3 proofs must use those stabilized surfaces for:

- restart-safe runtime state handling
- deterministic provider/auth resolution for downstream consumers
- real browser and Telegram completion paths instead of unit-only synthesis

## Selected Supported Matrix

| Surface | Methods / path | Strict pass criteria | Current evidence | Status | Remaining gap |
| --- | --- | --- | --- | --- | --- |
| Persistent store and restart recovery | `sessions.history`, `chat.history`, `doctor.memory.status` | append/history survives persistence roundtrip, replay derives `next_id`, restart status is consistent, and persisted state is consumed after restart | `src/memory/store.zig`: `store append/history and persistence roundtrip`, `store stats include vector graph metadata and persistence recovery`, `store load enforces max entries and keeps newest multi-session history`; `scripts/browser-request-memory-context-smoke-check.ps1`; `scripts/telegram-reply-memory-context-smoke-check.ps1` | `PASS` | none |
| Semantic recall ranking | `semanticRecall` | ranked recall returns the expected oracle-related hits from persisted memory content | `src/memory/store.zig`: `store semantic recall returns ranked oracle related hits` | `PASS` | none |
| Graph recall and synthesis | `graphNeighbors`, `recallSynthesis` | graph-neighbor recall and synthesized context expose semantic + graph depth from persisted memory | `src/memory/store.zig`: `store graph neighbors and recall synthesis provide semantic and graph depth` | `PASS` | none |
| Retention policy | replay load path, `runtime.memory_max_entries` | retention-cap and unlimited-retention modes are both tested and documented | `src/memory/store.zig`: `store load enforces max entries and keeps newest multi-session history`, `store unlimited retention keeps all entries and reports unlimited stats`; documented in `docs/zig-port/PORT_PLAN.md`, `docs/zig-port/PHASE_CHECKLIST.md`, and `docs/feature-coverage.md` | `PASS` | none |
| Browser completion memory consumer | `browser.request` completion mode | persisted session memory is injected into the completion context, bridge completion succeeds, and captured outbound payload includes memory recap + semantic recall text | `src/gateway/dispatcher.zig`: `dispatch browser.request injects memory and tool context when session history exists`; `scripts/browser-request-memory-context-smoke-check.ps1` | `PASS` | none |
| Telegram reply memory consumer | non-command Telegram reply / bridge completion path | persisted session memory is injected into the reply context, provider-backed reply succeeds, and captured outbound payload includes long-term recall context + semantic hits | `src/channels/telegram_runtime.zig`: `telegram runtime uses provider api key when no authorized browser session exists`; `scripts/telegram-reply-memory-context-smoke-check.ps1` | `PASS` | none |

## Strict FS3 Closure Status

FS3 is locally closed.

What is now closed:

- the hard matrix now exists in docs
- memory persistence/recovery, semantic recall, graph recall, synthesis, retention-cap, and unlimited-retention proofs are explicit in the repo-native test suite
- browser completion memory injection from persisted state is proven by an end-to-end smoke
- Telegram reply memory injection from persisted state is proven by an end-to-end smoke
- both consumer smokes are now part of the strict hosted CI/release lane

## Enforced Local Smoke Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\browser-request-memory-context-smoke-check.ps1 -SkipBuild
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\telegram-reply-memory-context-smoke-check.ps1 -SkipBuild
```
