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
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BAD_SIZE_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BAD_SIZE_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-free-failure-probe-check.ps1' `
    -FailureLabel 'allocator free-failure'
$probeText = $probeState.Text
$badSizeFreePages = Extract-IntValue -Text $probeText -Name 'BAD_SIZE_FREE_PAGES'
$badSizeCount = Extract-IntValue -Text $probeText -Name 'BAD_SIZE_COUNT'
$badSizeLastFreePtr = Extract-IntValue -Text $probeText -Name 'BAD_SIZE_LAST_FREE_PTR'
$badSizeLastFreeSize = Extract-IntValue -Text $probeText -Name 'BAD_SIZE_LAST_FREE_SIZE'
if ($null -in @($badSizeResult,$badSizeFreePages,$badSizeCount,$badSizeLastFreePtr,$badSizeLastFreeSize)) { throw 'Missing bad-size allocator free-failure fields.' }
if ($badSizeResult -ne -22) { throw "Expected BAD_SIZE_RESULT=-22. got $badSizeResult" }
if ($badSizeFreePages -ne 254) { throw "Expected BAD_SIZE_FREE_PAGES=254. got $badSizeFreePages" }
if ($badSizeCount -ne 1) { throw "Expected BAD_SIZE_COUNT=1. got $badSizeCount" }
if ($badSizeLastFreePtr -ne 0) { throw "Expected BAD_SIZE_LAST_FREE_PTR=0. got $badSizeLastFreePtr" }
if ($badSizeLastFreeSize -ne 0) { throw "Expected BAD_SIZE_LAST_FREE_SIZE=0. got $badSizeLastFreeSize" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BAD_SIZE_PRESERVE_PROBE=pass'
Write-Output "BAD_SIZE_RESULT=$badSizeResult"
Write-Output "BAD_SIZE_FREE_PAGES=$badSizeFreePages"
Write-Output "BAD_SIZE_COUNT=$badSizeCount"
Write-Output "BAD_SIZE_LAST_FREE_PTR=$badSizeLastFreePtr"
Write-Output "BAD_SIZE_LAST_FREE_SIZE=$badSizeLastFreeSize"

