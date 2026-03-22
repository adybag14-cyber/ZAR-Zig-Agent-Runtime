# ZAR vs ZigOS Virtio-Net Slice Plan

## Purpose

This is the next bounded ZigOS-derived hardware-breadth slice after `E1000` and `virtio-block`.

Why `virtio-net`:

- it expands the real NIC matrix with a second paravirtual path
- it fits ZAR's current FS5.5 bare-metal proof model
- it reuses the already-shipped ZAR raw-frame and protocol stack seams
- it does not force VFS, ELF, syscall, or userland redesign

## Provenance Rule

Upstream ZigOS is now `MIT`-licensed, but ZAR still treats this slice as an adapted ZAR-owned implementation.

This slice must:

- keep ZAR-owned code, tests, and probes
- adapt behavior to ZAR's PAL/ABI seams
- satisfy ZAR-native proof and release gates

This slice must not:

- bypass ZAR validation with upstream-only assumptions
- widen into a general-purpose OS redesign

## Reference Inputs

Reference inputs:

- ZigOS:
  - `src/kernel/drivers/virtio.zig`
  - `src/kernel/drivers/pci.zig`
- Current ZAR:
  - `src/baremetal/pci.zig`
  - `src/baremetal/virtio_block.zig`
  - `src/baremetal/e1000.zig`
  - `src/pal/net.zig`
  - `src/protocol/ethernet.zig`
  - `src/baremetal_main.zig`

## Target Outcome

ZAR should support a third real NIC-family/backend lane on the same network surface:

- `RTL8139`
- `E1000`
- `virtio-net`

through the same raw-frame PAL seam first, then the broader protocol stack later.

## Current Status

Delivered so far:

- modern `virtio-net` PCI discovery in `src/baremetal/pci.zig`
- ZAR-owned `virtio-net` driver bring-up in `src/baremetal/virtio_net.zig`
- PAL backend routing through `src/pal/net.zig`
- host regressions for init, MAC readout, TX, RX, and export-surface stability
- host regressions for `ARP`, `IPv4`, `UDP`, `DHCP`, `DNS`, and bounded `TCP` protocol reuse on the clean-room `virtio-net` path
- live QEMU raw-frame plus `ARP` / `IPv4` / `UDP` / `DHCP` / `DNS` / bounded `TCP` proof through `scripts/baremetal-qemu-virtio-net-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-arp-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-ipv4-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-udp-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-dhcp-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-dns-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-tcp-probe-check.ps1`, and `scripts/qemu-virtio-net-dgram-echo.ps1`

## Deliverables

### V0. Discovery And Transport Contract

- identify the first QEMU `virtio-net-pci` target
- require the modern PCI capability path
- require `VIRTIO_F_VERSION_1`
- require MAC feature export

### V1. Driver Module

- add `src/baremetal/virtio_net.zig`
- implement:
  - PCI bind
  - feature negotiation
  - RX/TX queue bring-up
  - MAC readout
  - raw frame send
  - raw frame receive
  - bounded counters/telemetry

### V2. Shared NIC Surface

- route the PAL raw-frame seam through:
  - `RTL8139`
  - `E1000`
  - `virtio-net`
- keep existing backends green

### V3. Host Regression Layer

- prove:
  - init
  - MAC readout
  - TX
  - RX
  - export-surface stability

### V4. Live Raw-Frame Probe

- add:
  - `scripts/baremetal-qemu-virtio-net-probe-check.ps1`
  - `scripts/qemu-virtio-net-dgram-echo.ps1`
- prove:
  - PCI bind
  - MAC readout
  - TX
  - RX
  - payload validation
  - counter advance

### V5. Protocol Reuse

Delivered now:

- `ARP`
- `IPv4`
- `UDP`
- `DHCP`
- `DNS`
- bounded `TCP`

Future depth after this protocol step:

- tool-service / `HTTP` / `HTTPS`

## Explicit Non-Goals

Not in this slice:

- generalized virtio framework redesign
- sockets API
- VFS redesign
- ELF/userspace
- syscalls/processes
- shell/userland
- physical HDMI/DisplayPort work

## Success Gates

1. `src/baremetal/virtio_net.zig` exists and is not a stub. Status: `Done`
2. host regressions prove init/TX/RX behavior. Status: `Done`
3. PAL backend selection includes `virtio-net` without regressing `RTL8139` or `E1000`. Status: `Done`
4. live QEMU `virtio-net-pci` raw-frame proof is green. Status: `Done`
5. `ARP` / `IPv4` / `UDP` / `DHCP` / `DNS` / bounded `TCP` protocol reuse is delivered on the `virtio-net` path. Status: `Done`
6. `zig build test --summary all` is green. Status: `Done`
7. parity gate is green. Status: `Done`
8. docs status gate is green. Status: `Done`
9. `zig-ci` is green. Status: `Done after push`
10. `docs-pages` is green. Status: `Done after push`

## Exit Criteria

Once this slice is green, ZAR has:

- a third real NIC/backend path
- broader hardware breadth from the ZigOS-inspired track
- a clean platform for later `virtio-net` tool-service / `HTTP` / `HTTPS` reuse

