<!-- SPDX-License-Identifier: GPL-2.0-only -->
# ZAR vs ZigOS Internal VFS Slice Plan

## Scope

Bounded internal VFS routing over the current ZAR storage surfaces.

This is a ZAR-native routing layer inspired by ZigOS `vfs.zig`. It is not a direct transplant and it is not a full general-purpose OS VFS.

## Delivered

- `src/baremetal/vfs.zig`
  - path normalization
  - `/mnt` alias resolution
  - route classification across:
    - persistent filesystem
    - `tmpfs`
    - read-only `virtual_fs`
    - `/mnt` root
- `src/baremetal/filesystem.zig`
  - persistent-only helpers split from public APIs
  - public `create/write/delete/read/list/stat` now delegate through `vfs.zig`
  - merged root listing keeps the existing ZAR semantics for:
    - persistent entries
    - `dir mnt`
    - `dir tmp`
    - `dir proc`
    - `dir dev`
    - `dir sys`
- `src/baremetal_main.zig`
  - widened `virtio-block` mount proof now checks:
    - root VFS listing
    - `/proc/version` readback
    - `/mnt/cache -> /tmp/cache` volatility across reset

## Why this slice exists

- It moves ZAR from ad hoc path branching toward a real internal VFS seam.
- It makes later bounded storage/runtime slices cleaner without forcing a full GP-OS redesign.
- It keeps the proven persistent backend logic intact while centralizing route ownership.

## Explicit non-goals

- no full userspace mount ABI
- no imported ZigOS `vfs.zig`
- no `ext2` / `fat32` integration
- no shell/userspace path contract changes
- no generalized inode/device model

## Proof boundary

Host validation now proves:

- VFS route normalization and alias classification
- merged root listing across persistent FS, `/tmp`, `/mnt`, `/proc`, `/dev`, and `/sys`
- mounted alias routing into `tmpfs`
- read-only virtual tree access through the same router

Live `virtio-blk-pci` validation now proves:

- persistent `boot` and `runtime` aliases still reload correctly
- root listing exposes the expected merged VFS view
- `/proc/version` is readable through the VFS path
- `/mnt/cache -> /tmp/cache` writes succeed before reset and disappear after reload while the alias itself persists

## Follow-on options

1. add bounded mount registration for more synthetic trees on top of the same VFS seam
2. add a ZAR-native storage layer registry above `virtio-block` / ATA / RAM-disk
3. defer full on-disk filesystem work until a separate ext2/FAT/VFS decision is made
