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

## Current Boundary

- this is build/boot smoke plus additive descriptor/bootstrap/runtime parity and the first real i386 hardware lanes
- it is not yet full 32-bit driver/runtime parity
- no live `i386` display probe lane is claimed yet
- the raw `RTL8139` i386 lane is not claimed yet; the current i386 guest still returns probe code `0x71` on that path
- descriptor telemetry is now dual-arch, but the broader descriptor/mailbox live proof lane is still only claimed on the existing `x86_64` PVH artifact
- higher protocol reuse on i386 (`ARP` / `IPv4` / `UDP` / `TCP` / service framing) is still only claimed on `x86_64`

## Next Steps

1. close the remaining raw `RTL8139` i386 lane
2. ship the first live i386 display proof:
   - VGA first
   - then framebuffer
3. widen the i386 NIC/storage matrix beyond raw proof:
   - `ARP`
   - `IPv4`
   - `UDP`
   - `TCP`
   - bounded service reuse
