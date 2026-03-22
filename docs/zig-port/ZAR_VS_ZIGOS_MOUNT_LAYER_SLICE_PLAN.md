<!-- SPDX-License-Identifier: GPL-2.0-only -->
# ZAR vs ZigOS Mount Layer Slice Plan

## Scope

Bounded persistent mount aliases on top of the existing ZAR filesystem and storage backend.

This is not a full VFS import. It is a ZAR-native layering step inspired by ZigOS mount and path-routing structure.

## Delivered

- `src/baremetal/mount_table.zig`
  - bounded in-memory alias table
  - alias validation
  - `/mnt/<alias>/...` resolution
- `src/baremetal/filesystem.zig`
  - persisted mount registry under `/runtime/mounts/<alias>.txt`
  - `/mnt` root exposure
  - alias reload on init
  - alias reload after direct registry writes/deletes
- `src/baremetal_main.zig`
  - bounded `virtio-block` mount proof
- `scripts/baremetal-qemu-virtio-block-mount-probe-check.ps1`
  - live QEMU proof on `virtio-blk-pci`

## Why this slice exists

- It adapts a useful ZigOS/VFS idea without importing ZigOS path semantics wholesale.
- It expands storage/runtime layering on top of already-validated ZAR persistence.
- It keeps the legal and architectural boundary clean.

## Explicit non-goals

- no general mount syscall ABI
- no dynamic device-backed mount manager
- no full VFS abstraction layer
- no ext2/fat32 import
- no ZigOS code transplant

## Proof boundary

The live proof binds:

- `boot -> /boot`
- `runtime -> /runtime`

Then proves:

- `/mnt/boot/loader.cfg` readback
- `/mnt/runtime/state/mounted-via-alias.txt` write/readback
- filesystem reset/re-init
- persisted alias reload from `/runtime/mounts/*.txt`
- persisted alias payload readback after reload

## Next follow-on options

1. extend the same bounded mount layer into `virtio-block` installer/runtime flows
2. add ZAR-native `tmpfs` / `proc` / `sys` mount registration on the same alias table
3. stop here and defer any real VFS work until a dedicated architecture decision is made
