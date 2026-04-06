# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'baremetal-qemu-i386-ethernet-probe-common.ps1') `
    -BuildOption 'baremetal-e1000-dhcp-probe' `
    -ProbeTag 'e1000-dhcp-probe' `
    -DeviceModel 'e1000' `
    -ExpectedProbeCode 0x4D `
    -UseUserNet `
    -SkipBuild:$SkipBuild `
    -TimeoutSeconds $TimeoutSeconds
