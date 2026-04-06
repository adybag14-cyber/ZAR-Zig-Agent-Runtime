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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_SATURATION_TERMINATE_STATE_PROBE' `
    -FailureLabel 'scheduler saturation' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$terminateLastResult = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_TERMINATE_LAST_RESULT"
$terminateTaskCount = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_TERMINATE_TASK_COUNT"
$terminatedState = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_TERMINATED_STATE"

if ($terminateLastResult -ne 0) { throw "Expected TERMINATE_LAST_RESULT=0, got $terminateLastResult" }
if ($terminateTaskCount -ne 15) { throw "Expected TERMINATE_TASK_COUNT=15, got $terminateTaskCount" }
if ($terminatedState -ne 4) { throw "Expected TERMINATED_STATE=4, got $terminatedState" }

Write-Output "BAREMETAL_QEMU_SCHEDULER_SATURATION_TERMINATE_STATE_PROBE=pass"
Write-Output "TERMINATE_LAST_RESULT=$terminateLastResult"
Write-Output "TERMINATE_TASK_COUNT=$terminateTaskCount"
Write-Output "TERMINATED_STATE=$terminatedState"
