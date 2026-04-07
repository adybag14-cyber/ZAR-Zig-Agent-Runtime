# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-cancel-task-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_BASELINE_PROBE' `
    -FailureLabel 'timer-cancel-task' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
$probeText = $probeState.Text
$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_TASK0_ID'
$taskPriority = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_TASK0_PRIORITY'
$taskBudget = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_TASK0_BUDGET'
$armedTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_ARMED_TICKS'
$preCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_PRE_CANCEL_ENTRY_COUNT'
$preState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_PRE_CANCEL_TIMER0_STATE'
$preTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_PRE_CANCEL_TIMER0_TASK_ID'
$preNextFire = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_PRE_CANCEL_TIMER0_NEXT_FIRE_TICK'

if ($null -in @($taskId, $taskPriority, $taskBudget, $armedTicks, $preCount, $preState, $preTaskId, $preNextFire)) {
    throw 'Missing baseline timer-cancel-task fields.'
}
if ($taskId -ne 1) { throw "Expected TASK0_ID=1. got $taskId" }
if ($taskPriority -ne 0) { throw "Expected TASK0_PRIORITY=0. got $taskPriority" }
if ($taskBudget -ne 7) { throw "Expected TASK0_BUDGET=7. got $taskBudget" }
if ($preCount -ne 1) { throw "Expected PRE_CANCEL_ENTRY_COUNT=1. got $preCount" }
if ($preState -ne 1) { throw "Expected PRE_CANCEL_TIMER0_STATE=1. got $preState" }
if ($preTaskId -ne $taskId) { throw "Expected PRE_CANCEL_TIMER0_TASK_ID=$taskId. got $preTaskId" }
if ($preNextFire -le $armedTicks) { throw "Expected PRE_CANCEL_TIMER0_NEXT_FIRE_TICK>$armedTicks. got $preNextFire" }

Write-Output 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_BASELINE_PROBE=pass'
Write-Output "TASK0_ID=$taskId"
Write-Output "TASK0_PRIORITY=$taskPriority"
Write-Output "TASK0_BUDGET=$taskBudget"
Write-Output "ARMED_TICKS=$armedTicks"
Write-Output "PRE_CANCEL_ENTRY_COUNT=$preCount"
Write-Output "PRE_CANCEL_TIMER0_STATE=$preState"
Write-Output "PRE_CANCEL_TIMER0_TASK_ID=$preTaskId"
Write-Output "PRE_CANCEL_TIMER0_NEXT_FIRE_TICK=$preNextFire"
