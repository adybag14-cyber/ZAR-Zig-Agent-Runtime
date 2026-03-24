# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'baremetal-qemu-i386-ethernet-probe-common.ps1') `
    -BuildOption 'baremetal-virtio-net-udp-probe' `
    -ProbeTag 'virtio-net-udp-probe' `
    -DeviceModel 'virtio-net-pci,netdev=n0,disable-legacy=on' `
    -ExpectedProbeCode 0x52 `
    -UseDgramEcho `
    -SkipBuild:$SkipBuild `
    -TimeoutSeconds $TimeoutSeconds
