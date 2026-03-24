# FS5.7 i386 CPU Architecture Support

## Scope

Start `FS5.7` with a real bounded `i386` freestanding lane, without falsely claiming full 32-bit parity for the existing `x86_64` driver/runtime matrix.

## Delivered Slices

### Slice 1: i386 Build and Boot Proof
- `build.zig` now emits a second freestanding artifact:
  - `zig build baremetal-i386`
  - output: `zig-out/bin/openclaw-zig-baremetal-i386.elf`
- new 32-bit bootstrap path:
  - `scripts/baremetal/i386_boot.S`
  - `scripts/baremetal/i386_lld.ld`
- new validation:
  - `scripts/baremetal-i386-smoke-check.ps1`
  - `scripts/baremetal-qemu-i386-smoke-check.ps1`
- hosted CI and `release-preview` now execute both i386 checks.

### Slice 2: i386 Descriptor and Runtime-Safe Bootstrap Parity

- `src/baremetal/x86_bootstrap.zig` now carries additive dual-arch descriptor layout support:
  - runtime `IDT` entry layout is now `8` bytes on `x86` and `16` bytes on `x86_64`
  - runtime descriptor-pointer base width is now `u32` on `x86` and `u64` on `x86_64`
  - descriptor-load telemetry now accepts both `x86` and `x86_64` freestanding runtime arches
- `src/baremetal/vga_text_console.zig` now treats both `x86` and `x86_64` freestanding guests as hardware-backed VGA text targets
- `src/baremetal_main.zig` now treats both `x86` and `x86_64` freestanding guests as valid `pause`, `cli`/`sti`, and QEMU debug-console targets
- `scripts/baremetal-i386-smoke-check.ps1` now validates the emitted i386 ELF symbol table for descriptor exports:
  - `oc_gdtr_ptr`
  - `oc_idtr_ptr`
  - `oc_gdt_ptr`
  - `oc_idt_ptr`
  - `oc_descriptor_tables_ready`
  - `oc_descriptor_tables_loaded`
  - `oc_try_load_descriptor_tables`

### Slice 3: i386 Hardware Guard Widening and Bootstrap SSE Fix

- `scripts/baremetal/i386_boot.S` now enables x87/SSE before entering Zig runtime:
  - clears `CR0.EM`
  - clears `CR0.TS`
  - sets `CR0.MP`
  - sets `CR0.NE`
  - sets `CR4.OSFXSR`
  - sets `CR4.OSXMMEXCPT`
  - runs `fninit`
- hardware-backed freestanding `x86` guards are now widened in:
  - `src/baremetal/pci.zig`
  - `src/baremetal/ata_pio_disk.zig`
  - `src/baremetal/rtl8139.zig`
  - `src/baremetal/e1000.zig`
  - `src/baremetal/framebuffer_console.zig`
  - `src/baremetal/ps2_input.zig`
  - `src/baremetal/virtio_block.zig`
  - `src/baremetal/virtio_gpu.zig`
  - `src/baremetal/virtio_net.zig`
  - `src/pal/net.zig`
  - `src/pal/tls_client_light.zig`

### Slice 4: i386 Live Storage and NIC Proofs

- new live QEMU probes:
  - `scripts/baremetal-qemu-i386-ata-storage-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-e1000-probe-check.ps1`
- the ATA lane now proves on a real i386 guest:
  - partition-mounted ATA PIO access
  - raw block mutation + readback
  - tool-layout persistence
  - filesystem persistence
- the E1000 lane now proves on a real i386 guest:
  - PCI bind
  - raw frame TX/RX
  - MAC readout
  - bounded counter advance
- hosted CI and `release-preview` now execute:
  - `scripts/baremetal-qemu-i386-ata-storage-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-e1000-probe-check.ps1`

### Slice 5: i386 RTL8139, VGA, and E1000 Protocol Lanes

- `src/baremetal/rtl8139.zig` now exposes a bounded hardware-loopback enablement seam for the raw freestanding probe path
- `src/baremetal_main.zig` now enables that bounded RTL8139 loopback path on hardware-backed non-test probe runs before the raw frame send/poll check
- new live i386 QEMU probes:
  - `scripts/baremetal-qemu-i386-rtl8139-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-vga-console-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-e1000-arp-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-e1000-ipv4-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-e1000-udp-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-e1000-tcp-probe-check.ps1`
- the i386 RTL8139 lane now proves on a real guest:
  - PCI bind
  - MAC readout
  - bounded raw frame TX/RX
  - counter advance
- the first live i386 display lane is now closed through a bounded VGA console-state proof:
  - VGA text backend selected
  - expected `80x25` geometry
  - cursor advance after `OK`
  - write/clear counters
- the i386 E1000 lane now also proves on a real guest:
  - `ARP`
  - `IPv4`
  - `UDP`
  - bounded `TCP`
- hosted CI and `release-preview` now execute all six new i386 probe scripts as part of the existing i386 optional QEMU lane

### Slice 6: i386 Higher Protocol, Service, and Display Lanes

