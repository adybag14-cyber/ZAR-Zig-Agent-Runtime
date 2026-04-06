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
    -ScriptStem 'baremetal-qemu-i386-firmware-smp-priority-window-probe-check' `
    -ProbeSlug 'smp-priority-window-probe' `
    -ProbeLabel 'smp priority window probe' `
    -BuildFlag 'baremetal-i386-smp-priority-window-probe' `
    -ProbeCode 0x85 `
    -ReceiptKey 'BAREMETAL_I386_FIRMWARE_SMP_PRIORITY_WINDOW_PROBE' `
    -QemuCodeReceiptKey 'BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_WINDOW_PROBE_CODE' `
    -QemuDebugReceiptKey 'BAREMETAL_I386_QEMU_FIRMWARE_SMP_PRIORITY_WINDOW_PROBE_DEBUG'
exit $LASTEXITCODE
