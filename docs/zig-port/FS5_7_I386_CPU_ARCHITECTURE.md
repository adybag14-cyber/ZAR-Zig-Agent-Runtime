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

### Slice 7: i386 RTL8139 Higher Protocols, virtio-net, and virtio-block

- new live i386 QEMU probes:
  - `scripts/baremetal-qemu-i386-rtl8139-dhcp-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-rtl8139-dns-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-rtl8139-http-post-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-rtl8139-https-post-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-net-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-net-arp-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-net-ipv4-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-net-udp-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-net-tcp-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-net-dhcp-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-net-dns-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-net-http-post-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-net-https-post-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-net-tool-service-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-block-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-block-installer-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-block-mount-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-block-ext2-mount-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-block-fat32-mount-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-virtio-block-mount-control-probe-check.ps1`
- `src/baremetal_main.zig` now makes the i386 `RTL8139` `DHCP` and `DNS` probes deterministic through the same bounded internal loopback hook already used by the later `TCP` and runtime-service lanes, removing the i386-only `TxCompletedNoRxInterrupt` failure mode on those higher protocol checks
- `scripts/baremetal-qemu-i386-ethernet-probe-common.ps1` now selects the correct datagram echo helper for `virtio-net`, so the i386 `virtio-net` raw/ARP/IPv4/UDP/TCP lane validates against the right remote MAC instead of the stale `E1000` helper identity
- the i386 RTL8139 lane now also proves on a real guest:
  - `DHCP`
  - `DNS`
  - `HTTP`
  - `HTTPS`
- the i386 virtio-net lane now proves on a real guest:
  - raw frame TX/RX
  - `ARP`
  - `IPv4`
  - `UDP`
  - bounded `TCP`
  - `DHCP`
  - `DNS`
  - `HTTP`
  - `HTTPS`
  - bounded framed tool-service reuse
- the i386 virtio-block lane now proves on a real guest:
  - raw block IO
  - installer/runtime layout persistence
  - bounded mount registry reload
  - bounded read-only `ext2` mount
  - bounded writable `fat32` mount
  - bounded mount-control reload
- hosted CI and `release-preview` now execute those additional i386 probe scripts as part of the optional QEMU lane

### Slice 8: i386 RTL8139 Gateway, Full-Stack Depth, and Display-Matrix Reuse

- new live i386 QEMU probes:
  - `scripts/baremetal-qemu-i386-rtl8139-gateway-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-rtl8139-full-stack-probe-check.ps1`
- `src/baremetal_main.zig` now enables the bounded `RTL8139` hardware-loopback datapath inside `runRtl8139GatewayProbe()` for hardware-backed non-test runs, so the i386 guest can deterministically observe its own ARP-learning and routed-UDP traffic instead of stalling on the first ARP miss
- the i386 RTL8139 lane now also proves on a real guest:
  - ARP-reply learning into the route cache
  - routed off-subnet UDP delivery through the learned gateway next hop
  - direct-subnet gateway bypass
  - broader full-stack `RTL8139` TCP/service depth through the existing persisted package/workspace/app/trust/runtime surface on the i386 artifact
- the existing i386 `virtio-gpu` display lane already reuses `runVirtioGpuDisplayProbe()`, so the i386 controller path now benefits from the same output/interface/mode/profile matrix validation already carried by that broad runtime function instead of only the early inventory subset
- hosted CI and `release-preview` now also execute:
  - `scripts/baremetal-qemu-i386-rtl8139-gateway-probe-check.ps1`
  - `scripts/baremetal-qemu-i386-rtl8139-full-stack-probe-check.ps1`

### Slice 9: i386 E1000 Full-Stack Depth

- new live i386 QEMU probe:
  - `scripts/baremetal-qemu-i386-e1000-full-stack-probe-check.ps1`
- `build.zig` now exports a dedicated `baremetal-e1000-full-stack-probe` option so the broader E1000 service depth is a first-class lane instead of being implied by the older tool-service wrapper name
- `src/baremetal_main.zig` now exposes `runE1000FullStackProbe()` as a dedicated alias over the existing broader `E1000` service/runtime probe surface and carries a distinct success code for that lane
- the i386 E1000 lane now also proves on a real guest:
  - persisted package install/list/run/info/asset/release/channel depth
  - trust install/select/rotate/delete depth
  - app/app-plan/app-suite release and channel depth
  - workspace/workspace-plan/workspace-suite release and channel depth
  - bounded shell, TTY, `/proc`, `/dev`, `/sys`, and storage-overlay readback through the same controller path
