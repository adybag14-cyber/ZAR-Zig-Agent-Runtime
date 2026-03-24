# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'baremetal-qemu-i386-ethernet-probe-common.ps1') `
    -BuildOption 'baremetal-virtio-net-tcp-probe' `
    -ProbeTag 'virtio-net-tcp-probe' `
    -DeviceModel 'virtio-net-pci,netdev=n0,disable-legacy=on' `
    -ExpectedProbeCode 0x53 `
    -UseDgramEcho `
    -SkipBuild:$SkipBuild `
    -TimeoutSeconds $TimeoutSeconds
