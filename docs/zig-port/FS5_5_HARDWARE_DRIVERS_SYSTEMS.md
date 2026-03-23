# FS5.5 Hardware Drivers And Systems

## Purpose

`FS5.5` is the strict hardware-driver and bare-metal systems track that sits between hosted-phase closure (`FS1..FS5`) and appliance/bare-metal maturity (`FS6`).

This track exists to remove guesswork. It defines the real bare-metal subsystems that must exist as code, not as checklist language:

- framebuffer text and console
- keyboard input
- mouse input
- in-RAM disk persistence
- disk driver and block-device usage
- ethernet device driver
- tcp/ip stack bring-up
- bare-metal filesystem usage
- bare-metal tool execution substrate

## ZigOS Reference Track

Status: `Slices 1-8 delivered`

This track uses `Cameron-Lyons/zigos` as a reference architecture and source candidate where it improves ZAR.

Current provenance boundary:

- upstream license is now explicit: `MIT`
- imported or adapted ZigOS code is legally possible
- every delivered slice still has to satisfy ZAR-native proof and release gates

Tracked docs:

- `docs/zig-port/ZAR_VS_ZIGOS_INTEGRATION_PLAN.md`
- `docs/zig-port/ZAR_VS_ZIGOS_E1000_SLICE_PLAN.md`
- `docs/zig-port/ZAR_VS_ZIGOS_BENCHMARK_SLICE_PLAN.md`
- `docs/zig-port/ZAR_VS_ZIGOS_VIRTIO_NET_SLICE_PLAN.md`
- `docs/zig-port/ZAR_VS_ZIGOS_VIRTIO_BLOCK_SLICE_PLAN.md`
- `docs/zig-port/ZAR_VS_ZIGOS_SHELL_CONTROL_SLICE_PLAN.md`

Delivered first adoption slice:

- clean-room `E1000` NIC support
- first strict delivery now includes raw-frame/L2 plus `ARP`, `IPv4`, `UDP`, `DHCP`, `DNS`, and bounded `TCP`
- `src/baremetal/e1000.zig` now provides a ZAR-owned `82540EM`-class driver with PCI bind, MMIO + legacy I/O reset, EEPROM MAC readout, bounded TX/RX rings, and raw-frame send/receive telemetry
- `src/baremetal/pci.zig` now discovers the `E1000` MMIO + I/O BAR pair and enables I/O, memory, and bus-master decode on the selected function
- host regressions now prove init, MAC readout, TX, RX, export-surface stability, and `ARP` / `IPv4` / `UDP` / `DHCP` / `DNS` / bounded `TCP` protocol reuse on the clean-room `E1000` path
- `scripts/baremetal-qemu-e1000-probe-check.ps1` plus `scripts/qemu-e1000-dgram-echo.ps1` now prove live QEMU `E1000` PCI bind, MAC readout, TX, RX, payload validation, and counter advance over the freestanding PVH artifact
- `src/pal/net.zig` now routes the same raw-frame PAL seam through selectable `RTL8139` and `E1000` backends without regressing the existing RTL8139 path
- `scripts/baremetal-qemu-e1000-arp-probe-check.ps1`, `scripts/baremetal-qemu-e1000-ipv4-probe-check.ps1`, `scripts/baremetal-qemu-e1000-udp-probe-check.ps1`, `scripts/baremetal-qemu-e1000-dhcp-probe-check.ps1`, `scripts/baremetal-qemu-e1000-dns-probe-check.ps1`, and `scripts/baremetal-qemu-e1000-tcp-probe-check.ps1` now prove live QEMU `E1000` ARP request transmission, IPv4 frame encode/decode, UDP datagram encode/decode, DHCP discover encode/decode, DNS query/response exchange, bounded TCP handshake/payload/teardown, and TX/RX counter advance over the freestanding PVH artifact
- host regressions in `src/pal/net.zig` plus `src/baremetal_main.zig` now prove bounded freestanding `HTTP` / `HTTPS` transport reuse over the clean-room `E1000` path without regressing the existing `RTL8139` lane
- `scripts/baremetal-qemu-e1000-tool-service-probe-check.ps1` now proves bounded framed tool-service reuse over the clean-room `E1000` path, including `echo`, `EXEC`, `help`, persisted script install, `run-script`, and filesystem readback over the live QEMU `TCP` probe lane
- `scripts/baremetal-qemu-e1000-http-post-probe-check.ps1` now proves bounded freestanding `HTTP` POST request/response flow over the `E1000` probe lane, and `scripts/baremetal-qemu-e1000-https-post-probe-check.ps1` now proves live QEMU `E1000` `HTTPS` POST over `ARP` + `IPv4` + `TCP` + `TLS` with filesystem-backed trust-bundle selection
- do not widen scope to VFS/ELF/syscalls/userspace in this slice

Delivered second adoption slice:

- hosted benchmark and stress lane informed by ZigOS benchmark coverage
- `src/benchmark_suite.zig` now provides ZAR-native benchmark cases for DNS, DHCP, TCP, runtime-state queue churn, tool-service codec parsing, filesystem persistence churn, virtual overlay read churn, and synthetic `RTL8139` / `E1000` UDP loopback comparisons
- `src/benchmark_main.zig` now exposes `zig build bench` with deterministic `BENCH:START` / `BENCH:CASE` / `BENCH:END` output
- `scripts/benchmark-smoke-check.ps1` now provides the strict hosted smoke gate for the benchmark lane and is safe to run repeatedly because each invocation uses a unique temp output file
- CI and release preview now run the benchmark smoke lane without regressing the normal hosted/bare-metal matrix

Delivered third adoption slice:

- ZAR-native read-only introspection overlay inspired by ZigOS `procfs` / `sysfs`
- `src/baremetal/virtual_fs.zig` now exposes synthetic `/proc` and `/sys` trees over existing ZAR runtime, storage, display, and network exports
- `src/baremetal/filesystem.zig` now routes `readFileAlloc`, `listDirectoryAlloc`, and `statSummary` through that overlay and rejects writes under `/proc` / `/sys`
- `src/baremetal/tool_exec.zig` and `src/baremetal/tool_service.zig` now expose the overlay through the existing builtin and typed `GET` / `LIST` / `STAT` surface instead of inventing a second management protocol
- host regressions now prove `/proc/runtime/snapshot`, `/proc/runtime/sessions/<id>`, `/sys/storage/state`, root overlay listing, and read-only path rejection
- `scripts/baremetal-qemu-e1000-tool-service-probe-check.ps1` now proves the same overlay live over the clean-room `E1000` tool-service path, including `/`, `/proc/runtime/snapshot`, `/sys/storage/state`, and virtual `STAT` readback

Delivered fourth adoption slice:

- ZAR-native read-only device overlay inspired by ZigOS `devfs`
- `src/baremetal/virtual_fs.zig` now exposes synthetic `/dev` entries for storage, display, network, and a bounded `/dev/null` sink on top of existing ZAR state
- `src/baremetal/filesystem.zig` now routes `readFileAlloc`, `listDirectoryAlloc`, and `statSummary` through that `/dev` overlay and rejects writes under `/dev`
- `src/baremetal/tool_exec.zig` and `src/baremetal/tool_service.zig` now expose `/dev` through the same builtin and typed `GET` / `LIST` / `STAT` surface
- host regressions now prove `/dev`, `/dev/storage/state`, `/dev/display/state`, root overlay listing, and read-only path rejection
- `scripts/baremetal-qemu-e1000-tool-service-probe-check.ps1` now proves `/`, `/dev`, `/dev/storage/state`, and virtual `STAT` readback live over the `E1000` tool-service path
- full ZigOS-style VFS, generalized mount semantics, and syscall-visible external filesystems remain future redesign work; this slice closes the bounded `/dev` overlay only

Delivered fifth adoption slice:

- bounded non-persistent `tmpfs` inspired by ZigOS `tmpfs`
- `src/baremetal/tmpfs.zig` now provides a ZAR-owned `/tmp` surface with directory create, file write/read/stat, direct-child listing, single-file delete, subtree delete, and reset-on-reinit semantics
- `src/baremetal/filesystem.zig` now routes `/tmp` through that bounded non-persistent store without changing the persistent storage-backed path for `/runtime`, `/tools`, or `/packages`
- host regressions now prove `/tmp` lifecycle behavior plus reset-driven non-persistence

Delivered sixth adoption slice:

