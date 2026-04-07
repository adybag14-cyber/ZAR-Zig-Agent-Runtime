# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_TASK_SHAPE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_TASK_SHAPE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-probe-check.ps1' `
    -FailureLabel 'scheduler'
$probeText = $probeState.Text

$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_TASK0_ID'
$taskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_TASK0_STATE'
$taskPriority = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_TASK0_PRIORITY'
$taskBudget = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_TASK0_BUDGET'

if ($null -in @($taskId, $taskState, $taskPriority, $taskBudget)) {
    throw 'Missing expected scheduler task-shape fields in probe output.'
}
if ($taskId -ne 1) { throw "Expected TASK0_ID=1. got $taskId" }
if ($taskState -ne 1) { throw "Expected TASK0_STATE=1. got $taskState" }
if ($taskPriority -ne 5) { throw "Expected TASK0_PRIORITY=5. got $taskPriority" }
if ($taskBudget -ne 12) { throw "Expected TASK0_BUDGET=12. got $taskBudget" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_TASK_SHAPE_PROBE=pass'
Write-Output "TASK0_ID=$taskId"
Write-Output "TASK0_STATE=$taskState"
Write-Output "TASK0_PRIORITY=$taskPriority"
Write-Output "TASK0_BUDGET=$taskBudget"
