# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-free-failure-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_GOOD_FREE_METADATA_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_GOOD_FREE_METADATA_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-free-failure-probe-check.ps1' `
    -FailureLabel 'allocator free-failure'
$probeText = $probeState.Text
$goodFreeResult = Extract-IntValue -Text $probeText -Name 'GOOD_FREE_RESULT'
$goodFreeFreePages = Extract-IntValue -Text $probeText -Name 'GOOD_FREE_FREE_PAGES'
$goodFreeCount = Extract-IntValue -Text $probeText -Name 'GOOD_FREE_COUNT'
$goodFreeLastFreePtr = Extract-IntValue -Text $probeText -Name 'GOOD_FREE_LAST_FREE_PTR'
$goodFreeLastFreeSize = Extract-IntValue -Text $probeText -Name 'GOOD_FREE_LAST_FREE_SIZE'
if ($null -in @($allocPtr,$goodFreeResult,$goodFreeFreePages,$goodFreeCount,$goodFreeLastFreePtr,$goodFreeLastFreeSize)) { throw 'Missing good-free allocator free-failure fields.' }
if ($goodFreeResult -ne 0) { throw "Expected GOOD_FREE_RESULT=0. got $goodFreeResult" }
if ($goodFreeFreePages -ne 256) { throw "Expected GOOD_FREE_FREE_PAGES=256. got $goodFreeFreePages" }
if ($goodFreeCount -ne 0) { throw "Expected GOOD_FREE_COUNT=0. got $goodFreeCount" }
if ($goodFreeLastFreePtr -ne $allocPtr) { throw "Expected GOOD_FREE_LAST_FREE_PTR=$allocPtr. got $goodFreeLastFreePtr" }
if ($goodFreeLastFreeSize -ne 8192) { throw "Expected GOOD_FREE_LAST_FREE_SIZE=8192. got $goodFreeLastFreeSize" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_GOOD_FREE_METADATA_PROBE=pass'
Write-Output "GOOD_FREE_RESULT=$goodFreeResult"
Write-Output "GOOD_FREE_FREE_PAGES=$goodFreeFreePages"
Write-Output "GOOD_FREE_COUNT=$goodFreeCount"
Write-Output "GOOD_FREE_LAST_FREE_PTR=$goodFreeLastFreePtr"
Write-Output "GOOD_FREE_LAST_FREE_SIZE=$goodFreeLastFreeSize"