- bounded `virtio-block` storage breadth inspired by ZigOS VirtIO device patterns
- `src/baremetal/virtio_block.zig` now provides a ZAR-owned modern `virtio-block` path with queue bring-up, bounded read/write/flush requests, and mock-backed host validation
- `src/baremetal/pci.zig` now discovers modern `virtio-block` PCI capability regions
- `src/baremetal/storage_backend.zig` now prefers `virtio-block` over RAM-disk when available, while still preferring ATA PIO if both hardware-backed backends are present
- `scripts/baremetal-qemu-virtio-block-probe-check.ps1` now proves live raw mutation, tool-layout readback, and filesystem superblock readback on the `virtio-block` path
- `src/baremetal_main.zig` now also carries a bounded `virtio-block` installer/runtime proof through `src/baremetal/disk_installer.zig`, including canonical loader/kernel/manifest seeding plus bootstrap package execution on the same backend
- `scripts/baremetal-qemu-virtio-block-installer-probe-check.ps1` now proves live QEMU installer/runtime persistence on `virtio-blk-pci`, including on-image loader marker persistence, bootstrap state persistence, tool-layout magic, and filesystem magic
- `src/baremetal/mount_table.zig` plus `src/baremetal/filesystem.zig` now add a bounded persistent mount layer that stores alias targets under `/runtime/mounts/<alias>.txt` and resolves `/mnt/<alias>/...` on top of the active backend without introducing a full VFS import
- `src/baremetal_main.zig` now carries a bounded `virtio-block` mount proof that binds `boot` and `runtime`, reads `/mnt/boot/loader.cfg`, writes `/mnt/runtime/state/mounted-via-alias.txt`, reloads the filesystem, and proves the alias plus payload persist
- `scripts/baremetal-qemu-virtio-block-mount-probe-check.ps1` now proves that same mount-layer behavior live on `virtio-blk-pci`, including persisted registry path markers and reloaded alias payload readback
- `src/baremetal/vfs.zig` now provides a bounded internal VFS router over the persistent filesystem, `tmpfs`, the read-only `virtual_fs` trees, and the `/mnt` root, while `src/baremetal/filesystem.zig` now delegates public path operations through that router instead of open-coded per-call branching
- `src/baremetal_main.zig` now widens the same `virtio-block` mount proof to cover merged root listing, `/proc/version` readback, and `/mnt/cache -> /tmp/cache` volatility across reset without regressing the persisted mount-alias contract
- `src/baremetal/storage_registry.zig` now adds a bounded storage-layer registry over the active persistent backend, `tmpfs`, `virtual_fs`, and persisted mount aliases, plus raw `zarfs` / `ext2` / `fat32` detection on the active backend
- `src/baremetal/virtual_fs.zig` now exposes that registry through `/dev/storage/registry` and `/sys/storage/registry`, while `/sys/storage/state` now also reports `detected_filesystem` plus `supported_filesystem_probes=zarfs,ext2,fat32`
- `src/baremetal_main.zig` now widens the same `virtio-block` mount proof to validate `/sys/storage/state`, `/sys/storage/registry`, persistent `zarfs` classification on `virtio-block`, and `tmpfs` classification for `/mnt/cache -> /tmp/cache`
- `src/baremetal/storage_backend_registry.zig` now exports a bounded backend registry over `ram_disk`, `ata_pio`, and `virtio_block`, including availability, active-selection state, preferred-order, logical-base-LBA, partition metadata, and detected filesystem kind per backend
- `src/baremetal/virtual_fs.zig` now also exposes `/dev/storage/backends`, `/dev/storage/filesystems`, `/sys/storage/backends`, and `/sys/storage/filesystems`, making the mounted-filesystem posture explicit at runtime: `zarfs` mounted+writable, `ext2` mounted read-only, and `fat32` bounded writable at the one-level `8.3` surface
- `src/baremetal_main.zig` now widens the same `virtio-block` mount proof to validate `/sys/storage/backends` plus `/sys/storage/filesystems` on the live `virtio-blk-pci` path
- `src/baremetal/ext2_ro.zig` now provides bounded read-only root listing, file read, and stat over deterministic external images seeded onto the active backend, while `src/baremetal/fat32_ro.zig` extends that same bounded surface with one-level `8.3` file write/overwrite/delete plus bounded directory create/remove
- `src/baremetal/mounted_external_fs.zig` now exposes those external filesystems under `/__storagefs/{active,ext2,fat32}`, while `src/baremetal/vfs.zig` routes mounted aliases like `/mnt/external/...` through that bounded external-filesystem seam and only permits file/directory mutation on the FAT32 lane
- `src/baremetal/storage_backend.zig` plus `src/baremetal_main.zig` now export bounded backend count, availability, and explicit selection so the mounted external-filesystem seam can retarget the active backend before rebinding the filesystem
- `src/baremetal_main.zig` now also exports bounded storage-backend info plus mount bind/remove controls through `oc_storage_backend_info`, `oc_filesystem_mount_count`, `oc_filesystem_mount_entry`, `oc_filesystem_bind_mount`, and `oc_filesystem_remove_mount`
- `src/baremetal/tool_exec.zig`, `src/baremetal/tool_service.zig`, and `src/baremetal/tool_service/codec.zig` now expose the same storage and mount controls to users through CLI verbs (`storage-backends`, `storage-filesystems`, `storage-backend-info`, `storage-backend-select`, `storage-partitions`, `storage-partition-select`, `mount-list`, `mount-info`, `mount-bind`, `mount-remove`) and typed framed verbs (`STORAGEBACKENDS`, `STORAGEFILESYSTEMS`, `STORAGEBACKENDINFO`, `STORAGEBACKENDSELECT`, `STORAGEPARTITIONS`, `STORAGEPARTITIONSELECT`, `MOUNTLIST`, `MOUNTINFO`, `MOUNTBIND`, `MOUNTREMOVE`)
- `scripts/baremetal-qemu-virtio-block-mount-control-probe-check.ps1` now proves live mount bind/remove export behavior on `virtio-blk-pci`, including persisted alias reload on the same controller path
- `scripts/baremetal-qemu-virtio-block-ext2-mount-probe-check.ps1` and `scripts/baremetal-qemu-virtio-block-fat32-mount-probe-check.ps1` now prove live bounded `ext2` and `fat32` mounting on `virtio-blk-pci`, including signature validation, mounted `/mnt/external` listing/read/stat, read-only write rejection on `ext2`, bounded root plus nested file mutation on `fat32`, and bounded mounted-directory create/remove on the FAT32 lane

Delivered seventh adoption slice:

- bounded `virtio-net` NIC breadth inspired by ZigOS VirtIO device patterns
- `src/baremetal/virtio_net.zig` now provides a ZAR-owned modern `virtio-net` path with modern PCI capability discovery, version-1 feature negotiation, MAC readout, bounded RX/TX queue bring-up, and raw-frame send/receive telemetry
- `src/baremetal/pci.zig` now discovers modern `virtio-net` PCI capability regions
- `src/pal/net.zig` now routes the raw-frame PAL seam through selectable `RTL8139`, `E1000`, and `virtio-net` backends without regressing the existing lanes
- host regressions now prove init, MAC readout, TX, RX, and export-surface stability on the clean-room `virtio-net` path
- host regressions now also prove `ARP`, `IPv4`, `UDP`, `DHCP`, `DNS`, and bounded `TCP` protocol reuse on the clean-room `virtio-net` path
- `scripts/baremetal-qemu-virtio-net-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-arp-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-ipv4-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-udp-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-dhcp-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-dns-probe-check.ps1`, and `scripts/baremetal-qemu-virtio-net-tcp-probe-check.ps1` plus `scripts/qemu-virtio-net-dgram-echo.ps1` now prove live QEMU `virtio-net-pci` PCI bind, MAC readout, TX, RX, ARP request transmission, IPv4 frame encode/decode, UDP datagram encode/decode, DHCP discover encode/decode, DNS query/A-response exchange, bounded TCP handshake/payload/teardown, payload validation, and counter advance over the freestanding PVH artifact
- host regressions in `src/pal/net.zig` plus `src/baremetal_main.zig` now prove bounded framed tool-service reuse and bounded freestanding `HTTP` / `HTTPS` transport reuse over the clean-room `virtio-net` path
- `scripts/baremetal-qemu-virtio-net-tool-service-probe-check.ps1`, `scripts/baremetal-qemu-virtio-net-http-post-probe-check.ps1`, and `scripts/baremetal-qemu-virtio-net-https-post-probe-check.ps1` now prove live QEMU tool-service reuse, `HTTP` POST, and `HTTPS` POST over the same `virtio-net-pci` freestanding path

Delivered eighth adoption slice:

- bounded shell/control helpers inspired by ZigOS shell structure without claiming a GP-OS shell model
- `src/baremetal/tool_exec.zig` now exposes `shell-expand <pattern>` plus `shell-run <command[;command...]>` over the existing builtin runtime surface
- `shell-run` now routes through shared bounded script execution with quote-aware separator splitting, deferred filesystem persistence, and a hard `64`-command limit
- `shell-run` now also supports bounded metacharacter escaping for separators/redirection including escaped `<`, bounded stdin redirection through `<`, bounded stdout redirection through `>` / `>>`, and bounded stderr redirection through `2>` / `2>>` onto the existing filesystem surface without adding pipes or job control
- `shell-expand` now provides bounded wildcard expansion across multiple path segments using `*` and `?`, returning absolute match paths and explicit `NoMatches` failure when nothing resolves
- `src/baremetal/tool_service.zig` plus `src/baremetal/tool_service/codec.zig` now expose typed `SHELLEXPAND` plus `SHELLRUN` over the framed TCP service
- `src/baremetal_main.zig` now widens the live `E1000` tool-service proof to validate shell help output, bounded shell batching, escaped metacharacters, file-fed stdin flows, multi-segment glob expansion, redirected stdout/stderr capture, and persisted filesystem readback on the clean-room NIC lane
- `build.zig` now explicitly wires `scripts/baremetal/pvh_boot.S` plus `scripts/baremetal/pvh_lld.ld` into the bare-metal artifact so the Multiboot2 header remains within the required first `32768` bytes on current Zig `master`
- full userspace shell, job control, pipelines, broader input/output process plumbing, richer quoting/escaping, editor/TTY parity, and syscall-visible shell semantics remain future redesign work

