# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'baremetal-qemu-i386-ethernet-probe-common.ps1') `
    -BuildOption 'baremetal-rtl8139-arp-probe' `
    -ProbeTag 'rtl8139-arp-probe' `
    -DeviceModel 'rtl8139' `
    -ExpectedProbeCode 0x37 `
    -UseUserNet `
    -SkipBuild:$SkipBuild `
    -TimeoutSeconds $TimeoutSeconds
