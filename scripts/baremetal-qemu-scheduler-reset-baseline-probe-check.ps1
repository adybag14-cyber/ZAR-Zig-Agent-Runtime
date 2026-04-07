# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-reset-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_RESET_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-reset-probe-check.ps1' `
    -FailureLabel 'scheduler-reset'
$probeText = $probeState.Text

$enabled = Extract-IntValue -Text $probeText -Name 'PRE_RESET_ENABLED'
$taskCount = Extract-IntValue -Text $probeText -Name 'PRE_RESET_TASK_COUNT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'PRE_RESET_DISPATCH_COUNT'
$taskId = Extract-IntValue -Text $probeText -Name 'PRE_RESET_TASK0_ID'
$taskRunCount = Extract-IntValue -Text $probeText -Name 'PRE_RESET_TASK0_RUN_COUNT'
$taskBudgetRemaining = Extract-IntValue -Text $probeText -Name 'PRE_RESET_TASK0_BUDGET_REMAINING'

if ($null -in @($enabled, $taskCount, $dispatchCount, $taskId, $taskRunCount, $taskBudgetRemaining)) {
    throw 'Missing expected baseline fields in scheduler-reset probe output.'
}
if ($enabled -ne 1) { throw "Expected PRE_RESET_ENABLED=1. got $enabled" }
if ($taskCount -ne 1) { throw "Expected PRE_RESET_TASK_COUNT=1. got $taskCount" }
if ($dispatchCount -ne 1) { throw "Expected PRE_RESET_DISPATCH_COUNT=1. got $dispatchCount" }
if ($taskId -ne 1) { throw "Expected PRE_RESET_TASK0_ID=1. got $taskId" }
if ($taskRunCount -ne 1) { throw "Expected PRE_RESET_TASK0_RUN_COUNT=1. got $taskRunCount" }
if ($taskBudgetRemaining -ne 4) { throw "Expected PRE_RESET_TASK0_BUDGET_REMAINING=4. got $taskBudgetRemaining" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_BASELINE_PROBE=pass'
Write-Output "PRE_RESET_ENABLED=$enabled"
Write-Output "PRE_RESET_TASK_COUNT=$taskCount"
Write-Output "PRE_RESET_DISPATCH_COUNT=$dispatchCount"
Write-Output "PRE_RESET_TASK0_ID=$taskId"
Write-Output "PRE_RESET_TASK0_RUN_COUNT=$taskRunCount"
Write-Output "PRE_RESET_TASK0_BUDGET_REMAINING=$taskBudgetRemaining"