`FS5.5` is not complete until each subsystem has:

1. a real Zig implementation path
2. a PAL-facing surface
3. host regression coverage where possible
4. at least one bare-metal proof path where hardware semantics matter
5. explicit dependency closure recorded below

## Dependency Order

The order is strict because later subsystems depend on earlier operator and storage surfaces.

1. console / framebuffer text
2. keyboard + mouse
3. in-RAM disk persistence
4. disk driver + block I/O usage
5. ethernet driver
6. tcp/ip
7. filesystem-on-block or filesystem-on-RAM-disk usage
8. bare-metal tool execution substrate

## Success Gates

### 1. Console / Framebuffer Text

Required:

- exported bare-metal console state ABI
- real VGA text-mode implementation on `freestanding + x86_64`
- host-backed test fallback for deterministic regression tests
- PAL console surface
- host regression proving clear/write/cell/cursor behavior
- bare-metal proof path reading back console state/cells

### 2. Keyboard / Mouse

Required:

- interrupt-driven input state capture
- exported key/mouse state ABI
- PAL input surface
- explicit key queue / mouse packet semantics
- bare-metal proof path showing IRQ-driven state updates

### 3. In-RAM Disk Persistence

Required:

- stable block-device abstraction
- fixed-capacity RAM disk
- read/write/flush semantics
- persistence across runtime operations inside the same boot session
- PAL storage surface

### 4. Disk Driver / Block I/O

Required:

- real device-facing block path
- request / response / error state
- read and write path
- geometry/capacity exposure
- at least one bare-metal proof of block mutation and readback

### 5. Ethernet Driver

Required:

- TX/RX ring or equivalent device state
- MAC address exposure
- packet send / receive path
- interrupt or poll-driven receive semantics
- PAL network-device surface

### 6. TCP/IP

Required:

- frame ingress/egress through the ethernet path
- IPv4 framing
- ARP handling
- UDP minimum viable send/receive
- TCP handshake + payload path or an explicitly defined staged gate if UDP is the first strict slice
- bare-metal proof of packet exchange against deterministic harness traffic

### 7. Filesystem Usage

Required:

- filesystem operations backed by RAM disk or disk driver
- directory creation
- file read/write/stat
- integration through PAL FS surface
- proof that tool or runtime state can persist via that path

### 8. Bare-Metal Tool Execution

Required:

- explicit execution model, not a hosted-process stub
- command/task dispatch substrate using bare-metal scheduler, storage, and console/network surfaces
- observable stdout/stderr or console output path
- storage/network dependencies satisfied for any claimed download or file-use scenario

## Current Status

### Console / Framebuffer Text

Status: `Complete`

Current local source-of-truth evidence:

- console ABI added
- VGA text console module added
- PAL console surface added
- host regression proves clear/write/cell/cursor behavior
- live bare-metal PVH/QEMU proof now passes:
  - exported console state has `magic=console_magic`, `api_version=2`, `cols=80`, `rows=25`
  - runtime reports `backend=vga_text`
  - runtime startup banner writes `OK`
  - raw VGA memory at `0xB8000` reads back `O` and `K`
- a real linear-framebuffer path now exists beyond VGA text mode:
  - `src/baremetal/framebuffer_console.zig` programs Bochs/QEMU BGA linear framebuffer modes and renders glyphs into bounded `640x400x32bpp`, `800x600x32bpp`, `1024x768x32bpp`, `1280x720x32bpp`, and `1280x1024x32bpp` surfaces
  - `src/baremetal/pci.zig` discovers the selected PCI display adapter as structured metadata, exposes its framebuffer BAR, and enables decode on that PCI display function
  - `src/pal/framebuffer.zig` exposes the framebuffer path plus the supported-mode table through the PAL surface
  - `src/baremetal_main.zig` exports framebuffer state/pixel access, bounded mode switching, and supported-mode table queries through the bare-metal ABI
- a real EDID-backed display capability path now exists beyond the rendered BGA console:
  - `src/baremetal/edid.zig` provides bounded EDID header/checksum/timing/name parsing
  - `src/baremetal/edid.zig` now also exports the digital-interface subtype for the parsed sink (`undefined`, `DVI`, `HDMI-A`, `HDMI-B`, `MDDI`, or `DisplayPort`)
  - EDID parsing now also exports capability flags for digital input, preferred timing, CEA extension presence, DisplayID extension presence, HDMI vendor data, and basic audio when those descriptors are present
  - `src/baremetal/display_output.zig` provides the exported display-output ABI surface plus EDID byte export, explicit interface-type export, explicit declared-interface export, bounded manufacturer/display-name export, EDID manufacture-week/year and version/revision export, extension-count export, a bounded per-output entry table, a bounded per-output mode inventory derived from the parsed EDID timings, and explicit capability-response formatting on the active/output surface
  - `src/baremetal/virtio_gpu.zig` probes the first real controller-specific path, `virtio-gpu-pci`, through modern virtio PCI capabilities plus `GET_DISPLAY_INFO`, `GET_EDID`, bounded multi-scanout enumeration, connector-aware scanout selection, bounded 2D resource creation, guest-backing attach, transfer-to-host, and flush
  - the same path now also supports explicit connector-targeted reactivation through the runtime surface, so the selected connector is no longer only inferred/exported but can be actively reselected on the real virtio-gpu path
  - the same path now also supports explicit interface-targeted activation and interface-preferred restore, so the live sink can be reselected by its EDID-derived interface type instead of only by connector class or output index
  - the same path now also supports explicit connector-preferred and output-preferred reactivation, so the connected output can be restored to the EDID-preferred geometry after an intermediate shrink instead of only staying at the last requested reduced mode
  - the same path now also supports explicit per-output mode retargeting plus explicit mode-index activation against the advertised mode inventory, so the connected output can be driven to a bounded requested mode through the runtime surface, oversized requests are rejected on the real controller path, and the preferred-mode restore path is proven on the same controller
  - the same path now also supports interface-scoped mode inventory plus interface-targeted mode set and mode-index activation against that same advertised EDID-derived inventory, so the live HDMI/DisplayPort-class sink can be retargeted through its exported interface view instead of only by output index
  - EDID CEA parsing now also exports underscan, YCbCr 4:4:4, and YCbCr 4:2:2 capability bits when present in the sink payload instead of collapsing those flags into a generic CEA-only result
  - `src/pal/framebuffer.zig` now also exposes the display-output state and EDID byte surface through the PAL seam
- host regressions now prove the framebuffer export surface updates host-backed framebuffer state, glyph pixels, supported-mode enumeration, high-resolution mode switching, per-output entry export, per-output mode inventory export, explicit mode-index activation, preferred-mode restore after an intermediate shrink, and preservation of the last valid mode on unsupported requests
- a live bare-metal PVH/QEMU proof now passes:
  - `scripts/baremetal-qemu-framebuffer-console-probe-check.ps1`
  - exported framebuffer state has `magic=framebuffer_magic`, `api_version=2`, and now proves `640x400` (`cols=80`, `rows=25`), `1024x768` (`cols=128`, `rows=48`), and `1280x720` (`cols=160`, `rows=45`) surfaces over the same BGA path
  - `scripts/baremetal-qemu-virtio-gpu-display-probe-check.ps1`
  - live `virtio-gpu-pci` proof now reads back the advertised mode inventory for the connected output, proves mode `0` matches the EDID-preferred `1280x800` geometry, proves an alternate advertised mode exists, drives the connected output down to `1024x768`, saves a connector-aware profile, reapplies that saved reduced profile, and then proves explicit connector-preferred plus output-preferred activation restores the same scanout to the EDID-preferred `1280x800`
  - runtime reports `backend=linear_framebuffer`
  - runtime now also reports the selected display adapter vendor/device and PCI location plus the supported-mode count/current mode index through the exported framebuffer state
  - the startup banner writes `OK`
  - actual MMIO framebuffer pixels read back `bg`, `O`, and `K` from the hardware-backed framebuffer BAR
