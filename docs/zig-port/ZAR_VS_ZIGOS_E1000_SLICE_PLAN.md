# ZAR vs ZigOS E1000 Slice Plan

## Purpose

This is the first clean-room implementation plan derived from the ZigOS reference review.

Why `E1000` is first:

- it adds immediate hardware breadth
- it fits ZAR's current FS5.5 architecture
- it reuses the already-shipped ZAR protocol stack
- it does not force VFS, ELF, syscall, or userland redesign up front

## Provenance Rule

`Cameron-Lyons/zigos` may be used only as a behavioral and structural reference.

This slice must not:

- copy code
- translate code mechanically
- mirror file structure just to simulate a port

This slice must:

- implement ZAR-owned code only
- use ZAR-owned tests only
- use ZAR-owned probes only

## Reference Inputs

Reference only:

- ZigOS:
  - `src/kernel/drivers/e1000.zig`
  - `src/kernel/drivers/pci.zig`
  - `src/kernel/net/*`
- Current ZAR:
  - `src/baremetal/rtl8139.zig`
  - `src/baremetal/pci.zig`
  - `src/pal/net.zig`
  - `src/protocol/ethernet.zig`
  - `src/protocol/arp.zig`
  - `src/protocol/ipv4.zig`
  - `src/protocol/udp.zig`
  - `src/protocol/tcp.zig`
  - `src/baremetal_main.zig`

## Target Outcome

ZAR should support a second real PCI NIC family:

- `RTL8139`
- `E1000`

over the same higher network stack:

- ARP
- IPv4
- UDP
- TCP
- DHCP
- DNS
- HTTP
- HTTPS

## Current Status

Delivered so far:

- `E0. Discovery And Hardware Contract`
- `E1. Driver Module`
- `E2. Shared NIC Surface`
- `E3. Host Regression Layer`
- `E4. Live L2 Probe`
- `E5. Protocol Reuse Over E1000` (`ARP` / `IPv4` / `UDP` / bounded `TCP`)

Current delivered slice:

- `src/baremetal/e1000.zig` now provides a ZAR-owned `82540EM`-class `E1000` path with PCI bind, MMIO + legacy I/O reset, EEPROM MAC readout, bounded TX/RX rings, and raw-frame send/receive telemetry
- `src/baremetal/pci.zig` now discovers the `E1000` MMIO + I/O BAR pair and enables I/O, memory, and bus-master decode on the selected PCI function
- `src/pal/net.zig` now routes the same raw-frame PAL seam through selectable `RTL8139` and `E1000` backends without regressing the existing RTL8139 path
- host regressions now prove init, MAC readout, TX, RX, export-surface stability, and `ARP` / `IPv4` / `UDP` / bounded `TCP` protocol reuse on the clean-room `E1000` path
- `scripts/baremetal-qemu-e1000-probe-check.ps1` plus `scripts/qemu-e1000-dgram-echo.ps1` now prove live QEMU `E1000` PCI bind, MAC readout, TX, RX, payload validation, and counter advance over the freestanding PVH artifact
- `scripts/baremetal-qemu-e1000-arp-probe-check.ps1`, `scripts/baremetal-qemu-e1000-ipv4-probe-check.ps1`, `scripts/baremetal-qemu-e1000-udp-probe-check.ps1`, and `scripts/baremetal-qemu-e1000-tcp-probe-check.ps1` now prove live QEMU `E1000` ARP request transmission, IPv4 frame encode/decode, UDP datagram encode/decode, bounded TCP handshake/payload/teardown, and TX/RX counter advance over the freestanding PVH artifact
- `HTTP` / `HTTPS` reuse over `E1000` remains future depth

## Deliverables

### E0. Discovery And Hardware Contract

- identify the exact QEMU `e1000` target to support first
- define required PCI vendor/device IDs
- define MMIO vs I/O BAR usage for the first slice
- define reset / init / RX / TX / interrupt/poll contract

### E1. Driver Module

- add `src/baremetal/e1000.zig`
- implement:
  - PCI bind
  - MAC readout
  - reset/init sequence
  - RX ring setup
  - TX ring setup
  - frame send
  - frame receive
  - bounded counters/telemetry for validation

### E2. Shared NIC Surface

- factor the PAL-facing raw-frame seam so it can route through:
  - `RTL8139`
  - `E1000`
- avoid breaking existing `RTL8139` proofs
- expose active NIC kind/identity in the bare-metal export surface if useful for proofing

### E3. Host Regression Layer

- add deterministic host-side E1000 mock coverage
- prove:
  - init
  - MAC readout
  - TX
  - RX
  - basic error handling

### E4. Live L2 Probe

- add a dedicated live proof script
- likely path:
  - `scripts/baremetal-qemu-e1000-probe-check.ps1`
- prove:
  - PCI bind
  - MAC readout
  - TX
  - RX
  - payload validation
  - counter advance

### E5. Protocol Reuse Over E1000

- route the existing protocol stack through the new NIC seam
- prove:
  - ARP
  - IPv4
  - UDP
  - TCP handshake/payload/close

### E6. Routed Services Over E1000

- prove the same service surfaces now work over E1000:
  - tool TCP service
  - HTTP
  - HTTPS

This phase can be split if transport closure comes before the full service proof.

## Explicit Non-Goals

Not in this slice:

- sockets API
- VFS redesign
- ELF/userspace
- syscalls/processes
- shell/userland
- USB/audio
- physical HDMI/DisplayPort work

## Success Gates

The slice is complete only when all of the following are true:

1. `src/baremetal/e1000.zig` exists and is not a stub. Status: `Done`
2. host regressions prove init/TX/RX behavior. Status: `Done`
3. live QEMU `e1000` raw-frame proof is green. Status: `Done`
4. live QEMU `ARP` / `IPv4` / `UDP` proof is green over `E1000`. Status: `Done`
5. live QEMU `TCP` proof is green over `E1000`. Status: `Done`
6. existing RTL8139 proofs stay green. Status: `Done`
7. `zig build test --summary all` is green. Status: `Done`
8. parity gate is green. Status: `Done`
9. docs status gate is green. Status: `Done`
10. `zig-ci` is green. Status: `Pending push verification`
11. `docs-pages` is green. Status: `Pending push verification`

## Implementation Order

Strict order:

1. clean-room driver skeleton with real register contract. Status: `Done`
2. host regression harness. Status: `Done`
3. live raw-frame proof. Status: `Done`
4. protocol reuse over E1000 (`ARP` / `IPv4` / `UDP`). Status: `Done`
5. bounded `TCP` reuse over `E1000`. Status: `Done`
6. optional service/http/https reuse proof. Status: `Next`
7. docs/tracking signoff. Status: `In progress`

## Exit Criteria

Once this slice is green, ZAR has:

- two real NIC families
- a better hardware abstraction point for future drivers
- a clean starting point for later ZigOS-inspired hardware breadth

That is the correct first adoption slice. It raises real capability without forcing a GP-OS redesign prematurely.
