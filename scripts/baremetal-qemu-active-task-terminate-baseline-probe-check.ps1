# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-active-task-terminate-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-active-task-terminate-probe-check.ps1' `
    -FailureLabel 'active-task terminate'
$probeText = $probeState.Text

$taskCount = Extract-IntValue -Text $probeText -Name 'PRE_TERMINATE_TASK_COUNT'
$runningSlot = Extract-IntValue -Text $probeText -Name 'PRE_TERMINATE_RUNNING_SLOT'
$lowRun = Extract-IntValue -Text $probeText -Name 'PRE_TERMINATE_LOW_RUN'
$highRun = Extract-IntValue -Text $probeText -Name 'PRE_TERMINATE_HIGH_RUN'
$highBudget = Extract-IntValue -Text $probeText -Name 'PRE_TERMINATE_HIGH_BUDGET_REMAINING'

if ($null -in @($taskCount, $runningSlot, $lowRun, $highRun, $highBudget)) {
    throw 'Missing expected baseline fields in active-task terminate probe output.'
}
if ($taskCount -ne 2) { throw "Expected PRE_TERMINATE_TASK_COUNT=2. got $taskCount" }
if ($runningSlot -ne 1) { throw "Expected PRE_TERMINATE_RUNNING_SLOT=1. got $runningSlot" }
if ($lowRun -ne 0) { throw "Expected PRE_TERMINATE_LOW_RUN=0. got $lowRun" }
if ($highRun -ne 1) { throw "Expected PRE_TERMINATE_HIGH_RUN=1. got $highRun" }
if ($highBudget -ne 5) { throw "Expected PRE_TERMINATE_HIGH_BUDGET_REMAINING=5. got $highBudget" }

Write-Output 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_BASELINE_PROBE=pass'
Write-Output "PRE_TERMINATE_TASK_COUNT=$taskCount"
Write-Output "PRE_TERMINATE_RUNNING_SLOT=$runningSlot"
Write-Output "PRE_TERMINATE_LOW_RUN=$lowRun"
Write-Output "PRE_TERMINATE_HIGH_RUN=$highRun"
Write-Output "PRE_TERMINATE_HIGH_BUDGET_REMAINING=$highBudget"
