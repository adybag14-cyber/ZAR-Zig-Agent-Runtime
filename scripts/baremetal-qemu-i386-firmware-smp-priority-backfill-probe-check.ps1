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
    -ScriptStem 'baremetal-qemu-i386-firmware-smp-priority-backfill-probe-check' `
    -ProbeSlug 'smp-priority-backfill-probe' `
    -ProbeLabel 'smp priority backfill probe' `
    -BuildFlag 'baremetal-i386-smp-priority-backfill-probe' `
    -ProbeCode 0x84 `
    -SmpCpuCount 5 `
    -ReceiptKey 'BAREMETAL_I386_FIRMWARE_SMP_PRIORITY_BACKFILL_PROBE' `
    -QemuCodeReceiptKey 'BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_BACKFILL_PROBE_CODE' `
    -QemuDebugReceiptKey 'BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_BACKFILL_PROBE_DEBUG'
exit $LASTEXITCODE
