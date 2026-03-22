<!-- SPDX-License-Identifier: GPL-2.0-only -->
# ZAR vs ZigOS Mounted ext2/FAT Filesystem Slice Plan

## Objective

Move from raw on-disk filesystem detection to bounded mounted external-filesystem support without forcing a full GP-OS VFS/syscall transplant into ZAR.

This slice is informed by ZigOS filesystem breadth and may use Linux and ZigOS as references, but the implementation remains ZAR-native.

## Current delivered seam

Already delivered:

- raw `zarfs` / `ext2` / `fat32` detection on the active backend
- bounded storage-layer registry over:
  - persistent root
  - `tmpfs`
  - virtual trees
  - persisted `/mnt/<alias>` routes
- bounded backend-registry export over:
  - `ram_disk`
  - `ata_pio`
  - `virtio_block`
- runtime-visible filesystem capability matrix through:
  - `/dev/storage/filesystems`
  - `/sys/storage/filesystems`

Current capability posture:

- `zarfs`
  - detect: yes
  - mount: yes
  - write: yes
- `tmpfs`
  - detect: synthetic
  - mount: yes
  - write: yes
- `ext2`
  - detect: yes
  - mount: not yet
  - write: not yet
- `fat32`
  - detect: yes
  - mount: not yet
  - write: not yet

## Deliberate scope for the next external-filesystem step

First bounded mounted-filesystem phase:

1. read-only external mount classification
2. explicit mount target under `/mnt/fs/<name>` or equivalent bounded alias
3. bounded directory listing
4. bounded file read
5. no write path
6. no journaling
7. no userspace syscall ABI
8. no import of a full ZigOS VFS/userspace model

## Recommended sequence

### Phase A: ext2 read-only mount

Deliver:

- ext2 superblock parse
- block-group descriptor parse
- inode lookup for directories/files
- directory entry iteration
- read-only file data path for direct and singly-indirect blocks if needed
- bounded mount proof against a deterministic ext2 image on `virtio-block` or `ATA`

Do not deliver yet:

- ext2 writes
- permissions/ownership semantics beyond bounded metadata export
- symlink/device/special-node parity

### Phase B: FAT32 read-only mount

Deliver:

- BPB + FAT32 info-sector parse
- cluster-chain walk
- short-name directory iteration
- bounded long-file-name handling only if needed by proofs
- read-only file data path
- bounded mount proof against a deterministic FAT32 image

Do not deliver yet:

- FAT writes
- VFAT edge-case parity beyond the bounded proof surface

### Phase C: mount registry integration

After A and B:

- extend mount registry records with `filesystem=<kind>`
- extend VFS router so mounted external roots participate through the same bounded path seam
- keep mounted external roots read-only until a later write-design slice exists

## Required ZAR-native success gates

Before the ext2/FAT slice is considered delivered:

- host/module tests for parser and bounded read paths
- live QEMU proof with deterministic external disk image
- no regressions in:
  - `zig build test --summary all`
  - parity gate
  - docs status gate
  - `zig-ci`
  - `docs-pages`

## Explicit non-goals

- no POSIX syscall mount ABI
- no general-purpose userland `mount(2)` surface
- no full devfs/procfs/ext2/fat32 transplant from ZigOS
- no writable external filesystem support in the first slice

## Why this is the right boundary

ZAR now has enough VFS/storage structure to support bounded mounted external-filesystem work.

What it still does not have, and does not need for this step, is:

- a GP-OS syscall model
- a full shell/userland mount contract
- writable ext2/FAT semantics

That keeps the implementation compatible with ZAR’s current appliance/runtime architecture instead of forcing an architectural fork mid-slice.
