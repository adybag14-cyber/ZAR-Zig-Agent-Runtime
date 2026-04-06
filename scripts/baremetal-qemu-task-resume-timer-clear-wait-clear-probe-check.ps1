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
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_WAIT_CLEAR_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_WAIT_CLEAR_PROBE_SOURCE' `
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

$POST_RESUME_TASK_STATE = Extract-IntValue -Text $probeText -Name 'POST_RESUME_TASK_STATE'
$POST_RESUME_TIMER_COUNT = Extract-IntValue -Text $probeText -Name 'POST_RESUME_TIMER_COUNT'
$POST_RESUME_WAIT_KIND = Extract-IntValue -Text $probeText -Name 'POST_RESUME_WAIT_KIND'
$POST_RESUME_WAIT_TIMEOUT = Extract-IntValue -Text $probeText -Name 'POST_RESUME_WAIT_TIMEOUT'
if ($null -in @($POST_RESUME_TASK_STATE, $POST_RESUME_TIMER_COUNT, $POST_RESUME_WAIT_KIND, $POST_RESUME_WAIT_TIMEOUT)) {
    throw 'Missing expected task-resume timer-clear wait-clear fields in probe output.'
}
if ($POST_RESUME_TASK_STATE -ne 1) { throw "Expected POST_RESUME_TASK_STATE=1. got $POST_RESUME_TASK_STATE" }
if ($POST_RESUME_TIMER_COUNT -ne 0) { throw "Expected POST_RESUME_TIMER_COUNT=0. got $POST_RESUME_TIMER_COUNT" }
if ($POST_RESUME_WAIT_KIND -ne 0) { throw "Expected POST_RESUME_WAIT_KIND=0. got $POST_RESUME_WAIT_KIND" }
if ($POST_RESUME_WAIT_TIMEOUT -ne 0) { throw "Expected POST_RESUME_WAIT_TIMEOUT=0. got $POST_RESUME_WAIT_TIMEOUT" }

Write-Output 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_WAIT_CLEAR_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_WAIT_CLEAR_PROBE_SOURCE=baremetal-qemu-task-resume-timer-clear-probe-check.ps1'
Write-Output "POST_RESUME_TASK_STATE=$POST_RESUME_TASK_STATE"
Write-Output "POST_RESUME_TIMER_COUNT=$POST_RESUME_TIMER_COUNT"
Write-Output "POST_RESUME_WAIT_KIND=$POST_RESUME_WAIT_KIND"
Write-Output "POST_RESUME_WAIT_TIMEOUT=$POST_RESUME_WAIT_TIMEOUT"
