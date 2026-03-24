# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30
)

& (Join-Path $PSScriptRoot 'baremetal-qemu-i386-ethernet-probe-common.ps1') `
    -BuildOption 'baremetal-rtl8139-probe' `
    -ProbeTag 'rtl8139-probe' `
    -DeviceModel 'rtl8139' `
    -ExpectedProbeCode 0x36 `
    -UseUserNet `
    -UseDebugLog `
    -SkipBuild:$SkipBuild `
    -TimeoutSeconds $TimeoutSeconds