- new live i386 QEMU probes:
  - `scripts/baremetal-qemu-i386-framebuffer-console-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-gpu-display-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-e1000-dhcp-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-e1000-dns-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-e1000-http-post-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-e1000-https-post-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-e1000-tool-service-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-rtl8139-arp-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-rtl8139-ipv4-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-rtl8139-udp-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-rtl8139-tcp-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-rtl8139-runtime-service-probe-check.ps1`
- `src/runtime/tool_runtime.zig` now explicitly fences hosted process-management methods off on `windows`, `wasi`, and `freestanding`, so the i386 freestanding display and service builds no longer instantiate unsupported hosted process code
- `src/baremetal_main.zig` now uses the same bounded internal loopback hook for the raw `RTL8139` `IPv4` and `UDP` probes that the later `TCP` and runtime-service lanes already used, removing fragile dependence on external receive progress for non-ARP protocol proofs
- the i386 display lane now also proves on a real guest:
  - bounded linear framebuffer console state at `640x400`
  - first i386 `virtio-gpu` EDID/output inventory proof on the live controller path
- the i386 E1000 lane now also proves on a real guest:
  - `DHCP`
  - `DNS`
  - `HTTP`
  - `HTTPS`
  - bounded framed tool-service reuse
- the i386 RTL8139 lane now also proves on a real guest:
  - `ARP`
  - `IPv4`
  - `UDP`
  - bounded `TCP`
  - bounded runtime-service reuse
- hosted CI and `release-preview` now execute those additional i386 probe scripts as part of the optional QEMU lane

## ZigOS Follow-On Work

- next adoption analysis is stored in:
  - `docs/zig-port/ZAR_VS_ZIGOS_NEXT_ADOPTION_OPPORTUNITIES.md`
- highest-value next ZigOS-derived upgrades after the current i386 slice are:
  - `ACPI`
  - `timer` / `interrupt` hardening
  - `SMP`
  - bounded `USB/UHCI`
  - bounded `AC97`
  - richer `tmpfs/devfs/procfs/sysfs`
  - deeper mounted `ext2/fat32`

## What This Proves

- the freestanding runtime builds for `x86-freestanding-none`
- the emitted artifact is `ELF32`
- the artifact keeps the required Multiboot2 header
- the artifact carries the PVH ELF note required by the current direct QEMU `-kernel` path
- `qemu-system-i386` boots the artifact far enough to reach `baremetalStart()` and exit through the existing `isa-debug-exit` smoke path
- the x86 bootstrap/descriptor export seam is no longer implicitly hard-coded to `x86_64`
- the i386 artifact exports the descriptor telemetry/control symbols required by the existing bare-metal ABI surface
- the i386 freestanding runtime now has additive support for QEMU debug-console writes, interrupt enable/disable toggles, and VGA text console hardware access
- the i386 bootstrap is now safe for Zig-generated SSE/x87 runtime instructions
- the i386 freestanding runtime now has live ATA-backed storage proof
- the i386 freestanding runtime now has live E1000 raw-frame NIC proof
- the i386 freestanding runtime now has live RTL8139 raw-frame NIC proof
- the i386 freestanding runtime now has the first live display proof through bounded VGA console-state inspection
- the i386 freestanding runtime now has live E1000 `ARP` / `IPv4` / `UDP` / bounded `TCP` proof
- the i386 freestanding runtime now has live E1000 `DHCP` / `DNS` / `HTTP` / `HTTPS` / bounded tool-service proof
- the i386 freestanding runtime now has live RTL8139 `ARP` / `IPv4` / `UDP` / bounded `TCP` / bounded runtime-service proof
- the i386 freestanding runtime now has live linear-framebuffer console proof
- the i386 freestanding runtime now has the first live `virtio-gpu` display proof on the i386 controller path

## Current Boundary

- this is build/boot smoke plus additive descriptor/bootstrap/runtime parity and the first broad real i386 storage/NIC/display/service lanes
- it is not yet full 32-bit driver/runtime parity
- descriptor telemetry is now dual-arch, but the broader descriptor/mailbox live proof lane is still only claimed on the existing `x86_64` PVH artifact
- i386 `RTL8139` higher protocol reuse beyond bounded `TCP` / runtime-service is still open:
  - `DHCP`
  - `DNS`
  - `HTTP`
  - `HTTPS`
  - gateway-routing proof
- i386 `virtio-net` and `virtio-block` deeper runtime/mount lanes are still open
- i386 display coverage is now bounded VGA + framebuffer + `virtio-gpu`, not the full display/profile/output matrix already proven on `x86_64`

## Next Steps

1. widen the i386 `RTL8139` matrix beyond bounded `TCP` / runtime-service:
   - `DHCP`
   - `DNS`
   - `HTTP`
   - `HTTPS`
   - gateway routing
2. widen i386 storage from raw ATA to broader mounted/runtime proof lanes:
   - `virtio-block`
   - bounded mount layer
   - bounded external filesystems
3. widen i386 NIC breadth after `E1000` / `RTL8139`:
   - `virtio-net`
   - bounded protocol/service reuse
