# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 60,
    [int] $MemoryMiB = 128
)

$helper = Join-Path $PSScriptRoot 'baremetal-qemu-i386-firmware-smp-priority-common.ps1'
& $helper `
    -SkipBuild:$SkipBuild `
    -TimeoutSeconds $TimeoutSeconds `
    -MemoryMiB $MemoryMiB `
    -ScriptStem 'baremetal-qemu-i386-firmware-smp-priority-failover-probe-check' `
    -ProbeSlug 'smp-priority-failover-probe' `
    -ProbeLabel 'smp priority failover probe' `
    -BuildFlag 'baremetal-i386-smp-priority-failover-probe' `
    -ProbeCode 0x83 `
    -ReceiptKey 'BAREMETAL_I386_FIRMWARE_SMP_PRIORITY_FAILOVER_PROBE' `
    -QemuCodeReceiptKey 'BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_FAILOVER_PROBE_CODE' `
    -QemuDebugReceiptKey 'BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_FAILOVER_PROBE_DEBUG'
exit $LASTEXITCODE
