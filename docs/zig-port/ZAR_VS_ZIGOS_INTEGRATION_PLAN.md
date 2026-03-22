# ZAR vs ZigOS Integration Plan

## Status

This document tracks the strict integration plan for ideas, adapted code, and feature targets observed in `Cameron-Lyons/zigos`.

Current posture:

- ZigOS upstream is now explicitly `MIT` licensed.
- ZAR can legally study, adapt, or import ZigOS code when that is the right engineering choice.
- Current delivered slices remain ZAR-owned implementations with ZAR-native tests, probes, and release gates.
- Delivered ZigOS-inspired slices now cover NIC breadth, benchmark/stress, introspection overlays, storage breadth, mount layering, a bounded internal VFS router, and a bounded storage registry plus ext2/FAT probe seam.

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

## License And Provenance

ZigOS now publishes an explicit upstream `MIT` license.

That removes the previous legal blocker, but it does not remove ZAR's engineering requirements:

1. imported or adapted code still needs ZAR-side ownership and review
2. every adopted slice still needs ZAR-native validation
3. issue/docs tracking must stay explicit about what was referenced, adapted, or reimplemented

Any ZAR slice influenced by ZigOS must satisfy all of the following:

1. implementation is either ZAR-owned or explicitly tracked as adapted/imported ZigOS code
2. tests remain ZAR-owned
3. live probe coverage remains ZAR-owned
4. provenance stays explicit in docs and issue tracking
5. each slice is labeled as `reference-inspired`, `adapted`, or `imported`

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
| `VFS core` | `src/kernel/fs/vfs.zig` | High | Adapt now, bounded | Bounded internal VFS router delivered; broader mount/filesystem model remains redesign |
| `tmpfs` | `src/kernel/fs/tmpfs.zig` | Medium-high | Adapt now | Delivered bounded `/tmp` slice; broader mount semantics later |
| `devfs` | `src/kernel/fs/devfs.zig` | Medium-high | Adapt now | First bounded read-only `/dev` overlay delivered; broader device/VFS model remains later |
| `procfs` | `src/kernel/fs/procfs.zig` | Medium-high | Adapt now | First bounded read-only `/proc` overlay delivered; broader VFS remains later |
| `sysfs` | `src/kernel/fs/sysfs.zig` | Medium-high | Adapt now | First bounded read-only `/sys` overlay delivered; broader VFS remains later |
| `ext2` | `src/kernel/fs/ext2.zig` | Medium | Adapt now, bounded | Raw on-disk detection now; mount/read model later |
| `fat32` | `src/kernel/fs/fat32.zig` | Medium | Adapt now, bounded | Raw on-disk detection now; mount/read model later |
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

The order below is strict. It favors bounded, low-risk wins before any redesign-heavy GP-OS work.

### Z0. Provenance Discipline

Required before any ZigOS-inspired implementation work:

- keep this document current
- keep provenance explicit
- keep issue tracking explicit about whether a slice is `reference-inspired`, `adapted`, or `imported`

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

Current delivered scope:

- `src/benchmark_suite.zig`
- `src/benchmark_main.zig`
- `scripts/benchmark-smoke-check.ps1`
- hosted benchmark catalog for DNS, DHCP, TCP, runtime-state, tool-service codec churn, filesystem churn, and synthetic NIC loopback comparisons across `RTL8139` and `E1000`

Tracking doc:

- `docs/zig-port/ZAR_VS_ZIGOS_BENCHMARK_SLICE_PLAN.md`

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

Current delivered scope:

