# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\baremetal-qemu-i386-ethernet-probe-common.ps1" `
    -BuildOption 'baremetal-rtl8139-tcp-probe' `
    -ProbeTag 'rtl8139-tcp-probe' `
    -DeviceModel 'rtl8139' `
    -ExpectedProbeCode 0x3A `
    -UseUserNet `
    -TimeoutSeconds $TimeoutSeconds `
    -SkipBuild:$SkipBuild
