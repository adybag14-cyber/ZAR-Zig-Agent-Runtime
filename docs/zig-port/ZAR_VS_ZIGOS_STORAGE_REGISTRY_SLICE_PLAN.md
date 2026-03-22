<!-- SPDX-License-Identifier: GPL-2.0-only -->
# ZAR vs ZigOS Storage Registry And Filesystem Probe Slice Plan

## Scope

Bounded storage-layer registry plus raw ext2/FAT detection on top of the current ZAR storage backend.

This is a ZAR-native layering step inspired by ZigOS filesystem breadth. It is not a direct import and it is not a full ext2/FAT mount implementation.

## Delivered

- `src/baremetal/storage_registry.zig`
  - bounded registry over:
    - persistent root
    - `/tmp`
    - `/proc`
    - `/dev`
    - `/sys`
    - persisted `/mnt/<alias>` entries
  - per-entry export of:
    - route path
    - target path
    - layer kind
    - storage backend
    - detected filesystem kind
    - mounted flag
    - block size / block count / logical base LBA on persistent entries
  - raw filesystem probes for:
    - `zarfs`
    - `ext2`
    - `fat32`
- `src/baremetal/virtual_fs.zig`
  - new read-only files:
    - `/dev/storage/registry`
    - `/sys/storage/registry`
  - `/sys/storage/state` now also exports:
    - `detected_filesystem`
    - `supported_filesystem_probes=zarfs,ext2,fat32`
- `src/baremetal_main.zig`
  - widened `virtio-block` mount proof now checks:
    - `/sys/storage/state`
    - `/sys/storage/registry`
    - persistent entries classified as `zarfs`
    - `/mnt/cache -> /tmp/cache` classified as `tmpfs`

## Why this slice exists

- It gives ZAR a real storage-layer registry above RAM-disk, ATA, and `virtio-block`.
- It adds the first honest ext2/FAT integration seam without pretending those filesystems are mounted.
- It creates the decision point for future external-filesystem work using real on-disk classification instead of guesses.

## Explicit non-goals

- no mounted ext2 implementation
- no mounted FAT/FAT32 implementation
- no generalized mount syscall ABI
- no imported ZigOS ext2/fat32 code
- no userspace-visible GP-OS VFS contract

## Proof boundary

Host validation now proves:

- persistent filesystem detection as `zarfs`
- synthetic `fat32` boot-sector detection
- synthetic `ext2` superblock detection
- registry rendering across persistent, tmpfs, virtual, and mounted alias layers

Live `virtio-blk-pci` validation now proves:

- `/sys/storage/state` reports `backend=virtio_block`
- `/sys/storage/state` reports `detected_filesystem=zarfs`
- `/sys/storage/registry` includes:
  - persistent root on `virtio_block`
  - persisted `/mnt/boot` and `/mnt/runtime`
  - volatile `/mnt/cache -> /tmp/cache`

## Follow-on options

1. add a bounded storage-driver registry for multiple persistent devices instead of only the active backend
2. add read-only ext2/FAT directory inspection on top of the new raw probes
3. defer writable external-filesystem support until a deliberate mount/VFS design slice is chosen