- a second live bare-metal PVH/QEMU proof now passes:
  - `scripts/baremetal-qemu-virtio-gpu-display-probe-check.ps1`
  - exported display-output state has `magic=display_output_magic`, `api_version=2`, `backend=virtio_gpu`, `controller=virtio_gpu`, an EDID-derived connector type, an exported EDID-derived interface type, and a real EDID header over `virtio-gpu-pci,edid=on`
  - runtime now also reports the selected virtio-gpu PCI vendor/device, PCI location, active scanout, current mode, preferred mode, physical dimensions, manufacturer/product IDs, exported EDID byte surface, the exported capability flags derived from the EDID payload, the exported active/output interface typing, the bounded per-output entry export for the selected scanout, and the bounded advertised mode inventory for that output including per-mode refresh values
  - the live proof now selects the first connected scanout on the real controller path before proving connector-aware reactivation, so the probe no longer assumes the connected output must classify as `virtual`
  - the same proof now also validates that explicit activation of the connected connector succeeds, that an explicit mismatched connector request is rejected on the live controller path, that explicit activation of the exported live interface succeeds, and that an explicit mismatched interface request is rejected on the same controller path
  - the same proof now also validates that explicit `display-output-set` retargets the connected output to `1024x768`, explicit `display-output-activate-mode` succeeds against an advertised alternate mode, and an oversized requested mode is rejected without corrupting the exported output state
  - the same proof now also validates that the connected HDMI/DisplayPort-class sink reports the same bounded mode inventory through the interface view, that explicit `display-interface-set` retargets the live sink by interface to `1024x768`, and that explicit `display-interface-activate-mode` succeeds against the alternate advertised interface mode without corrupting the exported sink identity
  - the same proof now also validates richer exported sink metadata invariants for the connected output, including manufacturer-name width, non-zero EDID version/revision, sane manufacture year, bounded display-name export, and non-zero extension count whenever exported CEA/DisplayID capability bits are set
  - the same proof now also validates exact `display-output-capabilities` and `display-interface-capabilities` response payloads for the connected sink, including the current live HDMI-class flag set on the `virtio-gpu-pci` controller path
  - the same proof now also validates persisted display-profile save/list/info/apply/delete, including mutating the active output down to `800x600`, reapplying the saved profile, and restoring the live output to `1024x768`
- a real display-capability query layer now exists on top of the connector-aware display path:
  - `src/baremetal/tool_exec.zig` now exposes `display-output-capabilities` and `display-interface-capabilities`
  - `src/baremetal/tool_service.zig` plus `src/baremetal/tool_service/codec.zig` now expose typed `DISPLAYOUTPUTCAPABILITIES` and `DISPLAYINTERFACECAPABILITIES`
  - host/module validation proves the same capability payload surface for both output-index and interface-index queries, including explicit `NotFound` behavior on a missing interface
  - the live `virtio-gpu-pci` proof now validates the exact framed capability responses for the connected sink on the real controller path
  - the same proof now also validates that explicit interface-preferred activation and explicit output-preferred activation each restore the connected output from `1024x768` back to the EDID-preferred `1280x800`
  - the same proof now also validates non-zero present statistics plus non-zero scanout pixels from the guest-backed render pattern after resource-create/attach/set-scanout/flush
- a real persisted display-profile layer now exists on top of the connector-aware display path:
  - `src/baremetal/display_profile_store.zig` persists connector-aware display profiles under `/runtime/display-profiles/profiles/<name>.txt` plus `/runtime/display-profiles/active.txt`
  - `src/baremetal/tool_exec.zig` now exposes `display-profile-list`, `display-profile-info`, `display-profile-active`, `display-profile-save`, `display-profile-apply`, and `display-profile-delete`
  - `src/baremetal/tool_service.zig` plus `src/baremetal/tool_service/codec.zig` now expose typed `DISPLAYPROFILELIST`, `DISPLAYPROFILEINFO`, `DISPLAYPROFILEACTIVE`, `DISPLAYPROFILESAVE`, `DISPLAYPROFILEAPPLY`, and `DISPLAYPROFILEDELETE`
  - host/module validation proves save -> list -> info -> mutate -> apply -> active -> delete on both RAM-disk and ATA-backed storage
  - `src/baremetal/display_output.zig` now restores a previously reduced mode up to the preferred output bounds, so the non-hardware virtio-gpu host model matches the real controller path when a saved profile reapplies a larger valid mode
- current real source-of-truth rendered display support now covers bounded Bochs/QEMU BGA mode-setting plus virtio-gpu present/flush over the virtual scanout path
- real HDMI/DisplayPort connector-specific scanout paths are not yet implemented and are not claimed by this branch; the current slice closes deeper HDMI/DisplayPort-class sink capability export on the real `virtio-gpu-pci` controller path instead

### Keyboard / Mouse

Status: `Complete`

Current local source-of-truth evidence:

- real PS/2-style keyboard and mouse state machine shipped in `src/baremetal/ps2_input.zig`
- real x86 port-I/O backed PS/2 controller path shipped in `src/baremetal/ps2_input.zig`:
  - controller data/status/command ports `0x60` / `0x64`
  - controller config read/write
  - controller keyboard + mouse enable flow
  - output-buffer drain and mouse-byte packet assembly
- interrupt-driven capture is wired through the existing x86 interrupt history path:
  - keyboard IRQ vector `33`
  - mouse IRQ vector `44`
- exported bare-metal keyboard/mouse ABI state now exists in `src/baremetal/abi.zig`
- PAL input surface shipped in `src/pal/input.zig`
- bare-metal export surface shipped in `src/baremetal_main.zig`
- host regressions prove:
  - keyboard modifier and scancode queue capture through IRQ delivery
  - mouse packet queue and position accumulator updates through IRQ delivery
- bare-metal proof path now exists:
  - `scripts/baremetal-qemu-ps2-input-probe-check.ps1`
  - wrapper probes for:
    - baseline mailbox/device state
    - keyboard event payloads
    - keyboard modifier + queue state
    - mouse accumulator state
    - mouse packet payloads

### In-RAM Disk Persistence

Status: `Complete`

Current local source-of-truth evidence:

- stable block-device abstraction shipped in `src/baremetal/ram_disk.zig`
- fixed-capacity RAM disk implemented with:
  - `2048` blocks
  - `512` byte block size
  - read/write/flush semantics
  - dirty-state tracking
  - read/write byte and block telemetry
- PAL storage surface shipped in `src/pal/storage.zig`
- bare-metal export surface shipped in `src/baremetal_main.zig`
- tool-slot persistence layer shipped in `src/baremetal/tool_layout.zig`
- host regressions prove:
  - raw block mutation + readback
  - flush clears dirty state
  - tool-slot payload persistence across runtime operations inside the same boot session
  - clear/rewrite behavior on the same RAM-disk-backed layout

### Disk Driver / Block I/O

Status: `Complete`

Current local source-of-truth evidence:

- a shared storage backend facade now exists in `src/baremetal/storage_backend.zig`
- the backend facade now selects between:
  - `src/baremetal/ram_disk.zig`
  - `src/baremetal/ata_pio_disk.zig`
- `src/baremetal/ata_pio_disk.zig` now contains a real x86 ATA PIO path with:
  - primary ATA port access (`0x1F0..0x1F7`, `0x3F6`)
  - `IDENTIFY DEVICE` bring-up
  - sector-count discovery from identify words `60/61`
  - sector `READ`, `WRITE`, and `CACHE FLUSH`
  - bounded multi-partition discovery/export for both MBR and GPT layouts
  - first usable MBR partition mount from sector `0`, with logical LBA translation above the mounted partition base
  - protective-MBR GPT header parsing plus first usable GPT partition mount with the same logical LBA translation model
  - hosted mock-device support for deterministic regression coverage
- `src/pal/storage.zig` now routes through the backend facade instead of directly through the RAM disk
- `src/pal/storage.zig` now also exports the mounted-view storage seam directly:
  - logical base LBA
  - bounded partition count
  - bounded partition info
  - explicit partition selection
- partition selection now invalidates the mounted tool-layout and filesystem state so the next init/format lands on the newly selected partition instead of stale state
- `src/baremetal/tool_layout.zig` now routes through the backend facade instead of directly through the RAM disk
- `src/baremetal/disk_installer.zig` now seeds a canonical persisted install layout on the active backend:
  - `/boot/loader.cfg`
  - `/system/kernel.txt`
  - `/runtime/install/manifest.txt`
  - bootstrap package under `/packages/bootstrap/...`
- host regressions now prove:
  - the storage facade prefers ATA PIO when a device is present
  - ATA PIO mock-device mount and identify-backed capacity detection
  - multi-partition export plus explicit selection for both MBR and GPT mock layouts
  - PAL/export-surface logical base-LBA, partition count/info, and partition selection on the same mounted ATA view
  - partition selection invalidates stale tool-layout/filesystem state and allows explicit re-format/re-init on the newly selected partition
  - per-partition tool-layout and filesystem persistence survives switching between primary and secondary MBR partitions
  - first-partition MBR mounting with logical base-LBA translation
  - protective-MBR GPT partition discovery with mounted logical base-LBA translation
  - ATA PIO mock-device read/write/flush behavior
- bare-metal exports now report ATA PIO as the active backend when a device is present and expose the same partition-mounted storage seam through:
  - `oc_storage_logical_base_lba`
  - `oc_storage_partition_count`
  - `oc_storage_selected_partition_index`
  - `oc_storage_partition_info`
  - `oc_storage_select_partition`