- `src/baremetal/virtual_fs.zig` now exposes a bounded read-only `/proc` + `/sys` overlay over existing ZAR state
- `src/baremetal/filesystem.zig` now routes `readFileAlloc`, `listDirectoryAlloc`, and `statSummary` through that overlay and rejects writes under `/proc` / `/sys`
- `src/baremetal/tool_exec.zig` and `src/baremetal/tool_service.zig` reuse the existing builtin and typed `GET` / `LIST` / `STAT` surface for the overlay
- `scripts/baremetal-qemu-e1000-tool-service-probe-check.ps1` now proves the overlay live on the clean-room `E1000` tool-service path
- `src/baremetal/virtual_fs.zig` now also exposes a bounded read-only `/dev` overlay over existing ZAR storage, display, and network device state
- `src/baremetal/filesystem.zig` now routes `readFileAlloc`, `listDirectoryAlloc`, and `statSummary` through that `/dev` overlay and rejects writes under `/dev`
- `src/baremetal/tool_exec.zig` and `src/baremetal/tool_service.zig` now reuse the same builtin and typed `GET` / `LIST` / `STAT` surface for `/dev`
- `scripts/baremetal-qemu-e1000-tool-service-probe-check.ps1` now proves `/`, `/dev`, and `/dev/storage/state` live on the `E1000` tool-service path
- `src/baremetal/tmpfs.zig` now provides a bounded non-persistent `/tmp` surface wired through `src/baremetal/filesystem.zig`, with host regression coverage for create/write/read/list/stat/delete and reset semantics
- `src/baremetal/vfs.zig` plus `src/baremetal/filesystem.zig` now add a bounded internal VFS router that owns normalization, alias resolution, and dispatch across persistent storage, `/tmp`, `/proc`, `/dev`, `/sys`, and `/mnt`
- `scripts/baremetal-qemu-virtio-block-mount-probe-check.ps1` now proves that same VFS seam live on `virtio-blk-pci`, including root listing, `/proc/version`, persisted aliases, and `/tmp` alias volatility after reset
- `src/baremetal/storage_registry.zig` now adds a bounded storage-layer registry over persistent, tmpfs, virtual, and mounted-alias routes, plus raw `zarfs` / `ext2` / `fat32` detection on the active backend
- `src/baremetal/virtual_fs.zig` now exposes that storage registry through `/dev/storage/registry` and `/sys/storage/registry`, while `/sys/storage/state` now also reports the detected filesystem kind and supported probe set
- `scripts/baremetal-qemu-virtio-block-mount-probe-check.ps1` now also proves the storage registry and detected-filesystem seam live on `virtio-blk-pci`

Still intentionally out of scope for this slice:

- full VFS mount model
- mounted external on-disk filesystems such as `ext2` / `fat32`
- userspace-facing path semantics beyond the current read-only introspection tree

### Z3b. Virtio-Block Storage Breadth

Scope:

- bounded `virtio-block` transport for ZAR's existing storage facade
- mock-backed host validation
- live QEMU proof over the existing installer/filesystem stack

Current delivered scope:

- `src/baremetal/virtio_block.zig` now provides a ZAR-owned modern `virtio-block` path with common-config/device-config queue bring-up, bounded read/write/flush requests, and mock-backed host validation
- `src/baremetal/pci.zig` now discovers modern `virtio-block` PCI capability regions
- `src/baremetal/storage_backend.zig` now prefers `virtio-block` ahead of RAM-disk when the device is available, without regressing ATA priority when both are present
- `scripts/baremetal-qemu-virtio-block-probe-check.ps1` now proves live raw mutation, tool-layout readback, and filesystem superblock readback on the `virtio-block` path
- `src/baremetal_main.zig` now also carries a bounded installer/runtime proof on the same `virtio-block` backend through `src/baremetal/disk_installer.zig`
- `scripts/baremetal-qemu-virtio-block-installer-probe-check.ps1` now proves live canonical loader/kernel/manifest/bootstrap persistence on `virtio-blk-pci`
- `src/baremetal/mount_table.zig` plus `src/baremetal/filesystem.zig` now add a ZAR-native persistent mount layer backed by `/runtime/mounts/<alias>.txt` instead of importing a full ZigOS VFS
- `scripts/baremetal-qemu-virtio-block-mount-probe-check.ps1` now proves live alias bind/reload behavior through `/mnt/boot` and `/mnt/runtime` on the same `virtio-block` backend
- `src/baremetal/vfs.zig` now extends that storage direction into a bounded internal VFS router instead of a direct full ZigOS VFS transplant
- `src/baremetal/storage_registry.zig` now extends that same storage direction into a bounded registry over RAM-disk / ATA / `virtio-block` with raw `zarfs` / `ext2` / `fat32` detection, without claiming mounted external-filesystem support

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

Current status:

- `virtio-block` is delivered as bounded storage breadth
- `virtio-net` raw-frame plus `ARP` / `IPv4` / `UDP` closure is now delivered as bounded NIC breadth
- `USB/UHCI` and `AC97` remain future candidates

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

- direct VFS import
- direct ext2/FAT32 import
- direct shell import
- direct syscall/process import
- direct ELF/userland import
- claiming ZigOS solves physical HDMI/DisplayPort scanout by itself

## Success Gates

Any ZigOS-inspired ZAR slice must satisfy all of the following:

1. implementation has explicit provenance and review
2. host regression coverage exists
3. live bare-metal proof exists where hardware semantics matter
4. `zig build test --summary all` is green
5. parity gate is green
6. docs status gate is green
7. `zig-ci` is green
8. `docs-pages` is green
9. this integration plan and the relevant phase tracking docs are updated

## Immediate Follow-Up

Concrete ZigOS-derived tracking docs now in-tree:

- `docs/zig-port/ZAR_VS_ZIGOS_E1000_SLICE_PLAN.md`
- `docs/zig-port/ZAR_VS_ZIGOS_BENCHMARK_SLICE_PLAN.md`
