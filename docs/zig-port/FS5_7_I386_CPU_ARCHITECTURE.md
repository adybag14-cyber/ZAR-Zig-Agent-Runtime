# FS5.7 i386 CPU Architecture Support

## Scope

Start `FS5.7` with a real bounded `i386` freestanding lane, without falsely claiming full 32-bit parity for the existing `x86_64` driver/runtime matrix.

## First Delivered Slice

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

## What This Proves

- the freestanding runtime builds for `x86-freestanding-none`
- the emitted artifact is `ELF32`
- the artifact keeps the required Multiboot2 header
- the artifact carries the PVH ELF note required by the current direct QEMU `-kernel` path
- `qemu-system-i386` boots the artifact far enough to reach `baremetalStart()` and exit through the existing `isa-debug-exit` smoke path

## Current Boundary

- this is build/boot smoke plus direct-QEMU entry proof
- it is not yet full 32-bit driver/runtime parity
- no live `i386` NIC/storage/display probe lanes are claimed yet
- `src/baremetal/x86_bootstrap.zig` still carries the current `x86_64` descriptor-table layout and needs an explicit `i386` follow-up

## Next Steps

1. make the bootstrap/descriptor seam dual-arch instead of implicitly `x86_64`
2. classify each freestanding subsystem into:
   - already 32-bit-safe
   - safe after guard widening
   - still blocked on `x86_64` assumptions
3. ship the first bounded live `i386` subsystem proof beyond smoke
