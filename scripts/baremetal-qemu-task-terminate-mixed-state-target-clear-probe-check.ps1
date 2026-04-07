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
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_TARGET_CLEAR_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_TARGET_CLEAR_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-terminate-mixed-state-probe-check.ps1' `
    -FailureLabel 'task-terminate mixed-state' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$postTaskCount = Extract-IntValue -Text $probeText -Name 'POST_TASK_COUNT'
$postTask0State = Extract-IntValue -Text $probeText -Name 'POST_TASK0_STATE'
$postTimerCount = Extract-IntValue -Text $probeText -Name 'POST_TIMER_COUNT'
$postTimer0State = Extract-IntValue -Text $probeText -Name 'POST_TIMER0_STATE'

if ($null -in @($postTaskCount, $postTask0State, $postTimerCount, $postTimer0State)) {
    throw 'Missing expected target-clear fields in task-terminate mixed-state probe output.'
}
if ($postTaskCount -ne 1) { throw "Expected POST_TASK_COUNT=1. got $postTaskCount" }
if ($postTask0State -ne 4) { throw "Expected POST_TASK0_STATE=4. got $postTask0State" }
if ($postTimerCount -ne 0) { throw "Expected POST_TIMER_COUNT=0. got $postTimerCount" }
if ($postTimer0State -ne 3) { throw "Expected POST_TIMER0_STATE=3. got $postTimer0State" }

Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_TARGET_CLEAR_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_MIXED_STATE_TARGET_CLEAR_PROBE_SOURCE=baremetal-qemu-task-terminate-mixed-state-probe-check.ps1'
Write-Output "POST_TASK_COUNT=$postTaskCount"
Write-Output "POST_TASK0_STATE=$postTask0State"
Write-Output "POST_TIMER_COUNT=$postTimerCount"
Write-Output "POST_TIMER0_STATE=$postTimer0State"
