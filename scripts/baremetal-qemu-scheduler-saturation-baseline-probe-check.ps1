# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-saturation-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_SATURATION_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_SATURATION_BASELINE_PROBE' `
    -FailureLabel 'scheduler saturation' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$taskCapacity = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_TASK_CAPACITY"
$fullCount = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_FULL_COUNT"
$lastTaskId = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_LAST_TASK_ID"

if ($taskCapacity -ne 16) { throw "Expected TASK_CAPACITY=16, got $taskCapacity" }
if ($fullCount -ne 16) { throw "Expected FULL_COUNT=16, got $fullCount" }
if ($lastTaskId -ne 16) { throw "Expected LAST_TASK_ID=16, got $lastTaskId" }

Write-Output "BAREMETAL_QEMU_SCHEDULER_SATURATION_BASELINE_PROBE=pass"
Write-Output "TASK_CAPACITY=$taskCapacity"
Write-Output "FULL_COUNT=$fullCount"
Write-Output "LAST_TASK_ID=$lastTaskId"
