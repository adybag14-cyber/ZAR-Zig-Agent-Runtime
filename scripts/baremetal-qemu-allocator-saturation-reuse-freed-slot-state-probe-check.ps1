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
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FREED_SLOT_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FREED_SLOT_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-saturation-reuse-probe-check.ps1' `
    -FailureLabel 'allocator saturation-reuse'
$probeText = $probeState.Text
$postFreeFreePages = Extract-IntValue -Text $probeText -Name 'POST_FREE_FREE_PAGES'
$postFreeFreeOps = Extract-IntValue -Text $probeText -Name 'POST_FREE_FREE_OPS'
$postFreeLastFreePtr = Extract-IntValue -Text $probeText -Name 'POST_FREE_LAST_FREE_PTR'
$postFreeLastFreeSize = Extract-IntValue -Text $probeText -Name 'POST_FREE_LAST_FREE_SIZE'
$postFreeReuseRecordState = Extract-IntValue -Text $probeText -Name 'POST_FREE_REUSE_RECORD_STATE'
$postFreeBitmapReuseSlot = Extract-IntValue -Text $probeText -Name 'POST_FREE_BITMAP_REUSE_SLOT'
if ($null -in @($postFreeAllocationCount,$postFreeFreePages,$postFreeFreeOps,$postFreeLastFreePtr,$postFreeLastFreeSize,$postFreeReuseRecordState,$postFreeBitmapReuseSlot)) { throw 'Missing freed-slot allocator saturation-reuse fields.' }
if ($postFreeAllocationCount -ne 63) { throw "Expected POST_FREE_ALLOCATION_COUNT=63. got $postFreeAllocationCount" }
if ($postFreeFreePages -ne 193) { throw "Expected POST_FREE_FREE_PAGES=193. got $postFreeFreePages" }
if ($postFreeFreeOps -ne 1) { throw "Expected POST_FREE_FREE_OPS=1. got $postFreeFreeOps" }
if ($postFreeLastFreePtr -ne 1069056) { throw "Expected POST_FREE_LAST_FREE_PTR=1069056. got $postFreeLastFreePtr" }
if ($postFreeLastFreeSize -ne 4096) { throw "Expected POST_FREE_LAST_FREE_SIZE=4096. got $postFreeLastFreeSize" }
if ($postFreeReuseRecordState -ne 0) { throw "Expected POST_FREE_REUSE_RECORD_STATE=0. got $postFreeReuseRecordState" }
if ($postFreeBitmapReuseSlot -ne 0) { throw "Expected POST_FREE_BITMAP_REUSE_SLOT=0. got $postFreeBitmapReuseSlot" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FREED_SLOT_STATE_PROBE=pass'
Write-Output "POST_FREE_ALLOCATION_COUNT=$postFreeAllocationCount"
Write-Output "POST_FREE_FREE_PAGES=$postFreeFreePages"
Write-Output "POST_FREE_FREE_OPS=$postFreeFreeOps"
Write-Output "POST_FREE_LAST_FREE_PTR=$postFreeLastFreePtr"
Write-Output "POST_FREE_LAST_FREE_SIZE=$postFreeLastFreeSize"
Write-Output "POST_FREE_REUSE_RECORD_STATE=$postFreeReuseRecordState"
Write-Output "POST_FREE_BITMAP_REUSE_SLOT=$postFreeBitmapReuseSlot"
