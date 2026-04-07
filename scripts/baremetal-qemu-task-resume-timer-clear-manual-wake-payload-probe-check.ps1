# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-task-resume-timer-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_MANUAL_WAKE_PAYLOAD_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_MANUAL_WAKE_PAYLOAD_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-resume-timer-clear-probe-check.ps1' `
    -FailureLabel 'task-resume timer-clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

    throw "Underlying task-resume timer-clear probe failed with exit code $probeExitCode"
}

$TASK_ID = Extract-IntValue -Text $probeText -Name 'TASK_ID'
$POST_RESUME_WAKE_COUNT = Extract-IntValue -Text $probeText -Name 'POST_RESUME_WAKE_COUNT'
$POST_RESUME_WAKE_REASON = Extract-IntValue -Text $probeText -Name 'POST_RESUME_WAKE_REASON'
$POST_RESUME_WAKE_TASK_ID = Extract-IntValue -Text $probeText -Name 'POST_RESUME_WAKE_TASK_ID'
$POST_RESUME_WAKE_TIMER_ID = Extract-IntValue -Text $probeText -Name 'POST_RESUME_WAKE_TIMER_ID'
$POST_RESUME_WAKE_TICK = Extract-IntValue -Text $probeText -Name 'POST_RESUME_WAKE_TICK'
if ($null -in @($TASK_ID, $POST_RESUME_WAKE_COUNT, $POST_RESUME_WAKE_REASON, $POST_RESUME_WAKE_TASK_ID, $POST_RESUME_WAKE_TIMER_ID, $POST_RESUME_WAKE_TICK)) {
    throw 'Missing expected task-resume timer-clear manual-wake fields in probe output.'
}
if ($POST_RESUME_WAKE_COUNT -ne 1) { throw "Expected POST_RESUME_WAKE_COUNT=1. got $POST_RESUME_WAKE_COUNT" }
if ($POST_RESUME_WAKE_REASON -ne 3) { throw "Expected POST_RESUME_WAKE_REASON=3. got $POST_RESUME_WAKE_REASON" }
if ($POST_RESUME_WAKE_TASK_ID -ne $TASK_ID) { throw "Expected POST_RESUME_WAKE_TASK_ID=$TASK_ID. got $POST_RESUME_WAKE_TASK_ID" }
if ($POST_RESUME_WAKE_TIMER_ID -ne 0) { throw "Expected POST_RESUME_WAKE_TIMER_ID=0. got $POST_RESUME_WAKE_TIMER_ID" }
if ($POST_RESUME_WAKE_TICK -le 0) { throw "Expected POST_RESUME_WAKE_TICK>0. got $POST_RESUME_WAKE_TICK" }

Write-Output 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_MANUAL_WAKE_PAYLOAD_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_MANUAL_WAKE_PAYLOAD_PROBE_SOURCE=baremetal-qemu-task-resume-timer-clear-probe-check.ps1'
Write-Output "TASK_ID=$TASK_ID"
Write-Output "POST_RESUME_WAKE_COUNT=$POST_RESUME_WAKE_COUNT"
Write-Output "POST_RESUME_WAKE_REASON=$POST_RESUME_WAKE_REASON"
Write-Output "POST_RESUME_WAKE_TASK_ID=$POST_RESUME_WAKE_TASK_ID"
Write-Output "POST_RESUME_WAKE_TIMER_ID=$POST_RESUME_WAKE_TIMER_ID"
Write-Output "POST_RESUME_WAKE_TICK=$POST_RESUME_WAKE_TICK"