- the live freestanding/QEMU ATA proof is now strict-closed through:
  - `scripts/baremetal-qemu-ata-storage-probe-check.ps1`
  - a real MBR-partitioned raw image attached to the freestanding PVH artifact
  - raw ATA-backed block mutation + readback at physical-on-disk LBAs behind the mounted logical partition view
  - secondary-partition export/selection plus physical readback behind that mounted logical partition view
  - secondary-partition tool-layout formatting + payload persistence through the rebind-safe exported seam
  - secondary-partition filesystem formatting + persisted superblock through the rebind-safe exported seam
  - tool-layout persistence through the ATA-backed shared storage facade on that partition-mounted view
  - path-based filesystem persistence through the ATA-backed shared storage facade on that partition-mounted view
  - `scripts/baremetal-qemu-ata-gpt-installer-probe-check.ps1`
  - a real protective-MBR GPT raw image attached to the freestanding PVH artifact
  - raw ATA-backed block mutation + readback behind the mounted GPT partition view
  - persisted install-layout seeding through `src/baremetal/disk_installer.zig`
  - bootstrap package execution and readback from the mounted GPT-backed filesystem

Notes:

- the strict FS5.5 gate only requires one real device-facing block path with live bare-metal mutation + readback proof; ATA PIO satisfies that gate now
- AHCI/NVMe remain future depth, not a blocker for current FS5.5 disk closure

### Ethernet Driver

Status: `Complete`

Current local source-of-truth evidence:

- `src/baremetal/rtl8139.zig` now contains a real RTL8139 driver path with:
  - PCI-discovered device bring-up
  - MAC readout
  - RX ring programming
  - TX slot programming
  - deterministic loopback-friendly TX/RX validation
  - explicit datapath and error telemetry
- `src/baremetal/pci.zig` now discovers vendor `0x10EC` / device `0x8139`, extracts the I/O BAR and IRQ line, and enables I/O plus bus-master decode on the selected PCI function
- `src/baremetal/abi.zig` now exports `BaremetalEthernetState`
- `src/baremetal_main.zig` now exports the bare-metal Ethernet surface:
  - `oc_ethernet_state_ptr`
  - `oc_ethernet_init`
  - `oc_ethernet_reset`
  - `oc_ethernet_mac_byte`
  - `oc_ethernet_send_pattern`
  - `oc_ethernet_poll`
  - `oc_ethernet_rx_byte`
  - `oc_ethernet_rx_len`
- `src/pal/net.zig` now exposes the bare-metal raw-frame PAL seam through the same RTL8139 driver path instead of a fake transport
- host regressions now prove mock-device initialization, raw-frame send, receive, ABI export, and PAL bridging
- a second clean-room NIC family now exists for broader FS5.5 depth:
  - `src/baremetal/e1000.zig` now provides a ZAR-owned `82540EM`-class `E1000` path with PCI bind, MMIO + legacy I/O reset, EEPROM MAC readout, bounded TX/RX rings, and raw-frame send/receive telemetry
  - `src/baremetal/pci.zig` now also discovers the `E1000` MMIO + I/O BAR pair and enables I/O, memory, and bus-master decode on the selected PCI function
  - dedicated host regressions prove init, MAC readout, TX, RX, export-surface stability, and bounded `TCP` reuse on the clean-room `E1000` path
  - `scripts/baremetal-qemu-e1000-probe-check.ps1`, `scripts/baremetal-qemu-e1000-arp-probe-check.ps1`, `scripts/baremetal-qemu-e1000-ipv4-probe-check.ps1`, `scripts/baremetal-qemu-e1000-udp-probe-check.ps1`, `scripts/baremetal-qemu-e1000-dhcp-probe-check.ps1`, `scripts/baremetal-qemu-e1000-dns-probe-check.ps1`, `scripts/baremetal-qemu-e1000-tcp-probe-check.ps1`, and `scripts/baremetal-qemu-e1000-tool-service-probe-check.ps1` now prove live QEMU `E1000` raw-frame, `ARP`, `IPv4`, `UDP`, `DHCP`, `DNS`, bounded `TCP`, framed tool-service reuse, and the new `/proc` + `/sys` overlay behavior over the freestanding PVH artifact
  - bounded `HTTP` / `HTTPS` transport reuse is now closed over `E1000`; higher service reuse beyond transport closure remains future depth
- the live freestanding/QEMU proof is now green:
  - `scripts/baremetal-qemu-rtl8139-probe-check.ps1`
  - MAC readout succeeds
  - TX succeeds
  - RX loopback succeeds
  - payload length and byte pattern are validated
  - TX/RX counters advance over the hardware-backed PVH image

### TCP/IP

Status: `Complete`

Notes:

- strict Ethernet L2 closure did **not** imply ARP, IPv4, UDP, DHCP, DNS, or TCP closure; that gap is now closed for the FS5.5 acceptance bar
- the strict networking slices above the raw-frame RTL8139 path are now complete locally:
  - `src/protocol/ethernet.zig` encodes and decodes Ethernet headers
  - `src/protocol/arp.zig` encodes ARP request/reply frames and decodes ARP frames
  - `src/protocol/ipv4.zig` encodes and decodes IPv4 headers and validates header checksums
  - `src/protocol/udp.zig` encodes and decodes UDP datagrams and validates pseudo-header checksums
- `src/protocol/tcp.zig` now also provides a minimal session/state machine for client/server handshake, established payload exchange, bounded four-way teardown, bounded FIN-timeout recovery during teardown, bounded multi-flow session-table management, and bounded cumulative-ACK advancement across multiple in-flight payload chunks
- `src/protocol/tcp.zig` now also provides client-side SYN retransmission/timeout recovery for the initial handshake path, established-payload retransmission/timeout recovery, client/responder FIN retransmission/timeout recovery during teardown, strict remote-window enforcement for bounded sequential payload chunking, zero-window blocking until a pure ACK reopens the remote window, and exact bytes-in-flight accounting for the bounded send path
- `src/pal/net.zig` exposes:
    - `sendArpRequest`
    - `pollArpPacket`
    - `sendIpv4Frame`
    - `pollIpv4PacketStrict`
    - `sendUdpPacket`
    - `pollUdpPacketStrictInto`
    - `sendTcpPacket`
    - `pollTcpPacketStrictInto`
    - `configureIpv4Route`
    - `configureIpv4RouteFromDhcp`
    - `configureDnsServers`
    - `configureDnsServersFromDhcp`
    - `resolveNextHop`
  - `learnArpPacket`
  - `sendUdpPacketRouted`
- `src/pal/net.zig` no longer leaves `post()` as a hosted-only hole on the freestanding path:
  - the freestanding branch now performs a real bounded `http://` POST over the existing RTL8139 + ARP + IPv4 + DNS + TCP stack
  - host regressions now prove hostname resolution through a DNS A response, ARP resolution, TCP connect, HTTP request framing, HTTP response parsing, and allocator-owned response buffering over the mock RTL8139 device
- a freestanding `https://` PAL transport path now exists as real code, not as a hosted fallback:
  - `src/pal/tls_client_light.zig` provides the bounded freestanding TLS client used by the PAL network surface
  - `src/pal/net.zig` now drives real DNS + TCP + TLS + HTTPS request/response exchange on the freestanding path
  - host regressions now prove the TLS client emits a real `ClientHello` through the mock RTL8139 transport seam
- the live freestanding PAL `http://` POST path is now also proven directly:
  - `scripts/baremetal-qemu-rtl8139-http-post-probe-check.ps1`
  - the freestanding DNS path now decodes directly into caller-owned packet storage instead of copying through large stack temporaries
  - the PVH boot stack was increased to `128 KiB` so the real DNS + TCP + HTTP + service path no longer overruns the early page-table scratch area
  - the probe keeps interrupts masked on exit, because re-enabling them after the proof can surface a real hardware IRQ0 on the test path and collapse the guest before `isa-debug-exit`
- the live freestanding PAL `https://` POST transport path is now also proven directly:
  - `scripts/baremetal-qemu-rtl8139-https-post-probe-check.ps1`
  - the probe proves direct-IP transport (`https://10.0.2.2:8443/...`), TCP connect, TLS handshake, HTTPS request write, HTTPS response readback, persistent filesystem-backed trust-store selection plus bounded CA-bundle verification with a fixed probe time, and allocator-owned body buffering against a deterministic self-hosted TLS harness over the live RTL8139 path
  - the trust anchor is now installed under `/runtime/trust/bundles/<name>.der`, selected through `/runtime/trust/active.txt`, loaded through the bare-metal filesystem, and validated through a bounded CA bundle on the freestanding path
  - the proof closes the transport-emission question that the earlier debug slice isolated around `ClientHello` generation and payload/FIN handling