- hosted CI and `release-preview` now also execute:
  - `scripts/baremetal-qemu-i386-e1000-full-stack-probe-check.ps1`

### Slice 10: i386 Platform ACPI, Timer, and Interrupt Proof

- new bounded platform parser/export seam:
  - `src/baremetal/acpi.zig`
- new virtual exports:
  - `/sys/acpi`
  - `/sys/acpi/state`
- new bare-metal ABI export:
  - `oc_acpi_state_ptr()`
- new dedicated live i386 QEMU probe:
  - `scripts/baremetal-qemu-i386-platform-probe-check.ps1`
- `src/baremetal_main.zig` now carries a dedicated `i386_platform_probe` lane that validates:
  - descriptor tables are loaded on freestanding `x86`
  - bounded ACPI state/export/render availability
  - interrupt wake delivery on vector `31`
  - masked external interrupt handling on vector `200`
  - timer-backed wake fallback after the masked interrupt path
- current direct `-kernel` QEMU boot still does not expose firmware low-memory ACPI tables in this environment, so the platform lane now:
  - attempts real low-memory ACPI discovery first
  - falls back to a bounded synthetic `XSDT`-backed ACPI image when firmware tables are unavailable or insufficient for the bounded SMP-ready platform proof
  - keeps timer/interrupt behavior as a real live i386 QEMU proof
- hosted CI and `release-preview` now also execute:
  - `scripts/baremetal-qemu-i386-platform-probe-check.ps1`

### Slice 11: i386 CPU Topology and SMP-Readiness Export

- `src/baremetal/acpi.zig` now derives a bounded CPU-topology export from `MADT` local-APIC entries instead of only exposing aggregate ACPI counts
- new bare-metal ABI exports:
  - `oc_cpu_topology_state_ptr()`
  - `oc_cpu_topology_entry_count()`
  - `oc_cpu_topology_entry(index)`
- new virtual exports:
  - `/dev/cpu/state`
  - `/dev/cpu/topology`
  - `/sys/cpu/state`
  - `/sys/cpu/topology`
- the bounded topology state now exports:
  - `cpu_count`
  - `exported_count`
  - `enabled_count`
  - `supports_smp`
  - `ioapic_count`
  - `lapic_addr_override_count`
  - `madt_flags`
  - `local_apic_addr`
- the bounded topology entry export now carries:
  - ACPI processor UID
  - APIC ID
  - enabled flag
  - raw `MADT` flags
- the synthetic ACPI fallback image now includes two enabled local-APIC entries plus one IOAPIC entry, so the direct-loader i386 platform lane proves bounded SMP-readiness rather than single-CPU-only enumeration
- `runI386PlatformProbe()` now validates:
  - exported CPU topology presence
  - at least two enabled CPUs
  - distinct APIC IDs
  - `/sys/cpu/state` and `/sys/cpu/topology` render/readback

### Slice 12: i386 LAPIC State and `-smp 2` Proof

- new bounded LAPIC seam:
  - `src/baremetal/lapic.zig`
- new bare-metal ABI export:
  - `oc_lapic_state_ptr()`
- new virtual exports:
  - `/dev/cpu/lapic`
  - `/dev/cpu/smp`
  - `/sys/cpu/lapic`
  - `/sys/cpu/smp`
- new live i386 QEMU probe:
  - `scripts/baremetal-qemu-i386-smp-probe-check.ps1`
- `src/baremetal_main.zig` now carries a dedicated `i386_smp_probe` lane that validates:
  - ACPI/topology presence with synthetic fallback only when firmware ACPI is unavailable or insufficient for the bounded SMP-ready platform proof
  - local APIC support through CPUID
  - local APIC enablement through `IA32_APIC_BASE`
  - bounded LAPIC MMIO register visibility (`ID`, `VERSION`, `SVR`, timer/error `LVT`)
  - `CPUID` APIC ID matches the current LAPIC ID
  - LAPIC base matches the exported topology `local_apic_addr`
  - `/sys/cpu/lapic` and `/sys/cpu/smp` render/readback
