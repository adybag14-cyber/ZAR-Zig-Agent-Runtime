# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-saturation-reuse-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FULL_TABLE_SHAPE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FULL_TABLE_SHAPE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-saturation-reuse-probe-check.ps1' `
    -FailureLabel 'allocator saturation-reuse'
$probeText = $probeState.Text
$preFreeFreePages = Extract-IntValue -Text $probeText -Name 'PRE_FREE_FREE_PAGES'
$preFreeAllocOps = Extract-IntValue -Text $probeText -Name 'PRE_FREE_ALLOC_OPS'
$preFreeBytesInUse = Extract-IntValue -Text $probeText -Name 'PRE_FREE_BYTES_IN_USE'
$preFreePeakBytes = Extract-IntValue -Text $probeText -Name 'PRE_FREE_PEAK_BYTES'
if ($null -in @($preFreeAllocationCount,$preFreeFreePages,$preFreeAllocOps,$preFreeBytesInUse,$preFreePeakBytes)) { throw 'Missing full-table allocator saturation-reuse fields.' }
if ($preFreeAllocationCount -ne 64) { throw "Expected PRE_FREE_ALLOCATION_COUNT=64. got $preFreeAllocationCount" }
if ($preFreeFreePages -ne 192) { throw "Expected PRE_FREE_FREE_PAGES=192. got $preFreeFreePages" }
if ($preFreeAllocOps -ne 64) { throw "Expected PRE_FREE_ALLOC_OPS=64. got $preFreeAllocOps" }
if ($preFreeBytesInUse -ne 262144) { throw "Expected PRE_FREE_BYTES_IN_USE=262144. got $preFreeBytesInUse" }
if ($preFreePeakBytes -ne 262144) { throw "Expected PRE_FREE_PEAK_BYTES=262144. got $preFreePeakBytes" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FULL_TABLE_SHAPE_PROBE=pass'
Write-Output "PRE_FREE_ALLOCATION_COUNT=$preFreeAllocationCount"
Write-Output "PRE_FREE_FREE_PAGES=$preFreeFreePages"
Write-Output "PRE_FREE_ALLOC_OPS=$preFreeAllocOps"
Write-Output "PRE_FREE_BYTES_IN_USE=$preFreeBytesInUse"
Write-Output "PRE_FREE_PEAK_BYTES=$preFreePeakBytes"
