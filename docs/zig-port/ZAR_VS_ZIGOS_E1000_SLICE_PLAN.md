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

1. `src/baremetal/e1000.zig` exists and is not a stub
2. host regressions prove init/TX/RX behavior
3. live QEMU `e1000` raw-frame proof is green
4. live QEMU ARP/IPv4/UDP/TCP proof is green over E1000
5. existing RTL8139 proofs stay green
6. `zig build test --summary all` is green
7. parity gate is green
8. docs status gate is green
9. `zig-ci` is green
10. `docs-pages` is green

## Implementation Order

Strict order:

1. clean-room driver skeleton with real register contract
2. host regression harness
3. live raw-frame proof
4. protocol reuse over E1000
5. optional service/http/https reuse proof
6. docs/tracking signoff

## Exit Criteria

Once this slice is green, ZAR has:

- two real NIC families
- a better hardware abstraction point for future drivers
- a clean starting point for later ZigOS-inspired hardware breadth

That is the correct first adoption slice. It raises real capability without forcing a GP-OS redesign prematurely.
