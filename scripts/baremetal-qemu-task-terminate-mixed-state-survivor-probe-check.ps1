# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-task-terminate-mixed-state-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\\d+)\\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_SURVIVOR_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_SURVIVOR_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-terminate-mixed-state-probe-check.ps1' `
    -FailureLabel 'task-terminate mixed-state' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$terminatedTaskId = Extract-IntValue -Text $probeText -Name 'PRE_TERMINATED_TASK_ID'
$survivorTaskId = Extract-IntValue -Text $probeText -Name 'PRE_SURVIVOR_TASK_ID'
$preWake0TaskId = Extract-IntValue -Text $probeText -Name 'PRE_WAKE0_TASK_ID'
$preWake1TaskId = Extract-IntValue -Text $probeText -Name 'PRE_WAKE1_TASK_ID'
$postTaskCount = Extract-IntValue -Text $probeText -Name 'POST_TASK_COUNT'
$postWakeCount = Extract-IntValue -Text $probeText -Name 'POST_WAKE_COUNT'
$postPendingWakeCount = Extract-IntValue -Text $probeText -Name 'POST_PENDING_WAKE_COUNT'
$postTask0State = Extract-IntValue -Text $probeText -Name 'POST_TASK0_STATE'
$postTask1State = Extract-IntValue -Text $probeText -Name 'POST_TASK1_STATE'
$postWake0TaskId = Extract-IntValue -Text $probeText -Name 'POST_WAKE0_TASK_ID'
$afterIdleWakeCount = Extract-IntValue -Text $probeText -Name 'AFTER_IDLE_WAKE_COUNT'
$afterIdlePendingWakeCount = Extract-IntValue -Text $probeText -Name 'AFTER_IDLE_PENDING_WAKE_COUNT'
$afterIdleWake0TaskId = Extract-IntValue -Text $probeText -Name 'AFTER_IDLE_WAKE0_TASK_ID'
$afterIdleTimerDispatchCount = Extract-IntValue -Text $probeText -Name 'AFTER_IDLE_TIMER_DISPATCH_COUNT'

if ($null -in @($terminatedTaskId, $survivorTaskId, $preWake0TaskId, $preWake1TaskId, $postTaskCount, $postWakeCount, $postPendingWakeCount, $postTask0State, $postTask1State, $postWake0TaskId, $afterIdleWakeCount, $afterIdlePendingWakeCount, $afterIdleWake0TaskId, $afterIdleTimerDispatchCount)) {
    throw 'Missing expected task-terminate mixed-state survivor fields in probe output.'
}
if ($terminatedTaskId -le 0 -or $survivorTaskId -le 0 -or $terminatedTaskId -eq $survivorTaskId) {
    throw "Expected distinct non-zero task ids. terminated=$terminatedTaskId survivor=$survivorTaskId"
}
if ($preWake0TaskId -ne $terminatedTaskId) { throw "Expected PRE_WAKE0_TASK_ID=$terminatedTaskId. got $preWake0TaskId" }
if ($preWake1TaskId -ne $survivorTaskId) { throw "Expected PRE_WAKE1_TASK_ID=$survivorTaskId. got $preWake1TaskId" }
if ($postTaskCount -ne 1) { throw "Expected POST_TASK_COUNT=1 after terminate. got $postTaskCount" }
if ($postWakeCount -ne 1) { throw "Expected POST_WAKE_COUNT=1 after terminate. got $postWakeCount" }
if ($postPendingWakeCount -ne 1) { throw "Expected POST_PENDING_WAKE_COUNT=1 after terminate. got $postPendingWakeCount" }
if ($postTask0State -ne 4) { throw "Expected POST_TASK0_STATE=4 for terminated task. got $postTask0State" }
if ($postTask1State -ne 1) { throw "Expected POST_TASK1_STATE=1 for survivor. got $postTask1State" }
if ($postWake0TaskId -ne $survivorTaskId) { throw "Expected POST_WAKE0_TASK_ID=$survivorTaskId. got $postWake0TaskId" }
if ($afterIdleWakeCount -ne 1) { throw "Expected AFTER_IDLE_WAKE_COUNT=1. got $afterIdleWakeCount" }
if ($afterIdlePendingWakeCount -ne 1) { throw "Expected AFTER_IDLE_PENDING_WAKE_COUNT=1. got $afterIdlePendingWakeCount" }
if ($afterIdleWake0TaskId -ne $survivorTaskId) { throw "Expected AFTER_IDLE_WAKE0_TASK_ID=$survivorTaskId. got $afterIdleWake0TaskId" }
if ($afterIdleTimerDispatchCount -ne 0) { throw "Expected AFTER_IDLE_TIMER_DISPATCH_COUNT=0. got $afterIdleTimerDispatchCount" }

Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_SURVIVOR_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_SURVIVOR_PROBE_SOURCE=baremetal-qemu-task-terminate-mixed-state-probe-check.ps1'
Write-Output "PRE_TERMINATED_TASK_ID=$terminatedTaskId"
Write-Output "PRE_SURVIVOR_TASK_ID=$survivorTaskId"
Write-Output "PRE_WAKE0_TASK_ID=$preWake0TaskId"
Write-Output "PRE_WAKE1_TASK_ID=$preWake1TaskId"
Write-Output "POST_TASK_COUNT=$postTaskCount"
Write-Output "POST_WAKE_COUNT=$postWakeCount"
Write-Output "POST_PENDING_WAKE_COUNT=$postPendingWakeCount"
Write-Output "POST_TASK0_STATE=$postTask0State"
Write-Output "POST_TASK1_STATE=$postTask1State"
Write-Output "POST_WAKE0_TASK_ID=$postWake0TaskId"
Write-Output "AFTER_IDLE_WAKE_COUNT=$afterIdleWakeCount"
Write-Output "AFTER_IDLE_PENDING_WAKE_COUNT=$afterIdlePendingWakeCount"
Write-Output "AFTER_IDLE_WAKE0_TASK_ID=$afterIdleWake0TaskId"
Write-Output "AFTER_IDLE_TIMER_DISPATCH_COUNT=$afterIdleTimerDispatchCount"
