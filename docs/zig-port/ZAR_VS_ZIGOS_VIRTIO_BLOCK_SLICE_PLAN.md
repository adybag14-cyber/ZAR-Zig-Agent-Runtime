# ZAR vs ZigOS Virtio-Block Slice Plan

## Status

This tracks the bounded ZigOS-inspired `virtio-block` storage breadth slice for ZAR.

Current posture:

- upstream ZigOS is `MIT` licensed
- this slice remains ZAR-owned and probe-driven
- this slice uses ZigOS `VirtIO` storage breadth as design reference, not as a drop-in transplant

## Scope

The bounded scope for this slice is:

1. `virtio-block` PCI transport bring-up
2. shared storage-backend routing through the existing ZAR storage facade
3. bounded filesystem/tool-layout persistence on that backend
4. canonical installer/runtime proof on that backend

Out of scope:

1. generalized VFS mount semantics
2. `virtio-fs`
3. external on-disk filesystem imports such as `ext2` or `fat32`
4. userland mount tooling or shell semantics

## Delivered

- `src/baremetal/virtio_block.zig` provides a ZAR-owned modern `virtio-block` path with queue bring-up plus bounded read/write/flush requests
- `src/baremetal/pci.zig` discovers modern `virtio-block` PCI capability regions
- `src/baremetal/storage_backend.zig` prefers `virtio-block` over RAM-disk when available, while still preferring ATA PIO if both hardware-backed backends are present
- `scripts/baremetal-qemu-virtio-block-probe-check.ps1` proves live raw mutation, tool-layout readback, and filesystem superblock readback on the `virtio-block` path
- `src/baremetal_main.zig` now also carries a bounded `virtio-block` installer/runtime proof that seeds the canonical `/boot`, `/system`, `/runtime/install`, and bootstrap-package layout through `src/baremetal/disk_installer.zig`
- `scripts/baremetal-qemu-virtio-block-installer-probe-check.ps1` now proves live QEMU `virtio-block` installer/runtime persistence through loader-config readback markers, filesystem magic, tool-layout magic, and bootstrap-state persistence on the raw image

## Closure Bar

This slice is closed only when all of the following are true:

1. host regressions prove `virtio-block` raw transport and installer/runtime persistence
2. live QEMU proves the same installer/runtime persistence on the real `virtio-blk-pci` path
3. docs and tracking explicitly call out that this is still ZAR's existing storage/filesystem stack riding on `virtio-block`, not a full ZigOS VFS transplant

## Next Likely Follow-On

After this slice, the next realistic ZigOS-derived hardware/runtime directions are:

1. `USB/UHCI` bounded root-hub/port-state bring-up
2. `AC97` only if audio becomes higher priority
3. broader storage/runtime layering such as `virtio-fs` only after a deliberate ZAR-side design decision
