# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1'
$taskWaitForOpcode = 53
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_REARM_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_REARM_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1' `
    -FailureLabel 'scheduler-reset mixed-state' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$freshTaskId = Extract-IntValue -Text $probeText -Name 'FRESH_TASK_ID'
$rearmTimerCount = Extract-IntValue -Text $probeText -Name 'REARM_TIMER_COUNT'
$rearmTimerId = Extract-IntValue -Text $probeText -Name 'REARM_TIMER_ID'
$rearmNextTimerId = Extract-IntValue -Text $probeText -Name 'REARM_NEXT_TIMER_ID'

if ($null -in @($ack, $lastOpcode, $lastResult, $freshTaskId, $rearmTimerCount, $rearmTimerId, $rearmNextTimerId)) {
    throw 'Missing expected scheduler-reset mixed-state rearm fields in probe output.'
}
if ($ack -ne 10) { throw "Expected ACK=10. got $ack" }
if ($lastOpcode -ne $taskWaitForOpcode) { throw "Expected LAST_OPCODE=53. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($freshTaskId -ne 1) { throw "Expected FRESH_TASK_ID=1. got $freshTaskId" }
if ($rearmTimerCount -ne 1) { throw "Expected REARM_TIMER_COUNT=1. got $rearmTimerCount" }
if ($rearmTimerId -ne 2) { throw "Expected REARM_TIMER_ID=2. got $rearmTimerId" }
if ($rearmNextTimerId -ne 3) { throw "Expected REARM_NEXT_TIMER_ID=3. got $rearmNextTimerId" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_REARM_STATE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "FRESH_TASK_ID=$freshTaskId"
Write-Output "REARM_TIMER_COUNT=$rearmTimerCount"
Write-Output "REARM_TIMER_ID=$rearmTimerId"
Write-Output "REARM_NEXT_TIMER_ID=$rearmNextTimerId"
