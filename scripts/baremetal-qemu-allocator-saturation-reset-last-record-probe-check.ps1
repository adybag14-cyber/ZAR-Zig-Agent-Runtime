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
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_RESET_LAST_RECORD_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_RESET_LAST_RECORD_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-saturation-reset-probe-check.ps1' `
    -FailureLabel 'allocator saturation-reset'
$probeText = $probeState.Text
$preResetLastAllocPtr = Extract-IntValue -Text $probeText -Name 'PRE_RESET_LAST_ALLOC_PTR'
$preResetLastRecordPtr = Extract-IntValue -Text $probeText -Name 'PRE_RESET_LAST_RECORD_PTR'
$preResetLastRecordPageStart = Extract-IntValue -Text $probeText -Name 'PRE_RESET_LAST_RECORD_PAGE_START'
if ($null -in @($preResetFirstRecordState,$preResetLastAllocPtr,$preResetLastRecordPtr,$preResetLastRecordPageStart)) { throw 'Missing last-record allocator saturation-reset fields.' }
if ($preResetFirstRecordState -ne 1) { throw "Expected PRE_RESET_FIRST_RECORD_STATE=1. got $preResetFirstRecordState" }
if ($preResetLastAllocPtr -ne 1306624) { throw "Expected PRE_RESET_LAST_ALLOC_PTR=1306624. got $preResetLastAllocPtr" }
if ($preResetLastRecordPtr -ne $preResetLastAllocPtr) { throw "Expected PRE_RESET_LAST_RECORD_PTR=$preResetLastAllocPtr. got $preResetLastRecordPtr" }
if ($preResetLastRecordPageStart -ne 63) { throw "Expected PRE_RESET_LAST_RECORD_PAGE_START=63. got $preResetLastRecordPageStart" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_RESET_LAST_RECORD_PROBE=pass'
Write-Output "PRE_RESET_FIRST_RECORD_STATE=$preResetFirstRecordState"
Write-Output "PRE_RESET_LAST_ALLOC_PTR=$preResetLastAllocPtr"
Write-Output "PRE_RESET_LAST_RECORD_PTR=$preResetLastRecordPtr"
Write-Output "PRE_RESET_LAST_RECORD_PAGE_START=$preResetLastRecordPageStart"
