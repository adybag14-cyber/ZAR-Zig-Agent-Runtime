# ZAR vs ZigOS Integration Plan

## Status

This document tracks the strict, reference-only integration plan for ideas and feature targets observed in `Cameron-Lyons/zigos`.

Current posture:

- ZigOS is `reference only`.
- No ZigOS source may be copied, translated, or mechanically ported into ZAR until upstream licensing is explicit.
- All adoption work described here is clean-room work implemented against ZAR-native architecture, tests, probes, and release gates.

## Source Baseline

This plan is based on:

- local review: `C:\Users\Ady\Downloads\zar_vs_zigos_engineering_review.md`
- upstream repo: `https://github.com/Cameron-Lyons/zigos`
- upstream capability areas observed in:
  - `src/kernel/drivers`
  - `src/kernel/fs`
  - `src/kernel/process`
  - `src/kernel/net`
  - `src/kernel/shell`
  - `src/kernel/elf`
  - `src/kernel/smp`
  - `src/kernel/benchmarks`
  - `src/kernel/tests`
  - `user/bin`
  - `user/lib`

## Hard Gate: License And Provenance

ZigOS currently has no explicit repository license in the checked upstream source of truth.

That creates a hard legal boundary:

1. no code copy
2. no line-by-line port
3. no translation of individual functions or files
4. no transplant of tests or userland programs

Allowed use until licensing is clarified:

- architecture study
- capability inventory
- clean-room design notes
- feature ordering and validation strategy

Any ZAR slice influenced by ZigOS must satisfy all of the following:

1. ZAR-owned implementation only
2. ZAR-owned tests only
3. ZAR-owned live probe coverage only
4. no imported upstream text beyond short factual references
5. explicit tracking note that the slice is `reference-inspired`, not imported

## Capability Inventory

The table below is the current strict classification for every realistic ZigOS area that could inform ZAR.

| Area | Upstream Evidence | ZAR Relevance | Disposition | First ZAR Action |
| --- | --- | --- | --- | --- |
| `E1000 NIC driver` | `src/kernel/drivers/e1000.zig` | High | Adapt now | Clean-room E1000 slice |
| `VirtIO device patterns` | `src/kernel/drivers/virtio.zig` | High | Adapt now | Use as reference for later virtio-net/storage breadth |
| `ATA driver ideas` | `src/kernel/drivers/ata.zig` | Medium | Already largely covered | Use only for comparison against ZAR ATA PIO |
| `PCI discovery patterns` | `src/kernel/drivers/pci.zig` | Medium | Already largely covered | Compare against current ZAR PCI routing |
| `USB/UHCI` | `src/kernel/drivers/usb.zig`, `uhci.zig` | Medium | Adapt later | Separate FS5.5 hardware expansion after E1000 |
| `AC97 audio` | `src/kernel/drivers/ac97.zig` | Low-medium | Adapt later | Only after display/input/network/storage priorities |
| `VGA path` | `src/kernel/drivers/vga.zig` | Low | Already covered conceptually | Reference only |
| `VFS core` | `src/kernel/fs/vfs.zig` | High | Major redesign | ZAR-native VFS design doc first |
| `tmpfs` | `src/kernel/fs/tmpfs.zig` | Medium-high | Adapt later | Rebuild concept over ZAR runtime/package/workspace state |
| `devfs` | `src/kernel/fs/devfs.zig` | Medium-high | Adapt later | Rebuild concept over ZAR bare-metal devices |
| `procfs` | `src/kernel/fs/procfs.zig` | Medium-high | Adapt later | Rebuild concept over ZAR runtime/process-equivalent surfaces |
| `sysfs` | `src/kernel/fs/sysfs.zig` | Medium-high | Adapt later | Rebuild concept over ZAR driver/runtime/export state |
| `ext2` | `src/kernel/fs/ext2.zig` | Medium | Major redesign | Only after ZAR VFS exists |
| `fat32` | `src/kernel/fs/fat32.zig` | Medium | Major redesign | Only after ZAR VFS exists |
| `TTY layer` | `src/kernel/fs/tty.zig` | Medium | Adapt later | Only if ZAR shell/interactive console expands |
| `Ethernet/ARP/IPv4/UDP/TCP/DHCP/DNS/HTTP` | `src/kernel/net/*` | High | Mostly already covered | Use as cross-check, not as adoption target |
| `IPv6/ICMPv6` | `src/kernel/net/ipv6.zig`, `icmpv6.zig` | Medium | Adapt later | New ZAR networking slice after E1000 |
| `Routing/socket model` | `src/kernel/net/routing.zig`, `socket.zig` | Medium-high | Major redesign | Requires ZAR network/service API decision |
| `ELF loader` | `src/kernel/elf/*` | High | Major redesign | Separate future OS-model track |
| `Ring3/userspace` | `ring3.zig`, `userspace.zig` | High | Major redesign | Separate future OS-model track |
| `Scheduler/process/signals/ipc/credentials` | `src/kernel/process/*` | High | Major redesign | Separate future syscall/process track |
| `Syscall ABI` | `src/kernel/process/syscall.zig` | High | Major redesign | Separate ABI design doc first |
| `Shell parser/glob/jobs/editor` | `src/kernel/shell/*` | Medium-high | Adapt later | Shell/UI design only after runtime-service decision |
| `HTTPD shell tool` | `src/kernel/shell/httpd.zig` | Low-medium | Adapt later | Only if ZAR wants shell-side admin/http tooling |
| `Userland binaries` | `user/bin/*` | Medium-high | Major redesign | Not a drop-in fit; separate userland decision |
| `Userland helper libs` | `user/lib/*` | Medium | Major redesign | Only relevant if ZAR commits to userland |
| `SMP boot/trampoline` | `src/kernel/smp/*` | Medium-high | Adapt later | SMP audit and stress lane, not direct import |
| `Benchmarks/stress` | `src/kernel/benchmarks/*`, `src/kernel/tests/*` | High | Adapt now | ZAR-native benchmark/stress harness |