- hosted CI and `release-preview` now also execute:
  - `scripts/baremetal-qemu-i386-smp-probe-check.ps1`

### Slice 13: i386 AP-Startup Control and Execution Telemetry

- new bounded AP-startup seam:
  - `src/baremetal/i386_ap_startup.zig`
- new bootstrap/linker support:
  - `scripts/baremetal/i386_ap_trampoline.S`
  - `scripts/baremetal/i386_lld.ld`
- new bare-metal ABI export:
  - `oc_i386_ap_startup_state_ptr()`
- new virtual exports:
  - `/dev/cpu/ap-startup`
  - `/sys/cpu/ap-startup`
- new dedicated live i386 QEMU probe:
  - `scripts/baremetal-qemu-i386-ap-startup-probe-check.ps1`
- `src/baremetal_main.zig` now carries a dedicated `i386_ap_startup_probe` lane that validates:
  - exported AP-startup state visibility
  - bounded high-page trampoline placement at `0x00080000`
  - BSP-side local-APIC enablement plus explicit INIT / deassert / SIPI / SIPI sequencing
  - exported stage progression through `0x10` .. `0x14`
  - bounded command/response/heartbeat telemetry for AP execution control when an AP actually comes online
  - `/sys/cpu/ap-startup` render/readback
- `src/baremetal/i386_ap_startup.zig` now also owns a bounded ping/halt control protocol with:
  - `command_seq`
  - `response_seq`
  - `heartbeat_count`
  - `ping_count`
- hosted regressions now prove the bounded ping/halt helper path with a simulated AP responder thread
- the current direct `-kernel` QEMU path still does not yield actual AP execution here, so the live lane remains intentionally bounded:
  - it proves the full BSP-side startup-control sequence and exported telemetry
  - it exposes the AP execution-control state shape used for the future real bring-up lane
  - it does not claim that the AP executes the trampoline or reaches halted state on the current direct-loader path yet
- the i386 live probe scripts now build into per-script isolated prefixes and caches so one probe cannot accidentally execute another probe's ELF artifact
- hosted CI and `release-preview` now also execute:
  - `scripts/baremetal-qemu-i386-ap-startup-probe-check.ps1`

### Slice 14: i386 AP-Startup Timing Hardening and Explicit Execution Detection

- `src/baremetal/i386_ap_startup.zig` now hardens the BSP-side startup sequence with:
  - longer INIT-settle delay before the startup IPIs
  - shorter bounded retry gap between the first and second SIPI
  - local-APIC error-status clearing before each SIPI
  - bounded first-SIPI polling before falling through to the second-SIPI retry
- `src/baremetal_main.zig` now treats the AP-startup probe as a two-outcome success lane:
  - `0x7F` means actual AP execution was observed and the bounded ping/halt control path completed live
  - `0x7E` means only the bounded BSP-side control telemetry was observed, with no false AP-execution claim
- `scripts/baremetal-qemu-i386-ap-startup-probe-check.ps1` now accepts both success codes and reports:
  - `BAREMETAL_I386_QEMU_AP_EXECUTION_OBSERVED=True|False`
- current live result on the direct `-kernel` QEMU path remains:
  - `BAREMETAL_I386_QEMU_AP_EXECUTION_OBSERVED=False`
- that means the current direct-loader i386 lane still does not yield actual AP execution even after timing/ESR hardening, but the live probe now states that boundary explicitly instead of hiding it behind a single pass code

### Slice 15: i386 IOAPIC State and Live Platform Proof

- `src/baremetal/acpi.zig` now records bounded `MADT` IOAPIC entries instead of only aggregate counts:
  - `ioapic_id`
  - `mmio_addr`
  - `gsi_base`
- new bounded IOAPIC seam:
  - `src/baremetal/ioapic.zig`
- new ABI export:
  - `oc_ioapic_state_ptr()`
- new virtual paths:
  - `/dev/cpu/ioapic`
  - `/sys/cpu/ioapic`
- `src/baremetal_main.zig` now widens the dedicated i386 platform probe to validate:
  - ACPI-present IOAPIC state
  - live MMIO base visibility
  - bounded redirection-entry count
  - `/sys/cpu/ioapic` render/readback
