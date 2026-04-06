# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'baremetal-qemu-i386-ethernet-probe-common.ps1') `
    -BuildOption 'baremetal-virtio-net-arp-probe' `
    -ProbeTag 'virtio-net-arp-probe' `
    -DeviceModel 'virtio-net-pci,netdev=n0,disable-legacy=on' `
    -ExpectedProbeCode 0x50 `
    -UseDgramEcho `
    -SkipBuild:$SkipBuild `
    -TimeoutSeconds $TimeoutSeconds
