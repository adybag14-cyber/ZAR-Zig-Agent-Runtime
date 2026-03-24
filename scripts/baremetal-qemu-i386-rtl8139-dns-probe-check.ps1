# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'baremetal-qemu-i386-ethernet-probe-common.ps1') `
    -BuildOption 'baremetal-rtl8139-dns-probe' `
    -ProbeTag 'rtl8139-dns-probe' `
    -DeviceModel 'rtl8139' `
    -ExpectedProbeCode 0x3C `
    -UseUserNet `
    -SkipBuild:$SkipBuild `
    -TimeoutSeconds $TimeoutSeconds
