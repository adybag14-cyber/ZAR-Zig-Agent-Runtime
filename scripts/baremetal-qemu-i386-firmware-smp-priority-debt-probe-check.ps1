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
    -ScriptStem 'baremetal-qemu-i386-firmware-smp-priority-debt-probe-check' `
    -ProbeSlug 'smp-priority-debt-probe' `
    -ProbeLabel 'smp priority debt probe' `
    -BuildFlag 'baremetal-i386-smp-priority-debt-probe' `
    -ProbeCode 0x96 `
    -SmpCpuCount 5 `
    -ReceiptKey 'BAREMETAL_I386_FIRMWARE_SMP_PRIORITY_DEBT_PROBE' `
    -QemuCodeReceiptKey 'BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_DEBT_PROBE_CODE' `
    -QemuDebugReceiptKey 'BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_DEBT_PROBE_DEBUG'
exit $LASTEXITCODE
