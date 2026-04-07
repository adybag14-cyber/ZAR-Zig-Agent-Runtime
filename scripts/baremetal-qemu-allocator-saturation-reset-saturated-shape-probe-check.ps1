# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-saturation-reset-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ALLOCATOR_SATURATION_RESET_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_RESET_SATURATED_SHAPE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_RESET_SATURATED_SHAPE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-saturation-reset-probe-check.ps1' `
    -FailureLabel 'allocator saturation-reset'
$probeText = $probeState.Text
$preResetFreePages = Extract-IntValue -Text $probeText -Name 'PRE_RESET_FREE_PAGES'
$preResetAllocOps = Extract-IntValue -Text $probeText -Name 'PRE_RESET_ALLOC_OPS'
$preResetBytesInUse = Extract-IntValue -Text $probeText -Name 'PRE_RESET_BYTES_IN_USE'
$preResetPeakBytes = Extract-IntValue -Text $probeText -Name 'PRE_RESET_PEAK_BYTES'
if ($null -in @($preResetAllocationCount,$preResetFreePages,$preResetAllocOps,$preResetBytesInUse,$preResetPeakBytes)) { throw 'Missing saturated-shape allocator saturation-reset fields.' }
if ($preResetAllocationCount -ne 64) { throw "Expected PRE_RESET_ALLOCATION_COUNT=64. got $preResetAllocationCount" }
if ($preResetFreePages -ne 192) { throw "Expected PRE_RESET_FREE_PAGES=192. got $preResetFreePages" }
if ($preResetAllocOps -ne 64) { throw "Expected PRE_RESET_ALLOC_OPS=64. got $preResetAllocOps" }
if ($preResetBytesInUse -ne 262144) { throw "Expected PRE_RESET_BYTES_IN_USE=262144. got $preResetBytesInUse" }
if ($preResetPeakBytes -ne 262144) { throw "Expected PRE_RESET_PEAK_BYTES=262144. got $preResetPeakBytes" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_RESET_SATURATED_SHAPE_PROBE=pass'
Write-Output "PRE_RESET_ALLOCATION_COUNT=$preResetAllocationCount"
Write-Output "PRE_RESET_FREE_PAGES=$preResetFreePages"
Write-Output "PRE_RESET_ALLOC_OPS=$preResetAllocOps"
Write-Output "PRE_RESET_BYTES_IN_USE=$preResetBytesInUse"
Write-Output "PRE_RESET_PEAK_BYTES=$preResetPeakBytes"
