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
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_SURVIVOR_WAKE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_SURVIVOR_WAKE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-terminate-mixed-state-probe-check.ps1' `
    -FailureLabel 'task-terminate mixed-state' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$survivorTaskId = Extract-IntValue -Text $probeText -Name 'PRE_SURVIVOR_TASK_ID'
$postWakeCount = Extract-IntValue -Text $probeText -Name 'POST_WAKE_COUNT'
$postPendingWakeCount = Extract-IntValue -Text $probeText -Name 'POST_PENDING_WAKE_COUNT'
$postTask1State = Extract-IntValue -Text $probeText -Name 'POST_TASK1_STATE'
$postWake0TaskId = Extract-IntValue -Text $probeText -Name 'POST_WAKE0_TASK_ID'

if ($null -in @($survivorTaskId, $postWakeCount, $postPendingWakeCount, $postTask1State, $postWake0TaskId)) {
    throw 'Missing expected survivor-wake fields in task-terminate mixed-state probe output.'
}
if ($survivorTaskId -le 0) { throw "Expected non-zero PRE_SURVIVOR_TASK_ID. got $survivorTaskId" }
if ($postWakeCount -ne 1) { throw "Expected POST_WAKE_COUNT=1. got $postWakeCount" }
if ($postPendingWakeCount -ne 1) { throw "Expected POST_PENDING_WAKE_COUNT=1. got $postPendingWakeCount" }
if ($postTask1State -ne 1) { throw "Expected POST_TASK1_STATE=1. got $postTask1State" }
if ($postWake0TaskId -ne $survivorTaskId) { throw "Expected POST_WAKE0_TASK_ID=$survivorTaskId. got $postWake0TaskId" }

Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_SURVIVOR_WAKE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_SURVIVOR_WAKE_PROBE_SOURCE=baremetal-qemu-task-terminate-mixed-state-probe-check.ps1'
Write-Output "PRE_SURVIVOR_TASK_ID=$survivorTaskId"
Write-Output "POST_WAKE_COUNT=$postWakeCount"
Write-Output "POST_PENDING_WAKE_COUNT=$postPendingWakeCount"
Write-Output "POST_TASK1_STATE=$postTask1State"
Write-Output "POST_WAKE0_TASK_ID=$postWake0TaskId"
