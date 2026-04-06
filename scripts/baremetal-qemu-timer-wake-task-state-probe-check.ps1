# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-wake-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TIMER_WAKE_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_WAKE_TASK_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TIMER_WAKE_TASK_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-timer-wake-probe-check.ps1' `
    -FailureLabel 'timer-wake'
$probeText = $probeState.Text

$task0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TASK0_STATE'
$task0RunCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TASK0_RUN_COUNT'
$task0Budget = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TASK0_BUDGET'
$task0BudgetRemaining = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TASK0_BUDGET_REMAINING'

if ($null -in @($task0State, $task0RunCount, $task0Budget, $task0BudgetRemaining)) {
    throw 'Missing expected task-state fields in timer-wake probe output.'
}
if ($task0State -ne 1) { throw "Expected TASK0_STATE=1. got $task0State" }
if ($task0RunCount -ne 0) { throw "Expected TASK0_RUN_COUNT=0. got $task0RunCount" }
if ($task0Budget -ne 9) { throw "Expected TASK0_BUDGET=9. got $task0Budget" }
if ($task0BudgetRemaining -ne $task0Budget) { throw "Expected TASK0_BUDGET_REMAINING to equal TASK0_BUDGET. got $task0BudgetRemaining vs $task0Budget" }

Write-Output 'BAREMETAL_QEMU_TIMER_WAKE_TASK_STATE_PROBE=pass'
Write-Output "TASK0_STATE=$task0State"
Write-Output "TASK0_RUN_COUNT=$task0RunCount"
Write-Output "TASK0_BUDGET=$task0Budget"
Write-Output "TASK0_BUDGET_REMAINING=$task0BudgetRemaining"