- `scripts/baremetal-qemu-i386-platform-probe-check.ps1` now inspects the live exported IOAPIC state via GDB and requires:
  - `present=1`
  - `acpi_present=1`
  - `enabled=1`
  - `ioapic_count>=1`
  - non-zero MMIO base
  - non-zero redirection-entry count
- current live result on the direct `-kernel` QEMU path now includes:
  - `BAREMETAL_I386_PLATFORM_PROBE_IOAPIC_PRESENT=1`
  - `BAREMETAL_I386_PLATFORM_PROBE_IOAPIC_COUNT=1`
  - `BAREMETAL_I386_PLATFORM_PROBE_IOAPIC_REDIRECTION_ENTRY_COUNT=24`
  - `BAREMETAL_I386_PLATFORM_PROBE_IOAPIC_MMIO_ADDR=4273995776`
- that closes bounded IOAPIC export plus live MMIO proof on the current i386 platform lane without falsely claiming firmware-backed ACPI or actual AP execution

### Slice 16: i386 Warm-Reset Startup Diagnostics

- `src/baremetal/i386_ap_startup.zig` now programs the legacy warm-reset vector before the BSP-side `INIT / deassert / SIPI / SIPI` sequence, mirroring the missing Linux-era startup mechanic that was not present in the earlier bounded AP-control seam:
  - CMOS shutdown code `0x0A` through ports `0x70/0x71`
  - warm-reset vector offset at physical `0x467`
  - warm-reset vector segment at physical `0x469`
- the exported AP-startup ABI now also carries bounded BSP-side delivery diagnostics:
  - `warm_reset_programmed`
  - `warm_reset_vector_segment`
  - `warm_reset_vector_offset`
  - `init_ipi_count`
  - `startup_ipi_count`
  - `last_delivery_status`
  - `last_accept_status`
- `src/baremetal_main.zig` now requires that those diagnostics are populated on the live AP-startup probe lane instead of treating them as optional render-only metadata
- `scripts/baremetal-qemu-i386-ap-startup-probe-check.ps1` now captures the i386 AP lane’s debug-port trace and preserves it at:
  - `release/qemu-i386-ap-startup-probe-debug.log`
- current live result on the direct `-kernel` QEMU path is now explicit and more informative:
  - `I386_AP_WARM_RESET_PROGRAMMED=1`
  - `I386_AP_INIT_IPI_COUNT=2`
  - `I386_AP_STARTUP_IPI_COUNT=2`
  - `I386_AP_LAST_DELIVERY_STATUS=0x0`
  - `I386_AP_LAST_ACCEPT_STATUS=0x0`
  - `I386_AP_EXECUTION_OBSERVED=0`
- that means the missing warm-reset programming gap is now closed and the BSP-side delivery path is clean, but the current direct-loader path still does not yield actual AP trampoline execution

### Slice 17: i386 Legacy PIC Export and Live Platform Proof

- new bounded legacy PIC seam:
  - `src/baremetal/pic.zig`
- new ABI export:
  - `oc_pic_state_ptr()`
- new virtual paths:
  - `/dev/cpu/pic`
  - `/sys/cpu/pic`
- the PIC seam now performs a real legacy dual-8259 remap on hardware-backed `x86` / `x86_64` freestanding runs:
  - master offset `0x20`
  - slave offset `0x28`
  - preserves the live hardware mask bytes while reprogramming the controller
  - records bounded IRR/ISR visibility for both master and slave PICs
- the exported PIC state also records the distinct software interrupt-mask control plane from `src/baremetal/x86_bootstrap.zig`:
  - `control_mask_profile`
  - `control_masked_count`
  - `control_ignored_count`
  - `last_masked_vector`
- `src/baremetal_main.zig` now widens the dedicated i386 platform probe to require:
  - `present=1`
  - `remapped=1`
  - `master_offset=0x20`
  - `slave_offset=0x28`
  - `/sys/cpu/pic` render/readback
  - preserved hardware PIC masks across a software `interrupt_mask_profile_external_all` apply
  - updated control-plane counters without falsely mutating the hardware PIC mask bytes
- that closes bounded legacy PIC export plus live remap/control-plane separation proof on the current direct-loader i386 platform lane without falsely claiming firmware-backed ACPI or actual AP execution

