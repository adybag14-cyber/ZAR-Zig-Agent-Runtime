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
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_NO_SPACE_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_NO_SPACE_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-saturation-reuse-probe-check.ps1' `
    -FailureLabel 'allocator saturation-reuse'
$probeText = $probeState.Text
$preFreeReuseRecordPtr = Extract-IntValue -Text $probeText -Name 'PRE_FREE_REUSE_RECORD_PTR'
$preFreeReuseRecordPageStart = Extract-IntValue -Text $probeText -Name 'PRE_FREE_REUSE_RECORD_PAGE_START'
$preFreeLastRecordPtr = Extract-IntValue -Text $probeText -Name 'PRE_FREE_LAST_RECORD_PTR'
$preFreeLastRecordPageStart = Extract-IntValue -Text $probeText -Name 'PRE_FREE_LAST_RECORD_PAGE_START'
if ($null -in @($preFreeLastAllocPtr,$preFreeReuseRecordPtr,$preFreeReuseRecordPageStart,$preFreeLastRecordPtr,$preFreeLastRecordPageStart)) { throw 'Missing no-space preservation allocator saturation-reuse fields.' }
if ($preFreeLastAllocPtr -ne 1306624) { throw "Expected PRE_FREE_LAST_ALLOC_PTR=1306624. got $preFreeLastAllocPtr" }
if ($preFreeReuseRecordPtr -ne 1069056) { throw "Expected PRE_FREE_REUSE_RECORD_PTR=1069056. got $preFreeReuseRecordPtr" }
if ($preFreeReuseRecordPageStart -ne 5) { throw "Expected PRE_FREE_REUSE_RECORD_PAGE_START=5. got $preFreeReuseRecordPageStart" }
if ($preFreeLastRecordPtr -ne 1306624) { throw "Expected PRE_FREE_LAST_RECORD_PTR=1306624. got $preFreeLastRecordPtr" }
if ($preFreeLastRecordPageStart -ne 63) { throw "Expected PRE_FREE_LAST_RECORD_PAGE_START=63. got $preFreeLastRecordPageStart" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_NO_SPACE_PRESERVE_PROBE=pass'
Write-Output "PRE_FREE_LAST_ALLOC_PTR=$preFreeLastAllocPtr"
Write-Output "PRE_FREE_REUSE_RECORD_PTR=$preFreeReuseRecordPtr"
Write-Output "PRE_FREE_REUSE_RECORD_PAGE_START=$preFreeReuseRecordPageStart"
Write-Output "PRE_FREE_LAST_RECORD_PTR=$preFreeLastRecordPtr"
Write-Output "PRE_FREE_LAST_RECORD_PAGE_START=$preFreeLastRecordPageStart"
