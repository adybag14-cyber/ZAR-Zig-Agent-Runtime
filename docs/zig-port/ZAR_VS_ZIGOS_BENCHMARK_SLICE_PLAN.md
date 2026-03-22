# ZAR vs ZigOS Benchmark Slice Plan

## Status

Status: `Delivered`

This is the second ZigOS-derived slice now shipped in ZAR.

Why this slice matters:

- low architecture risk
- immediate validation value on refreshed Zig `master`
- no dependency on GP-OS userspace/syscall redesign

Upstream reference baseline:

- repo: `https://github.com/Cameron-Lyons/zigos`
- license: `MIT`
- reference area: `src/kernel/benchmarks`

Current delivered ZAR scope:

- hosted benchmark suite at `src/benchmark_suite.zig`
- benchmark executable at `src/benchmark_main.zig`
- build steps:
  - `zig build bench`
  - `zig build bench-smoke`
- smoke gate:
  - `scripts/benchmark-smoke-check.ps1`
- CI / release wiring:
  - `.github/workflows/zig-ci.yml`
  - `.github/workflows/release-preview.yml`

Delivered benchmark cases:

- `protocol.dns_roundtrip`
- `protocol.dhcp_discover`
- `protocol.tcp_handshake_payload`
- `runtime.state_queue_cycle`
- `tool_service.codec_parse`
- `filesystem.persistence_cycle`
- `filesystem.overlay_read_cycle`
- `network.rtl8139_udp_loopback`
- `network.e1000_udp_loopback`

Delivered output contract:

- `BENCH:START duration_ms=... warmup_ms=...`
- `BENCH:CASE name=... ops=... total_ns=... ns_per_op=... checksum=...`
- `BENCH:END cases=... total_ops=... total_ns=...`

## Design Boundary

This slice is informed by ZigOS benchmark coverage but implemented as ZAR-owned code.

That means:

- no ZigOS benchmark code is required for this lane to function
- the benchmark catalog is aligned to ZAR subsystems, not ZigOS kernel internals
- validation stays inside normal ZAR gates

## Validation

Required for closure:

1. benchmark executable builds on the local Zig `master` toolchain
2. `zig build bench -- --list` reports the benchmark catalog
3. `scripts/benchmark-smoke-check.ps1 -SkipBuild` passes
4. `zig build test --summary all` remains green
5. parity gate remains green
6. docs status gate remains green
7. `zig-ci` remains green
8. `docs-pages` remains green

## Follow-on Depth

Natural next benchmark expansions:

- allocator pressure benchmark lane
- NIC-path transport throughput comparisons beyond the current UDP loopback parity lane
- display mode-switch/present timing lane
- future SMP stress once that track is expanded

Recently delivered follow-on depth:

- filesystem persistence throughput lane through `filesystem.persistence_cycle`
- virtual overlay read churn through `filesystem.overlay_read_cycle`