### Slice 18: i386 PIT and ACPI PM-Timer Controller Proof

- new bounded timer-controller seams:
  - `src/baremetal/pit.zig`
  - `src/baremetal/acpi_pm_timer.zig`
- new ABI exports:
  - `oc_pit_state_ptr()`
  - `oc_pm_timer_state_ptr()`
- new virtual paths:
  - `/dev/cpu/pit`
  - `/sys/cpu/pit`
  - `/sys/acpi/pm-timer`
- `src/baremetal_main.zig` now widens the dedicated i386 platform probe to require:
  - successful bounded PIT channel-0 latch/readback
  - non-zero PIT count delta with `counter_changed=1`
  - ACPI PM-timer visibility through the exported FADT `pm_timer_block`
  - non-zero PM-timer delta with `monotonic=1`
  - `/sys/cpu/pit` and `/sys/acpi/pm-timer` render/readback
- that closes bounded i386 timer-controller export and live controller readback on the current direct-loader path instead of only proving higher-level timer wake behavior above the controllers

### Slice 19: i386 Firmware-Boot ACPI Proof

- new BIOS firmware-boot lane:
  - `scripts/build-i386-firmware-image.ps1`
  - `scripts/baremetal/i386_bios_boot_sector.asm`
  - `scripts/baremetal/i386_bios_stage2.asm`
  - `scripts/baremetal-qemu-i386-firmware-platform-probe-check.ps1`
- new freestanding build option:
  - `baremetal-i386-firmware-platform-probe`
- `src/baremetal_main.zig` now carries a dedicated `i386_firmware_platform_probe` lane that:
  - requires live low-memory ACPI instead of accepting synthetic fallback
  - reuses the platform validation surface only after firmware ACPI is proven real
- `src/baremetal/acpi.zig` now keeps the `RSDP` search bounded to low memory but permits bounded live physical table validation beyond `1 MiB`, so firmware-root `RSDT`/`XSDT` tables can be validated even when BIOS places them high in RAM
- the live BIOS lane now proves:
  - real firmware `RSDP` discovery
  - real firmware root-table validation without synthetic fallback
  - real `FADT` + `MADT` parsing
  - real LAPIC, IOAPIC, SCI, and PM-timer data on the firmware-boot path
- hosted CI and `release-preview` now also execute:
  - `scripts/baremetal-qemu-i386-firmware-platform-probe-check.ps1`
