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
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FRESH_RESTART_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FRESH_RESTART_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-saturation-reuse-probe-check.ps1' `
    -FailureLabel 'allocator saturation-reuse'
$probeText = $probeState.Text
$postReusePageStart = Extract-IntValue -Text $probeText -Name 'POST_REUSE_PAGE_START'
$postReusePageLen = Extract-IntValue -Text $probeText -Name 'POST_REUSE_PAGE_LEN'
$postReuseAllocationCount = Extract-IntValue -Text $probeText -Name 'POST_REUSE_ALLOCATION_COUNT'
$postReuseFreePages = Extract-IntValue -Text $probeText -Name 'POST_REUSE_FREE_PAGES'
$postReuseAllocOps = Extract-IntValue -Text $probeText -Name 'POST_REUSE_ALLOC_OPS'
$postReuseBytesInUse = Extract-IntValue -Text $probeText -Name 'POST_REUSE_BYTES_IN_USE'
$postReusePeakBytes = Extract-IntValue -Text $probeText -Name 'POST_REUSE_PEAK_BYTES'
$postReuseLastAllocPtr = Extract-IntValue -Text $probeText -Name 'POST_REUSE_LAST_ALLOC_PTR'
$postReuseLastAllocSize = Extract-IntValue -Text $probeText -Name 'POST_REUSE_LAST_ALLOC_SIZE'
$postReuseNeighborState = Extract-IntValue -Text $probeText -Name 'POST_REUSE_NEIGHBOR_STATE'
$postReuseBitmap64 = Extract-IntValue -Text $probeText -Name 'POST_REUSE_BITMAP64'
$postReuseBitmap65 = Extract-IntValue -Text $probeText -Name 'POST_REUSE_BITMAP65'
if ($null -in @($postReusePtr,$postReusePageStart,$postReusePageLen,$postReuseAllocationCount,$postReuseFreePages,$postReuseAllocOps,$postReuseBytesInUse,$postReusePeakBytes,$postReuseLastAllocPtr,$postReuseLastAllocSize,$postReuseNeighborState,$postReuseBitmap64,$postReuseBitmap65)) { throw 'Missing fresh-restart allocator saturation-reuse fields.' }
if ($postReusePtr -ne 1310720) { throw "Expected POST_REUSE_PTR=1310720. got $postReusePtr" }
if ($postReusePageStart -ne 64) { throw "Expected POST_REUSE_PAGE_START=64. got $postReusePageStart" }
if ($postReusePageLen -ne 2) { throw "Expected POST_REUSE_PAGE_LEN=2. got $postReusePageLen" }
if ($postReuseAllocationCount -ne 64) { throw "Expected POST_REUSE_ALLOCATION_COUNT=64. got $postReuseAllocationCount" }
if ($postReuseFreePages -ne 191) { throw "Expected POST_REUSE_FREE_PAGES=191. got $postReuseFreePages" }
if ($postReuseAllocOps -ne 65) { throw "Expected POST_REUSE_ALLOC_OPS=65. got $postReuseAllocOps" }
if ($postReuseBytesInUse -ne 266240) { throw "Expected POST_REUSE_BYTES_IN_USE=266240. got $postReuseBytesInUse" }
if ($postReusePeakBytes -ne 266240) { throw "Expected POST_REUSE_PEAK_BYTES=266240. got $postReusePeakBytes" }
if ($postReuseLastAllocPtr -ne 1310720) { throw "Expected POST_REUSE_LAST_ALLOC_PTR=1310720. got $postReuseLastAllocPtr" }
if ($postReuseLastAllocSize -ne 8192) { throw "Expected POST_REUSE_LAST_ALLOC_SIZE=8192. got $postReuseLastAllocSize" }
if ($postReuseNeighborState -ne 1) { throw "Expected POST_REUSE_NEIGHBOR_STATE=1. got $postReuseNeighborState" }
if ($postReuseBitmap64 -ne 1 -or $postReuseBitmap65 -ne 1) { throw "Expected POST_REUSE_BITMAP64/65=1/1. got $postReuseBitmap64/$postReuseBitmap65" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FRESH_RESTART_PROBE=pass'
Write-Output "POST_REUSE_PTR=$postReusePtr"
Write-Output "POST_REUSE_PAGE_START=$postReusePageStart"
Write-Output "POST_REUSE_PAGE_LEN=$postReusePageLen"
Write-Output "POST_REUSE_ALLOCATION_COUNT=$postReuseAllocationCount"
Write-Output "POST_REUSE_FREE_PAGES=$postReuseFreePages"
Write-Output "POST_REUSE_ALLOC_OPS=$postReuseAllocOps"
Write-Output "POST_REUSE_BYTES_IN_USE=$postReuseBytesInUse"
Write-Output "POST_REUSE_PEAK_BYTES=$postReusePeakBytes"
Write-Output "POST_REUSE_LAST_ALLOC_PTR=$postReuseLastAllocPtr"
Write-Output "POST_REUSE_LAST_ALLOC_SIZE=$postReuseLastAllocSize"
Write-Output "POST_REUSE_NEIGHBOR_STATE=$postReuseNeighborState"
Write-Output "POST_REUSE_BITMAP64=$postReuseBitmap64"
Write-Output "POST_REUSE_BITMAP65=$postReuseBitmap65"