- host regressions prove mock-device ARP, IPv4, UDP, DHCP, DNS, TCP handshake/payload exchange, bounded four-way close, dropped-first-SYN retransmission/timeout recovery, dropped-first-payload retransmission/timeout recovery, dropped-first-FIN retransmission/timeout recovery on both close sides, bounded multi-flow session isolation, bounded cumulative-ACK advancement across multiple in-flight payload chunks, bounded sender congestion-window growth/collapse on the chunked send path, DHCP-driven route configuration, gateway ARP learning, routed off-subnet UDP delivery, and direct-subnet UDP bypass through the RTL8139 path
- `src/baremetal/tool_service.zig` now provides a bounded framed request/response shim on top of the bare-metal tool substrate for the TCP path, with typed `CMD`, `EXEC`, `GET`, `PUT`, `STAT`, `LIST`, `INSTALL`, `MANIFEST`, `PKG`, `PKGLIST`, `PKGINFO`, `PKGRUN`, `PKGAPP`, `PKGDISPLAY`, `PKGPUT`, `PKGLS`, `PKGGET`, `PKGDELETE`, `APPLIST`, `APPINFO`, `APPSTATE`, `APPHISTORY`, `APPSTDOUT`, `APPSTDERR`, `APPTRUST`, `APPCONNECTOR`, `APPRUN`, `APPDELETE`, `DISPLAYINFO`, `DISPLAYMODES`, `DISPLAYSET`, `TRUSTPUT`, `TRUSTLIST`, `TRUSTINFO`, `TRUSTACTIVE`, `TRUSTSELECT`, and `TRUSTDELETE` requests plus bounded batched request parsing/execution on one flow
- live QEMU proofs now pass:
  - `scripts/baremetal-qemu-rtl8139-arp-probe-check.ps1`
  - `scripts/baremetal-qemu-rtl8139-ipv4-probe-check.ps1`
  - `scripts/baremetal-qemu-rtl8139-udp-probe-check.ps1`
  - `scripts/baremetal-qemu-rtl8139-tcp-probe-check.ps1`
  - `scripts/baremetal-qemu-rtl8139-gateway-probe-check.ps1`
- `src/baremetal/package_store.zig` now persists canonical package metadata beyond the entrypoint alone, including manifest fields for `name`, `root`, `entrypoint`, `script_bytes`, `asset_root`, `asset_count`, and `asset_bytes`, and `src/baremetal/tool_exec.zig` now exposes matching `ls`, `package-info`, `package-ls`, `package-cat`, `display-info`, `display-outputs`, `display-output`, `display-output-set`, `display-modes`, and `display-activate` builtins on top of the same bare-metal filesystem/package layout
- `src/baremetal_main.zig` host regressions now also prove TCP zero-window block/reopen behavior, framed multi-request command-service exchange on a single live flow, structured `EXEC` request/response behavior, bounded long-response chunking under the advertised remote window, bounded typed batch request multiplexing on one live flow, typed `PUT`/`GET`/`STAT`/`LIST` service behavior, typed `INSTALL` / `MANIFEST` runtime-layout service behavior, typed `PKGAPP` / `PKGDISPLAY` / `PKGPUT` / `PKGLS` / `PKGGET` / `PKGDELETE` package/app-manifest/package-asset/uninstall behavior, typed `APPLIST` / `APPINFO` / `APPSTATE` / `APPHISTORY` / `APPSTDOUT` / `APPSTDERR` / `APPTRUST` / `APPCONNECTOR` / `APPRUN` / `APPDELETE` app-lifecycle behavior, typed `DISPLAYINFO` / `DISPLAYOUTPUTS` / `DISPLAYOUTPUT` / `DISPLAYMODES` / `DISPLAYSET` / `DISPLAYACTIVATE` display-query/control behavior, typed `TRUSTPUT` / `TRUSTLIST` / `TRUSTINFO` / `TRUSTACTIVE` / `TRUSTSELECT` / `TRUSTDELETE` trust-store behavior, persisted `run-script` execution through the framed TCP service seam, and package/app install/list/info/run/delete behavior on the canonical package layout
- those proofs now cover live ARP request transmission, IPv4 frame encode/decode, UDP datagram encode/decode, TCP `SYN -> SYN-ACK -> ACK` handshake plus payload exchange, dropped-first-SYN recovery, dropped-first-payload recovery, dropped-first-FIN recovery on both close sides, bounded four-way close, bounded two-flow session isolation, zero-window block/reopen, bounded sequential payload chunking, bounded sender congestion-window growth after ACK and timeout collapse back to the initial window, framed TCP command-service exchange, bounded typed batch request multiplexing on one flow with concatenated framed responses, typed TCP `PUT` upload, direct filesystem readback of the uploaded script path, typed `INSTALL` / `MANIFEST` runtime-layout service exchange with `/boot/loader.cfg` readback, typed `PKG` / `PKGLIST` / `PKGINFO` / `PKGRUN` / `PKGAPP` / `PKGDISPLAY` / `PKGDELETE` package-service exchange, typed `APPLIST` / `APPINFO` / `APPSTATE` / `APPHISTORY` / `APPSTDOUT` / `APPSTDERR` / `APPTRUST` / `APPCONNECTOR` / `APPRUN` / `APPDELETE` app-lifecycle exchange with persisted runtime-state readback, persisted history-log readback, persisted stdout/stderr readback, and uninstall cleanup, typed `DISPLAYINFO` / `DISPLAYOUTPUTS` / `DISPLAYOUTPUT` / `DISPLAYOUTPUTSET` / `DISPLAYMODES` / `DISPLAYSET` / `DISPLAYACTIVATE` exchange including explicit connected-connector activation, explicit output-index mode retargeting, and mismatched/oversized request rejection, typed `TRUSTPUT` / `TRUSTLIST` / `TRUSTINFO` / `TRUSTACTIVE` / `TRUSTSELECT` / `TRUSTDELETE` trust-store exchange, selected trust-bundle query/path readback, trust-bundle deletion, post-delete remaining-list readback, canonical package entrypoint readback, package manifest readback, package app-manifest readback, persisted package display-profile readback, package-directory listing, package output readback, live `run-package` display-mode application, explicit `DISPLAYSET` mode change/readback, and TX/RX counter advance over the freestanding PVH image
  - the live package-service extension required a real probe-stack fix: `runRtl8139TcpProbe()` now uses static scratch storage, reducing the project-built bare-metal stack frame from `0x3e78` to `0x3708` bytes before the live QEMU proof would pass with package install/list/run enabled
  - the routed UDP proof now also covers live ARP-reply learning, ARP-cache population, gateway next-hop selection for off-subnet traffic, direct-subnet gateway bypass, and routed UDP delivery with the gateway MAC on the Ethernet frame while preserving the remote IPv4 destination
- A real DHCP framing/decode slice is now also closed locally:
  - `src/protocol/dhcp.zig` provides strict DHCP discover encode/decode
  - `src/pal/net.zig` exposes DHCP send/poll helpers for the hosted/mock path
  - `scripts/baremetal-qemu-rtl8139-dhcp-probe-check.ps1` now proves real RTL8139 TX/RX of a DHCP discover payload over a loopback-safe UDP transport envelope, followed by strict DHCP decode and TX/RX counter advance
- A real DNS framing/decode slice is now also closed locally:
  - `src/protocol/dns.zig` provides strict DNS query and A-response encode/decode
  - `src/pal/net.zig` exposes `sendDnsQuery`, `pollDnsPacket`, and `pollDnsPacketStrictInto`
  - host regressions prove DNS query encode/decode, DNS A-response decode, and strict rejection of non-DNS UDP frames over the mock RTL8139 path
  - `scripts/baremetal-qemu-rtl8139-dns-probe-check.ps1` now proves real RTL8139 TX/RX of a DNS query plus strict decode/validation of a DNS A response over the freestanding PVH artifact
- deeper networking depth remains future work above the FS5.5 closure bar:
  - higher-level service/runtime layers beyond the current bounded typed batch + `EXEC` / `LIST` / `INSTALL` / `MANIFEST` / `PKGAPP` / `PKGDISPLAY` / `PKGPUT` / `PKGLS` / `PKGGET` / `PKGDELETE` / `APPLIST` / `APPINFO` / `APPSTATE` / `APPHISTORY` / `APPSTDOUT` / `APPSTDERR` / `APPTRUST` / `APPCONNECTOR` / `APPRUN` / `APPDELETE` / file/package/trust/display/app metadata seam on the bare-metal TCP path
  - persistent multi-root trust-store lifecycle is now proven through `TRUSTPUT` / `TRUSTLIST` / `TRUSTINFO` / `TRUSTACTIVE` / `TRUSTSELECT` / `TRUSTDELETE` on the live TCP path, and the live `https://` transport now consumes the persisted selected bundle from that same trust store
  - real HDMI/DisplayPort connector-specific scanout depth beyond the current BGA render path and virtio-gpu virtual scanout proof

### Filesystem Usage

Status: `Complete`

Current local source-of-truth evidence:

- `src/baremetal/filesystem.zig` now implements a real path-based bare-metal filesystem layer on top of the shared storage backend
- the filesystem entry budget is now `80`, which is the current bounded baseline that keeps the deeper FS5.5 package/trust/app/autorun/workspace runtime state fitting on the persisted filesystem surface without live-service `NoSpace` failures
- directory creation is implemented through `createDirPath`
- file write/read/stat are implemented through `writeFile`, `readFileAlloc`, and `statNoFollow`
- `src/pal/fs.zig` now routes the freestanding PAL surface through that filesystem layer instead of requiring hosted filesystem calls
- `src/baremetal_main.zig` now exports filesystem state and entry metadata through the bare-metal ABI surface
- host regressions and module tests prove path-based persistence on:
  - the RAM-disk backend
  - the ATA PIO backend
