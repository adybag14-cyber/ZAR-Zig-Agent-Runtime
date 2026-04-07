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
    -ScriptStem 'baremetal-qemu-i386-firmware-smp-priority-probe-check' `
    -ProbeSlug 'smp-priority-probe' `
    -ProbeLabel 'smp priority probe' `
    -BuildFlag 'baremetal-i386-smp-priority-probe' `
    -ProbeCode 0x74 `
    -SmpCpuCount 3 `
    -ReceiptKey 'BAREMETAL_I386_FIRMWARE_SMP_PRIORITY_PROBE' `
    -QemuCodeReceiptKey 'BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_PROBE_CODE' `
    -QemuDebugReceiptKey 'BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_PROBE_DEBUG'
exit $LASTEXITCODE
