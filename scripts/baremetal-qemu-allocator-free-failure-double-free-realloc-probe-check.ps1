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
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_DOUBLE_FREE_REALLOC_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_DOUBLE_FREE_REALLOC_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-free-failure-probe-check.ps1' `
    -FailureLabel 'allocator free-failure'
$probeText = $probeState.Text
$doubleFreeResult = Extract-IntValue -Text $probeText -Name 'DOUBLE_FREE_RESULT'
$doubleFreeFreePages = Extract-IntValue -Text $probeText -Name 'DOUBLE_FREE_FREE_PAGES'
$doubleFreeCount = Extract-IntValue -Text $probeText -Name 'DOUBLE_FREE_COUNT'
$doubleFreeLastFreePtr = Extract-IntValue -Text $probeText -Name 'DOUBLE_FREE_LAST_FREE_PTR'
$doubleFreeLastFreeSize = Extract-IntValue -Text $probeText -Name 'DOUBLE_FREE_LAST_FREE_SIZE'
$reallocPtr = Extract-IntValue -Text $probeText -Name 'REALLOC_PTR'
$reallocPageStart = Extract-IntValue -Text $probeText -Name 'REALLOC_PAGE_START'
$reallocPageLen = Extract-IntValue -Text $probeText -Name 'REALLOC_PAGE_LEN'
$reallocFreePages = Extract-IntValue -Text $probeText -Name 'REALLOC_FREE_PAGES'
$reallocCount = Extract-IntValue -Text $probeText -Name 'REALLOC_COUNT'
if ($null -in @($allocPtr,$doubleFreeResult,$doubleFreeFreePages,$doubleFreeCount,$doubleFreeLastFreePtr,$doubleFreeLastFreeSize,$reallocPtr,$reallocPageStart,$reallocPageLen,$reallocFreePages,$reallocCount)) { throw 'Missing double-free/realloc allocator free-failure fields.' }
if ($doubleFreeResult -ne -2) { throw "Expected DOUBLE_FREE_RESULT=-2. got $doubleFreeResult" }
if ($doubleFreeFreePages -ne 256) { throw "Expected DOUBLE_FREE_FREE_PAGES=256. got $doubleFreeFreePages" }
if ($doubleFreeCount -ne 0) { throw "Expected DOUBLE_FREE_COUNT=0. got $doubleFreeCount" }
if ($doubleFreeLastFreePtr -ne $allocPtr) { throw "Expected DOUBLE_FREE_LAST_FREE_PTR=$allocPtr. got $doubleFreeLastFreePtr" }
if ($doubleFreeLastFreeSize -ne 8192) { throw "Expected DOUBLE_FREE_LAST_FREE_SIZE=8192. got $doubleFreeLastFreeSize" }
if ($reallocPtr -ne 1048576) { throw "Expected REALLOC_PTR=1048576. got $reallocPtr" }
if ($reallocPageStart -ne 0) { throw "Expected REALLOC_PAGE_START=0. got $reallocPageStart" }
if ($reallocPageLen -ne 1) { throw "Expected REALLOC_PAGE_LEN=1. got $reallocPageLen" }
if ($reallocFreePages -ne 255) { throw "Expected REALLOC_FREE_PAGES=255. got $reallocFreePages" }
if ($reallocCount -ne 1) { throw "Expected REALLOC_COUNT=1. got $reallocCount" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_DOUBLE_FREE_REALLOC_PROBE=pass'
Write-Output "DOUBLE_FREE_RESULT=$doubleFreeResult"
Write-Output "DOUBLE_FREE_FREE_PAGES=$doubleFreeFreePages"
Write-Output "DOUBLE_FREE_COUNT=$doubleFreeCount"
Write-Output "DOUBLE_FREE_LAST_FREE_PTR=$doubleFreeLastFreePtr"
Write-Output "DOUBLE_FREE_LAST_FREE_SIZE=$doubleFreeLastFreeSize"
Write-Output "REALLOC_PTR=$reallocPtr"
Write-Output "REALLOC_PAGE_START=$reallocPageStart"
Write-Output "REALLOC_PAGE_LEN=$reallocPageLen"
Write-Output "REALLOC_FREE_PAGES=$reallocFreePages"
Write-Output "REALLOC_COUNT=$reallocCount"