- runtime-style state payloads now persist and reload through that path:
  - `/runtime/state/agent.json`
  - `/tools/cache/tool.txt`
  - `/tools/scripts/bootstrap.oc`
  - `/tools/script/output.txt`

### Bare-Metal Tool Execution

Status: `Complete`

Current local source-of-truth evidence:

- `src/baremetal/tool_exec.zig` now provides the real freestanding builtin command substrate used by the bare-metal PAL, including persisted `run-script` execution, canonical `run-package` execution, `package-app`, `package-display`, and `display-set` on the bare-metal filesystem.
- `src/baremetal/package_store.zig` now provides the canonical persisted package layout used by the bare-metal execution and TCP service seams:
  - `/packages/<name>/bin/main.oc`
  - `/packages/<name>/meta/package.txt`
  - `/packages/<name>/meta/app.txt`
  - `/packages/<name>/assets/...`
  - manifest `script_checksum`, `app_manifest_checksum`, and `asset_tree_checksum` fields that can be recomputed against the current persisted package tree
- `src/pal/proc.zig` now exposes an explicit `runCaptureFreestanding(...)` path instead of pretending the hosted child-process path is valid on `freestanding`.
- `src/baremetal/tool_service.zig` now exposes a bounded typed framed request/response shim on top of `tool_exec.runCapture(...)`, `package_store`, and the bare-metal filesystem for the TCP path.
- the execution path now closes its dependency chain through real FS5.5 storage/filesystem layers:
  - `src/baremetal/filesystem.zig`
  - `src/pal/fs.zig`
  - `src/baremetal/storage_backend.zig`
  - attached ATA-backed media in the live probe
- the tool-exec proof is wired directly into `src/baremetal_main.zig` as a dedicated freestanding validation path.
- `scripts/baremetal-qemu-tool-exec-probe-check.ps1` now proves end-to-end bare-metal command execution over the freestanding PVH image with an attached disk by validating:
  - `help`
  - `mkdir /tools/tmp`
  - `write-file /tools/tmp/tool.txt baremetal-tool`
  - `cat /tools/tmp/tool.txt`
  - `stat /tools/tmp/tool.txt`
  - `run-script /tools/scripts/bootstrap.oc`
  - direct filesystem readback of `baremetal-tool`
  - direct filesystem readback of `script-data` after filesystem reset/re-init
  - `echo tool-exec-ok`
- host/module validation now also proves the same path through:
  - `zig test src/baremetal/tool_exec.zig`
  - `zig test src/baremetal/tool_service.zig`
  - `zig test src/baremetal/package_store.zig`
  - the hosted regression in `src/baremetal_main.zig`
