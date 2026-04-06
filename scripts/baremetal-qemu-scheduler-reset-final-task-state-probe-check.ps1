# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-reset-probe-check.ps1"
$schedulerEnableOpcode = 24
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_RESET_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_FINAL_TASK_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_FINAL_TASK_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-reset-probe-check.ps1' `
    -FailureLabel 'scheduler-reset'
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$enabled = Extract-IntValue -Text $probeText -Name 'ENABLED'
$taskCount = Extract-IntValue -Text $probeText -Name 'TASK_COUNT'
$runningSlot = Extract-IntValue -Text $probeText -Name 'RUNNING_SLOT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'DISPATCH_COUNT'
$taskId = Extract-IntValue -Text $probeText -Name 'TASK0_ID'
$taskState = Extract-IntValue -Text $probeText -Name 'TASK0_STATE'
$taskPriority = Extract-IntValue -Text $probeText -Name 'TASK0_PRIORITY'
$taskRunCount = Extract-IntValue -Text $probeText -Name 'TASK0_RUN_COUNT'
$taskBudget = Extract-IntValue -Text $probeText -Name 'TASK0_BUDGET'
$taskBudgetRemaining = Extract-IntValue -Text $probeText -Name 'TASK0_BUDGET_REMAINING'

if ($null -in @($ack, $lastOpcode, $lastResult, $enabled, $taskCount, $runningSlot, $dispatchCount, $taskId, $taskState, $taskPriority, $taskRunCount, $taskBudget, $taskBudgetRemaining)) {
    throw 'Missing expected final task-state fields in scheduler-reset probe output.'
}
if ($ack -ne 6) { throw "Expected ACK=6. got $ack" }
if ($lastOpcode -ne $schedulerEnableOpcode) { throw "Expected LAST_OPCODE=24. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($enabled -ne 1) { throw "Expected ENABLED=1. got $enabled" }
if ($taskCount -ne 1) { throw "Expected TASK_COUNT=1. got $taskCount" }
if ($runningSlot -ne 0) { throw "Expected RUNNING_SLOT=0. got $runningSlot" }
if ($dispatchCount -ne 1) { throw "Expected DISPATCH_COUNT=1. got $dispatchCount" }
if ($taskId -ne 1) { throw "Expected TASK0_ID=1. got $taskId" }
if ($taskState -ne 1) { throw "Expected TASK0_STATE=1. got $taskState" }
if ($taskPriority -ne 7) { throw "Expected TASK0_PRIORITY=7. got $taskPriority" }
if ($taskRunCount -ne 1) { throw "Expected TASK0_RUN_COUNT=1. got $taskRunCount" }
if ($taskBudget -ne 6) { throw "Expected TASK0_BUDGET=6. got $taskBudget" }
if ($taskBudgetRemaining -ne 5) { throw "Expected TASK0_BUDGET_REMAINING=5. got $taskBudgetRemaining" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_FINAL_TASK_STATE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "ENABLED=$enabled"
Write-Output "TASK_COUNT=$taskCount"
Write-Output "RUNNING_SLOT=$runningSlot"
Write-Output "DISPATCH_COUNT=$dispatchCount"
Write-Output "TASK0_ID=$taskId"
Write-Output "TASK0_STATE=$taskState"
Write-Output "TASK0_PRIORITY=$taskPriority"
Write-Output "TASK0_RUN_COUNT=$taskRunCount"
Write-Output "TASK0_BUDGET=$taskBudget"
Write-Output "TASK0_BUDGET_REMAINING=$taskBudgetRemaining"
