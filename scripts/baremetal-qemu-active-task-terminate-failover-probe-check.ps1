# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-active-task-terminate-probe-check.ps1"
$taskStateTerminated = 4
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_FAILOVER_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_FAILOVER_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-active-task-terminate-probe-check.ps1' `
    -FailureLabel 'active-task terminate'
$probeText = $probeState.Text

$taskCount = Extract-IntValue -Text $probeText -Name 'POST_TERMINATE_TASK_COUNT'
$runningSlot = Extract-IntValue -Text $probeText -Name 'POST_TERMINATE_RUNNING_SLOT'
$lowRun = Extract-IntValue -Text $probeText -Name 'POST_TERMINATE_LOW_RUN'
$lowBudget = Extract-IntValue -Text $probeText -Name 'POST_TERMINATE_LOW_BUDGET_REMAINING'
$highState = Extract-IntValue -Text $probeText -Name 'POST_TERMINATE_HIGH_STATE'

if ($null -in @($taskCount, $runningSlot, $lowRun, $lowBudget, $highState)) {
    throw 'Missing expected failover fields in active-task terminate probe output.'
}
if ($taskCount -ne 1) { throw "Expected POST_TERMINATE_TASK_COUNT=1. got $taskCount" }
if ($runningSlot -ne 0) { throw "Expected POST_TERMINATE_RUNNING_SLOT=0. got $runningSlot" }
if ($lowRun -ne 1) { throw "Expected POST_TERMINATE_LOW_RUN=1. got $lowRun" }
if ($lowBudget -ne 5) { throw "Expected POST_TERMINATE_LOW_BUDGET_REMAINING=5. got $lowBudget" }
if ($highState -ne $taskStateTerminated) { throw "Expected POST_TERMINATE_HIGH_STATE=4. got $highState" }

Write-Output 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_FAILOVER_PROBE=pass'
Write-Output "POST_TERMINATE_TASK_COUNT=$taskCount"
Write-Output "POST_TERMINATE_RUNNING_SLOT=$runningSlot"
Write-Output "POST_TERMINATE_LOW_RUN=$lowRun"
Write-Output "POST_TERMINATE_LOW_BUDGET_REMAINING=$lowBudget"
Write-Output "POST_TERMINATE_HIGH_STATE=$highState"