- those host/module proofs now also cover:
  - persisted ATA-backed package layout roundtrips
  - typed TCP `PKG` / `PKGLIST` / `PKGINFO` / `PKGRUN` / `PKGAPP` / `PKGDISPLAY` / `PKGPUT` / `PKGLS` / `PKGGET` / `PKGVERIFY` / `PKGRELEASELIST` / `PKGRELEASEINFO` / `PKGRELEASESAVE` / `PKGRELEASEACTIVATE` / `PKGRELEASEDELETE` / `PKGRELEASEPRUNE` / `PKGCHANNELLIST` / `PKGCHANNELINFO` / `PKGCHANNELSET` / `PKGCHANNELACTIVATE` / `PKGDELETE` service behavior
  - canonical `run-package <name>` execution against `/packages/<name>/bin/main.oc`
  - package manifest readback, package app-manifest readback, manifest checksum fields, package asset install/list/get, persisted package display profiles, direct-child directory listing, and persisted release snapshots under `/packages/<name>/releases/<release>/...` on the canonical `/packages/<name>/...` layout
  - `package-verify <name>` plus typed `PKGVERIFY <name>` success receipts against the persisted package tree
  - deterministic mismatch detection after script tampering, currently proven by hosted/module tests through `field=script_checksum`
  - `display-info` / `display-modes` / `display-set` builtin output and typed `DISPLAYINFO` / `DISPLAYMODES` / `DISPLAYSET` service behavior
  - the current FS5.5 autorun slice now adds persisted `/runtime/apps/autorun.txt` state through `src/baremetal/app_runtime.zig`, new `tool_exec` builtins (`app-autorun-list`, `app-autorun-add`, `app-autorun-remove`, `app-autorun-run`), new typed TCP verbs (`APPAUTORUNLIST`, `APPAUTORUNADD`, `APPAUTORUNREMOVE`, `APPAUTORUNRUN`), ATA/RAM-backed autorun registry tests, and live RTL8139 TCP proof for add/list/run/remove plus `/runtime/apps/autorun.txt`, `/runtime/apps/aux/last_run.txt`, and `/runtime/apps/aux/stdout.log` readback
  - the current FS5.5 package-release slice now adds `package-release-list` / `package-release-info` / `package-release-save` / `package-release-activate` / `package-release-delete` / `package-release-prune`, typed `PKGRELEASELIST` / `PKGRELEASEINFO` / `PKGRELEASESAVE` / `PKGRELEASEACTIVATE` / `PKGRELEASEDELETE` / `PKGRELEASEPRUNE`, ATA/RAM-backed release info/delete/prune tests with deterministic `saved_seq` / `saved_tick` metadata, and live RTL8139 TCP proof for save -> mutate -> info -> list -> activate -> delete -> prune plus restored canonical script and asset readback with newest-release retention
  - the current FS5.5 package-release-channel slice now adds persisted `/packages/<name>/channels/<channel>.txt` mappings, `package-release-channel-list` / `package-release-channel-info` / `package-release-channel-set` / `package-release-channel-activate`, typed `PKGCHANNELLIST` / `PKGCHANNELINFO` / `PKGCHANNELSET` / `PKGCHANNELACTIVATE`, ATA/RAM-backed release-channel persistence tests, and live RTL8139 TCP proof for set -> info -> list -> mutate -> activate plus restored canonical script and asset readback through the selected release channel
  - the current FS5.5 app-plan slice now adds persisted `/runtime/apps/<name>/plans/<plan>.txt` plus `/runtime/apps/<name>/active_plan.txt`, new `tool_exec` builtins (`app-plan-list`, `app-plan-info`, `app-plan-active`, `app-plan-save`, `app-plan-apply`, `app-plan-delete`), new typed TCP verbs (`APPPLANLIST`, `APPPLANINFO`, `APPPLANACTIVE`, `APPPLANSAVE`, `APPPLANAPPLY`, `APPPLANDELETE`), ATA/RAM-backed app-plan tests, and a live RTL8139 TCP proof for save/list/info/apply/delete plus restored release/trust/display/autorun state readback
  - the current FS5.5 app-suite slice now adds persisted `/runtime/app-suites/<suite>.txt`, new `tool_exec` builtins (`app-suite-list`, `app-suite-info`, `app-suite-save`, `app-suite-apply`, `app-suite-run`, `app-suite-delete`), new typed TCP verbs (`APPSUITELIST`, `APPSUITEINFO`, `APPSUITESAVE`, `APPSUITEAPPLY`, `APPSUITERUN`, `APPSUITEDELETE`), ATA/RAM-backed app-suite tests, and a live RTL8139 TCP proof for save/list/info/apply/run/delete plus restored active-plan, autorun, and stdout readback across multiple apps
  - the current FS5.5 app-suite-release slice now adds persisted `/runtime/app-suite-releases/<suite>/<release>/suite.txt` plus `release.txt`, new `tool_exec` builtins (`app-suite-release-list`, `app-suite-release-info`, `app-suite-release-save`, `app-suite-release-activate`, `app-suite-release-delete`, `app-suite-release-prune`), new typed TCP verbs (`APPSUITERELEASELIST`, `APPSUITERELEASEINFO`, `APPSUITERELEASESAVE`, `APPSUITERELEASEACTIVATE`, `APPSUITERELEASEDELETE`, `APPSUITERELEASEPRUNE`), ATA/RAM-backed app-suite-release tests with deterministic `saved_seq` / `saved_tick` metadata, and a live RTL8139 TCP proof for save -> mutate -> list -> info -> activate -> delete -> prune plus restored suite readback
  - the current FS5.5 app-suite-release-channel slice now adds persisted `/runtime/app-suite-release-channels/<suite>/<channel>.txt` mappings, `app-suite-release-channel-list` / `app-suite-release-channel-info` / `app-suite-release-channel-set` / `app-suite-release-channel-activate`, typed `APPSUITECHANNELLIST` / `APPSUITECHANNELINFO` / `APPSUITECHANNELSET` / `APPSUITECHANNELACTIVATE`, ATA/RAM-backed app-suite-release-channel persistence tests, and live RTL8139 TCP proof for set -> persisted channel-target readback -> list -> info -> activate plus restored suite readback through the selected suite release channel
  - the current FS5.5 workspace slice now adds persisted `/runtime/workspaces/<name>.txt` plus `/runtime/workspace-runs/<name>/last_run.txt`, `history.log`, `stdout.log`, `stderr.log`, `/runtime/workspace-runs/autorun.txt`, and versioned release snapshots under `/runtime/workspace-releases/<name>/<release>/workspace.txt` plus `release.txt`, new `tool_exec` builtins (`workspace-list`, `workspace-info`, `workspace-save`, `workspace-apply`, `workspace-run`, `workspace-state`, `workspace-history`, `workspace-stdout`, `workspace-stderr`, `workspace-delete`, `workspace-release-list`, `workspace-release-info`, `workspace-release-save`, `workspace-release-activate`, `workspace-release-delete`, `workspace-release-prune`, `workspace-autorun-list`, `workspace-autorun-add`, `workspace-autorun-remove`, `workspace-autorun-run`), new typed TCP verbs (`WORKSPACELIST`, `WORKSPACEINFO`, `WORKSPACESAVE`, `WORKSPACEAPPLY`, `WORKSPACERUN`, `WORKSPACESTATE`, `WORKSPACEHISTORY`, `WORKSPACESTDOUT`, `WORKSPACESTDERR`, `WORKSPACEDELETE`, `WORKSPACERELEASELIST`, `WORKSPACERELEASEINFO`, `WORKSPACERELEASESAVE`, `WORKSPACERELEASEACTIVATE`, `WORKSPACERELEASEDELETE`, `WORKSPACERELEASEPRUNE`, `WORKSPACEAUTORUNLIST`, `WORKSPACEAUTORUNADD`, `WORKSPACEAUTORUNREMOVE`, `WORKSPACEAUTORUNRUN`), RAM-disk and ATA-backed workspace/release/autorun tests, and a live RTL8139 TCP proof for save/list/info/apply/run/state/history/stdout/stderr/delete, workspace release save/mutate/list/info/activate/delete/prune with persisted release readback and restored workspace info, workspace autorun add/list/run/remove, persisted `/runtime/workspace-runs/autorun.txt` readback, persisted workspace-run receipt readback, restored canonical package script content, trust-bundle selection, display mode, app-suite active-plan markers, and delete cleanup
  - the current FS5.5 workspace-plan slice now adds persisted `/runtime/workspace-plans/<name>/<plan>.txt` plus `/runtime/workspace-plans/<name>/active.txt`, new `tool_exec` builtins (`workspace-plan-list`, `workspace-plan-info`, `workspace-plan-active`, `workspace-plan-save`, `workspace-plan-apply`, `workspace-plan-delete`), new typed TCP verbs (`WORKSPACEPLANLIST`, `WORKSPACEPLANINFO`, `WORKSPACEPLANACTIVE`, `WORKSPACEPLANSAVE`, `WORKSPACEPLANAPPLY`, `WORKSPACEPLANDELETE`), RAM-disk and ATA-backed workspace-plan persistence tests, and a live RTL8139 TCP proof for save -> list -> info -> apply -> active -> restore -> delete with restored suite/trust/display/channel readback
  - the current FS5.5 workspace-plan-release slice now adds persisted `/runtime/workspace-plan-releases/<name>/<plan>/<release>/plan.txt` plus `release.txt`, `workspace-plan-release-list` / `workspace-plan-release-info` / `workspace-plan-release-save` / `workspace-plan-release-activate` / `workspace-plan-release-delete` / `workspace-plan-release-prune`, typed `WORKSPACEPLANRELEASELIST` / `WORKSPACEPLANRELEASEINFO` / `WORKSPACEPLANRELEASESAVE` / `WORKSPACEPLANRELEASEACTIVATE` / `WORKSPACEPLANRELEASEDELETE` / `WORKSPACEPLANRELEASEPRUNE`, RAM-disk and ATA-backed workspace-plan-release persistence tests with deterministic `saved_seq` / `saved_tick` metadata, and a live RTL8139 TCP proof for save -> mutate -> list -> info -> activate -> delete -> prune plus persisted plan/metadata readback and restored workspace-plan info
  - the current FS5.5 workspace-release-channel slice now adds persisted `/runtime/workspace-release-channels/<name>/<channel>.txt` mappings, `workspace-release-channel-list` / `workspace-release-channel-info` / `workspace-release-channel-set` / `workspace-release-channel-activate`, typed `WORKSPACECHANNELLIST` / `WORKSPACECHANNELINFO` / `WORKSPACECHANNELSET` / `WORKSPACECHANNELACTIVATE`, RAM-disk and ATA-backed workspace-channel persistence tests, and live RTL8139 TCP proof for set -> info -> list -> activate plus persisted channel-target readback and restored workspace info through the selected workspace release channel
  - the current FS5.5 workspace-suite slice now adds persisted `/runtime/workspace-suites/<suite>.txt` orchestration groups, `workspace-suite-list` / `workspace-suite-info` / `workspace-suite-save` / `workspace-suite-apply` / `workspace-suite-run` / `workspace-suite-delete`, typed `WORKSPACESUITELIST` / `WORKSPACESUITEINFO` / `WORKSPACESUITESAVE` / `WORKSPACESUITEAPPLY` / `WORKSPACESUITERUN` / `WORKSPACESUITEDELETE`, RAM-disk and ATA-backed workspace-suite persistence tests, and live RTL8139 TCP proof for save -> persisted suite-file readback -> list -> info -> apply -> run -> delete plus post-delete suite absence on the higher-level workspace orchestration surface
  - the current FS5.5 workspace-suite-release slice now adds persisted `/runtime/workspace-suite-releases/<suite>/<release>/suite.txt` plus `release.txt`, `workspace-suite-release-list` / `workspace-suite-release-info` / `workspace-suite-release-save` / `workspace-suite-release-activate` / `workspace-suite-release-delete` / `workspace-suite-release-prune`, typed `WORKSPACESUITERELEASELIST` / `WORKSPACESUITERELEASEINFO` / `WORKSPACESUITERELEASESAVE` / `WORKSPACESUITERELEASEACTIVATE` / `WORKSPACESUITERELEASEDELETE` / `WORKSPACESUITERELEASEPRUNE`, RAM-disk and ATA-backed workspace-suite-release persistence tests with deterministic `saved_seq` / `saved_tick` metadata, and live RTL8139 TCP proof for save -> mutate -> list -> info -> activate -> delete -> prune plus restored suite readback and post-delete suite-release absence
  - the current FS5.5 workspace-suite-release-channel slice now adds persisted `/runtime/workspace-suite-release-channels/<suite>/<channel>.txt` mappings, `workspace-suite-release-channel-list` / `workspace-suite-release-channel-info` / `workspace-suite-release-channel-set` / `workspace-suite-release-channel-activate`, typed `WORKSPACESUITECHANNELLIST` / `WORKSPACESUITECHANNELINFO` / `WORKSPACESUITECHANNELSET` / `WORKSPACESUITECHANNELACTIVATE`, RAM-disk and ATA-backed workspace-suite-release-channel persistence tests, and live RTL8139 TCP proof for set -> persisted channel-target readback -> list -> info -> activate plus restored suite readback through the selected workspace-suite release channel
  - `src/baremetal/filesystem.zig` now carries a `128`-entry filesystem budget so the deeper FS5.5 package/trust/app/workspace/workspace-plan/workspace-suite release surface fits on the persisted path without live-service `NoSpace` failures
  - the current FS5.5 runtime-service slice now adds `src/baremetal/runtime_bridge.zig` as the shared bare-metal runtime seam, new `tool_exec` builtins (`runtime-snapshot`, `runtime-sessions`, `runtime-session`), new typed TCP verbs (`RUNTIMECALL`, `RUNTIMESNAPSHOT`, `RUNTIMESESSIONS`, `RUNTIMESESSION`), lifetime-safe `runtime.session.get` handling in `src/runtime/tool_runtime.zig`, logical `/runtime/...` PAL filesystem routing through `src/pal/fs.zig` during hosted bare-metal tests so runtime persistence lands on the same RAM-disk/ATA-backed surface as the rest of FS5.5, hosted/module validation for runtime snapshot/session query and RPC call bridging, and a dedicated live RTL8139 runtime-service proof (`scripts/baremetal-qemu-rtl8139-runtime-service-probe-check.ps1`) for runtime file-write/exec/read plus persisted `/runtime/state/runtime-state.json` and `/runtime/tmp/service-runtime.txt` readback
  - the current local Windows master-Zig stabilization slice now uses the wider `262144`-byte PVH boot/runtime stack in `scripts/baremetal/pvh_boot.S`; hosted master-Zig validation is green (`zig build test --summary all` -> `398/398` passed), and the broad live RTL8139 TCP QEMU proof now passes on both the local `Debug` and stable `ReleaseSafe` probe lanes alongside the live HTTPS proof

## Non-Goals For This Track

- hosted-only PAL wrappers do not count as FS5.5 completion
- synthetic wrapper-only proofs do not count as hardware completion by themselves
- CI green alone does not imply hardware completion

## Completion Rule

`FS5.5` is only complete when every subsystem above is implemented and validated end to end with the dependency chain satisfied.

Current local source-of-truth verdict: the current FS5.5 closure bar is satisfied for the subsystems above, and the remaining future-depth gaps are listed explicitly in this document rather than being claimed as complete.


