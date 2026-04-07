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
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BAD_POINTER_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BAD_POINTER_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-free-failure-probe-check.ps1' `
    -FailureLabel 'allocator free-failure'
$probeText = $probeState.Text
$badPtrFreePages = Extract-IntValue -Text $probeText -Name 'BAD_PTR_FREE_PAGES'
$badPtrCount = Extract-IntValue -Text $probeText -Name 'BAD_PTR_COUNT'
$badPtrLastFreePtr = Extract-IntValue -Text $probeText -Name 'BAD_PTR_LAST_FREE_PTR'
$badPtrLastFreeSize = Extract-IntValue -Text $probeText -Name 'BAD_PTR_LAST_FREE_SIZE'
if ($null -in @($badPtrResult,$badPtrFreePages,$badPtrCount,$badPtrLastFreePtr,$badPtrLastFreeSize)) { throw 'Missing bad-pointer allocator free-failure fields.' }
if ($badPtrResult -ne -2) { throw "Expected BAD_PTR_RESULT=-2. got $badPtrResult" }
if ($badPtrFreePages -ne 254) { throw "Expected BAD_PTR_FREE_PAGES=254. got $badPtrFreePages" }
if ($badPtrCount -ne 1) { throw "Expected BAD_PTR_COUNT=1. got $badPtrCount" }
if ($badPtrLastFreePtr -ne 0) { throw "Expected BAD_PTR_LAST_FREE_PTR=0. got $badPtrLastFreePtr" }
if ($badPtrLastFreeSize -ne 0) { throw "Expected BAD_PTR_LAST_FREE_SIZE=0. got $badPtrLastFreeSize" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BAD_POINTER_PRESERVE_PROBE=pass'
Write-Output "BAD_PTR_RESULT=$badPtrResult"
Write-Output "BAD_PTR_FREE_PAGES=$badPtrFreePages"
Write-Output "BAD_PTR_COUNT=$badPtrCount"
Write-Output "BAD_PTR_LAST_FREE_PTR=$badPtrLastFreePtr"
Write-Output "BAD_PTR_LAST_FREE_SIZE=$badPtrLastFreeSize"