- current live result on the firmware-boot i386 path includes:
  - `ACPI_PRESENT=1`
  - `ACPI_FLAGS=0x0E`
  - `source_live_low_memory=1`
  - `source_synthetic=0`
  - `ACPI_LAPIC_COUNT=2`
  - `ACPI_IOAPIC_COUNT=1`
  - `ACPI_SCI_INTERRUPT=9`
  - `ACPI_PM_TIMER_BLOCK=0x608`
  - `ACPI_RSDP_ADDR=0x000F52A0`
  - `ACPI_RSDT_ADDR=0x07FE1C67`

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
- the i386 freestanding runtime now has live higher-level package/workspace/app/trust/runtime depth on the E1000 controller lane
- the i386 freestanding runtime now has a dedicated live platform proof for descriptor-load state, bounded ACPI export/render, PIT plus ACPI PM-timer controller visibility, interrupt wake delivery, and masked-interrupt timer fallback
- the i386 freestanding runtime now has exported CPU topology and bounded SMP-readiness derived from `MADT`, with `/dev/cpu` and `/sys/cpu` visibility on the i386 platform lane
- the i386 freestanding runtime now has a dedicated live `-smp 2` LAPIC proof with `/dev/cpu/lapic` and `/sys/cpu/{lapic,smp}` visibility on the i386 platform lane
- the i386 freestanding runtime now has a dedicated live AP-startup control diagnostic proof with `/dev/cpu/ap-startup` and `/sys/cpu/ap-startup` visibility, a high-page trampoline, verified BSP-side INIT / deassert / SIPI / SIPI sequencing, bounded command/response/heartbeat telemetry, hardened startup timing/ESR handling, and explicit live AP-execution observation reporting on the current direct-loader QEMU path
- the i386 freestanding runtime now also proves that the warm-reset vector is programmed correctly and that the BSP-side startup IPIs complete without APIC delivery or accept errors on the current direct-loader path, with the live AP debug trace preserved for inspection
- the i386 freestanding runtime now has bounded IOAPIC export plus live MMIO proof with `/dev/cpu/ioapic` and `/sys/cpu/ioapic` visibility on the i386 platform lane
- the i386 freestanding runtime now has bounded legacy PIC export plus live remap/control-plane proof with `/dev/cpu/pic` and `/sys/cpu/pic` visibility on the i386 platform lane
- the i386 freestanding runtime now has bounded PIT export plus live latch/readback proof with `/dev/cpu/pit` and `/sys/cpu/pit` visibility on the i386 platform lane
- the i386 freestanding runtime now has bounded ACPI PM-timer export plus live monotonic readback proof through `/sys/acpi/pm-timer` on the i386 platform lane
- the i386 freestanding runtime now has a real BIOS firmware-boot ACPI proof with no synthetic fallback, using a custom bounded BIOS disk image + stage2 loader and a dedicated firmware platform probe lane
- the i386 freestanding runtime now has live RTL8139 `ARP` / `IPv4` / `UDP` / bounded `TCP` / bounded runtime-service proof
- the i386 freestanding runtime now has live RTL8139 `DHCP` / `DNS` / `HTTP` / `HTTPS` proof
- the i386 freestanding runtime now has live RTL8139 gateway-routing proof
- the i386 freestanding runtime now has live higher-level package/workspace/app/trust/runtime depth on the RTL8139 controller lane
- the i386 freestanding runtime now has live virtio-net raw-frame plus `ARP` / `IPv4` / `UDP` / bounded `TCP` / `DHCP` / `DNS` / `HTTP` / `HTTPS` / bounded tool-service proof
- the i386 freestanding runtime now has live virtio-block raw IO plus installer/runtime, mount, `ext2`, `fat32`, and mount-control proof
- the i386 freestanding runtime now has live linear-framebuffer console proof
- the current explicit boundary is:
  - live i386 timer/interrupt/device/display/storage/NIC proof breadth is broad
  - the direct `-kernel` platform lane still has bounded synthetic ACPI fallback when firmware tables are unavailable or insufficient there
  - a separate BIOS firmware-boot lane now proves real ACPI end to end
  - actual AP bring-up/SMP execution and broader platform-controller hardening remain the next `FS5.7` steps
- the i386 freestanding runtime now has live `virtio-gpu` display proof on the i386 controller path with reused output/interface/mode/profile matrix coverage from the shared broad display probe

## Current Boundary

- this is build/boot smoke plus additive descriptor/bootstrap/runtime parity and broad real i386 storage/NIC/display/service lanes
- it is not yet full 32-bit driver/runtime parity
- descriptor telemetry is now dual-arch, but the broader descriptor/mailbox live proof lane is still only claimed on the existing `x86_64` PVH artifact
- i386 display coverage now includes bounded VGA + framebuffer + `virtio-gpu` with reused output/interface/mode/profile matrix validation on the current controller path, but it still does not claim physical HDMI/DisplayPort controller-specific scanout or a separate i386-only display-profile wrapper matrix
- i386 platform coverage now includes bounded ACPI plus exported CPU topology, IOAPIC state, PIC state, LAPIC state, PIT state, ACPI PM-timer state, SMP-readiness, AP-startup execution telemetry, explicit live AP-execution observation reporting on the current direct-loader path, and a separate real firmware-boot ACPI proof with no synthetic fallback
- the remaining i386 AP/SMP gap is now narrower and explicit:
  - warm-reset programming is present
  - INIT + SIPI delivery completes cleanly
  - AP execution is still not observed on the direct-loader path
  - that points the next real closure step at actual AP execution / SMP bring-up, not missing firmware ACPI or missing BSP-side setup anymore

## Next Steps

1. start the next real i386 architecture-hardening slice after bounded AP-startup control diagnostics:
   - actual AP bring-up and execution on top of the now-live firmware/platform seams
2. then widen bounded SMP groundwork into actual AP bring-up and execution
   - AP trampoline execution
   - LAPIC / IPI bring-up beyond BSP-side sequencing
3. only after that, widen timer / interrupt hardening around the real multi-core path
