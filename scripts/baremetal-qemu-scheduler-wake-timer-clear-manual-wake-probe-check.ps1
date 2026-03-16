# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-wake-timer-clear-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
if ($probeText -match '(?m)^BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_PROBE=skipped\r?$') {
    if ($probeText) { Write-Output $probeText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_MANUAL_WAKE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_MANUAL_WAKE_PROBE_SOURCE=baremetal-qemu-scheduler-wake-timer-clear-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    if ($probeText) { Write-Output $probeText.TrimEnd() }
    throw "Underlying scheduler-wake timer-clear probe failed with exit code $probeExitCode"
}

$taskId = Extract-IntValue -Text $probeText -Name 'TASK_ID'
$preTaskState = Extract-IntValue -Text $probeText -Name 'PRE_TASK_STATE'
$preTimerCount = Extract-IntValue -Text $probeText -Name 'PRE_TIMER_COUNT'
$postTaskState = Extract-IntValue -Text $probeText -Name 'POST_RESUME_TASK_STATE'
$postTimerCount = Extract-IntValue -Text $probeText -Name 'POST_RESUME_TIMER_COUNT'
$postEntryState = Extract-IntValue -Text $probeText -Name 'POST_RESUME_ENTRY_STATE'
$postWakeCount = Extract-IntValue -Text $probeText -Name 'POST_RESUME_WAKE_COUNT'
$postWakeReason = Extract-IntValue -Text $probeText -Name 'POST_RESUME_WAKE_REASON'
$postWakeTaskId = Extract-IntValue -Text $probeText -Name 'POST_RESUME_WAKE_TASK_ID'
$postIdleWakeCount = Extract-IntValue -Text $probeText -Name 'POST_IDLE_WAKE_COUNT'
$postIdleTimerCount = Extract-IntValue -Text $probeText -Name 'POST_IDLE_TIMER_COUNT'
$rearmTimerId = Extract-IntValue -Text $probeText -Name 'REARM_TIMER_ID'
$rearmNextTimerId = Extract-IntValue -Text $probeText -Name 'REARM_NEXT_TIMER_ID'

if ($null -in @($taskId, $preTaskState, $preTimerCount, $postTaskState, $postTimerCount, $postEntryState, $postWakeCount, $postWakeReason, $postWakeTaskId, $postIdleWakeCount, $postIdleTimerCount, $rearmTimerId, $rearmNextTimerId)) {
    throw 'Missing expected scheduler-wake timer-clear manual-wake fields in probe output.'
}
if ($taskId -le 0) { throw "Expected TASK_ID>0. got $taskId" }
if ($preTaskState -ne 6) { throw "Expected PRE_TASK_STATE=6 before wake. got $preTaskState" }
if ($preTimerCount -ne 1) { throw "Expected PRE_TIMER_COUNT=1 before wake. got $preTimerCount" }
if ($postTaskState -ne 1) { throw "Expected POST_RESUME_TASK_STATE=1 after wake. got $postTaskState" }
if ($postTimerCount -ne 0) { throw "Expected POST_RESUME_TIMER_COUNT=0 after wake. got $postTimerCount" }
if ($postEntryState -ne 3) { throw "Expected POST_RESUME_ENTRY_STATE=3 for canceled timer entry. got $postEntryState" }
if ($postWakeCount -ne 1) { throw "Expected POST_RESUME_WAKE_COUNT=1. got $postWakeCount" }
if ($postWakeReason -ne 3) { throw "Expected POST_RESUME_WAKE_REASON=3. got $postWakeReason" }
if ($postWakeTaskId -ne $taskId) { throw "Expected POST_RESUME_WAKE_TASK_ID=$taskId. got $postWakeTaskId" }
if ($postIdleWakeCount -ne 1) { throw "Expected POST_IDLE_WAKE_COUNT=1. got $postIdleWakeCount" }
if ($postIdleTimerCount -ne 0) { throw "Expected POST_IDLE_TIMER_COUNT=0. got $postIdleTimerCount" }
if ($rearmTimerId -ne 2) { throw "Expected REARM_TIMER_ID=2 after fresh schedule. got $rearmTimerId" }
if ($rearmNextTimerId -ne 3) { throw "Expected REARM_NEXT_TIMER_ID=3 after fresh schedule. got $rearmNextTimerId" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_MANUAL_WAKE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_MANUAL_WAKE_PROBE_SOURCE=baremetal-qemu-scheduler-wake-timer-clear-probe-check.ps1'
Write-Output "TASK_ID=$taskId"
Write-Output "PRE_TASK_STATE=$preTaskState"
Write-Output "PRE_TIMER_COUNT=$preTimerCount"
Write-Output "POST_RESUME_TASK_STATE=$postTaskState"
Write-Output "POST_RESUME_TIMER_COUNT=$postTimerCount"
Write-Output "POST_RESUME_ENTRY_STATE=$postEntryState"
Write-Output "POST_RESUME_WAKE_COUNT=$postWakeCount"
Write-Output "POST_RESUME_WAKE_REASON=$postWakeReason"
Write-Output "POST_RESUME_WAKE_TASK_ID=$postWakeTaskId"
Write-Output "POST_IDLE_WAKE_COUNT=$postIdleWakeCount"
Write-Output "POST_IDLE_TIMER_COUNT=$postIdleTimerCount"
Write-Output "REARM_TIMER_ID=$rearmTimerId"
Write-Output "REARM_NEXT_TIMER_ID=$rearmNextTimerId"
