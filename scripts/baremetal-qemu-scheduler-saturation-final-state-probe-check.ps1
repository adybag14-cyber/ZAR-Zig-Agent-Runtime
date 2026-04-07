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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_SATURATION_FINAL_STATE_PROBE' `
    -FailureLabel 'scheduler saturation' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$ack = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_ACK"
$lastOpcode = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_LAST_OPCODE"
$lastResult = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_LAST_RESULT"
$taskCount = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_TASK_COUNT"
$reusedState = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSED_STATE"

if ($ack -ne 20) { throw "Expected ACK=20, got $ack" }
if ($lastOpcode -ne 27) { throw "Expected LAST_OPCODE=27, got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0, got $lastResult" }
if ($taskCount -ne 16) { throw "Expected TASK_COUNT=16, got $taskCount" }
if ($reusedState -ne 1) { throw "Expected REUSED_STATE=1, got $reusedState" }

Write-Output "BAREMETAL_QEMU_SCHEDULER_SATURATION_FINAL_STATE_PROBE=pass"
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TASK_COUNT=$taskCount"
Write-Output "REUSED_STATE=$reusedState"
