# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-priority-budget-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-priority-budget-probe-check.ps1' `
    -FailureLabel 'scheduler-priority-budget'
$probeText = $probeState.Text

$defaultBudget = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_DEFAULT_BUDGET'
$lowId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_LOW_ID'
$highId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_HIGH_ID'
$lowPriorityBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_LOW_PRIORITY_BEFORE'
$highPriorityBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_HIGH_PRIORITY_BEFORE'
$taskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_TASK_COUNT'
$policy = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_POLICY'
$lowState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_LOW_STATE'
$highState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_HIGH_STATE'

if ($null -in @($defaultBudget, $lowId, $highId, $lowPriorityBefore, $highPriorityBefore, $taskCount, $policy, $lowState, $highState)) {
    throw 'Missing expected scheduler-priority-budget baseline fields in probe output.'
}
if ($defaultBudget -ne 9) { throw "Expected DEFAULT_BUDGET=9. got $defaultBudget" }
if ($lowId -le 0) { throw "Expected LOW_ID > 0. got $lowId" }
if ($highId -le $lowId) { throw "Expected HIGH_ID > LOW_ID. got LOW_ID=$lowId HIGH_ID=$highId" }
if ($lowPriorityBefore -ne 1) { throw "Expected LOW_PRIORITY_BEFORE=1. got $lowPriorityBefore" }
if ($highPriorityBefore -ne 9) { throw "Expected HIGH_PRIORITY_BEFORE=9. got $highPriorityBefore" }
if ($taskCount -ne 2) { throw "Expected TASK_COUNT=2. got $taskCount" }
if ($policy -ne 1) { throw "Expected POLICY=1. got $policy" }
if ($lowState -ne 1 -or $highState -ne 1) { throw "Expected both task states ready. got low=$lowState high=$highState" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_BASELINE_PROBE=pass'
Write-Output "DEFAULT_BUDGET=$defaultBudget"
Write-Output "LOW_ID=$lowId"
Write-Output "HIGH_ID=$highId"
Write-Output "LOW_PRIORITY_BEFORE=$lowPriorityBefore"
Write-Output "HIGH_PRIORITY_BEFORE=$highPriorityBefore"
Write-Output "TASK_COUNT=$taskCount"
Write-Output "POLICY=$policy"
