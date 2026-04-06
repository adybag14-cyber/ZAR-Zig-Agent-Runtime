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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_SATURATION_OVERFLOW_PRESERVE_PROBE' `
    -FailureLabel 'scheduler saturation' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$overflowResult = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_OVERFLOW_RESULT"
$overflowTaskCount = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_OVERFLOW_TASK_COUNT"
$previousId = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSED_SLOT_PREVIOUS_ID"

if ($overflowResult -ne -28) { throw "Expected OVERFLOW_RESULT=-28, got $overflowResult" }
if ($overflowTaskCount -ne 16) { throw "Expected OVERFLOW_TASK_COUNT=16, got $overflowTaskCount" }
if ($previousId -le 0) { throw "Expected REUSED_SLOT_PREVIOUS_ID > 0, got $previousId" }

Write-Output "BAREMETAL_QEMU_SCHEDULER_SATURATION_OVERFLOW_PRESERVE_PROBE=pass"
Write-Output "OVERFLOW_RESULT=$overflowResult"
Write-Output "OVERFLOW_TASK_COUNT=$overflowTaskCount"
Write-Output "REUSED_SLOT_PREVIOUS_ID=$previousId"