## Integration Order

The order below is strict. It favors bounded clean-room wins before any redesign-heavy GP-OS work.

### Z0. Provenance Discipline

Required before any ZigOS-inspired implementation work:

- keep this document current
- keep no-copy / no-translation discipline explicit
- keep issue tracking explicit about `reference only`

### Z1. E1000 Clean-Room NIC Slice

Why first:

- highest near-term hardware value
- lowest architectural disruption
- reuses ZAR's existing ARP/IPv4/UDP/TCP/DHCP/DNS/HTTP/HTTPS stack
- expands NIC breadth without changing the runtime/service contract

Required closure:

- new real `src/baremetal/e1000.zig`
- PCI discovery and BAR/IRQ wiring
- PAL surface routing through selectable NIC backend
- host regression coverage
- live QEMU `e1000` proof

Tracking doc:

- `docs/zig-port/ZAR_VS_ZIGOS_E1000_SLICE_PLAN.md`

### Z2. Benchmark And Stress Lane

Why second:

- low legal risk
- low architecture risk
- improves confidence in the existing ZAR bare-metal stack

Required closure:

- scheduler latency probes
- allocator and syscall microbenchmarks
- network stress probes
- optional SMP stress once SMP breadth is expanded

### Z3. ZAR-Native Introspection FS Layer

Scope:

- `tmpfs`
- `devfs`
- `procfs`
- `sysfs`

This is not a direct VFS transplant. It is a ZAR-native exported tree over:

- runtime state
- package/workspace/app state
- trust store
- display outputs
- device/export state

### Z4. Shell And Interactive Control Layer

Scope:

- parser
- globbing
- job-control ideas
- interactive console/editor concepts

This phase is allowed only after ZAR decides whether the shell is:

- a builtin command/runtime surface over existing services
- or the start of a future userspace model

### Z5. Additional Hardware Breadth

Candidates:

- `virtio-net`
- `virtio-block`
- `USB/UHCI`
- `AC97`

This phase comes after Z1 because E1000 yields broader network confidence faster.

### Z6. IPv6 / Socket Model

Scope:

- IPv6
- ICMPv6
- socket-style API
- richer route management

This is meaningful only after NIC breadth is improved.

### Z7. GP-OS Direction Decision

Separate, major decision point:

- ELF loader
- ring3 userspace
- syscall ABI
- process model
- signals
- IPC
- userland programs
- external-mount filesystems such as ext2/FAT32

This is not an incremental `FS5.5` tweak. It is a product-direction fork.

## First Adoption Slice

The first realistic slice is `E1000`, not VFS, ELF, syscalls, or shell.

Reason:

- it is cleanly bounded
- it uses existing ZAR networking and probe infrastructure
- it delivers immediate hardware breadth
- it avoids forcing ZAR into a GP-OS redesign prematurely

## Non-Goals

These are explicitly not part of the first ZigOS reference track:

- copying ZigOS code
- claiming ZigOS licensing is resolved
- direct VFS import
- direct ext2/FAT32 import
- direct shell import
- direct syscall/process import
- direct ELF/userland import
- claiming ZigOS solves physical HDMI/DisplayPort scanout by itself

## Success Gates

Any ZigOS-inspired ZAR slice must satisfy all of the following:

1. implementation is ZAR-owned and clean-room
2. host regression coverage exists
3. live bare-metal proof exists where hardware semantics matter
4. `zig build test --summary all` is green
5. parity gate is green
6. docs status gate is green
7. `zig-ci` is green
8. `docs-pages` is green
9. this integration plan and the relevant phase tracking docs are updated

## Immediate Follow-Up

The next concrete document is the clean-room E1000 plan:

- `docs/zig-port/ZAR_VS_ZIGOS_E1000_SLICE_PLAN.md`
