# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-task-resume-interrupt-timeout-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_READY_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_READY_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-resume-interrupt-timeout-probe-check.ps1' `
    -FailureLabel 'task-resume interrupt-timeout' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$schedTaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_SCHED_TASK_COUNT'
$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_TASK0_ID'
$taskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_TASK0_STATE'
$taskPriority = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_TASK0_PRIORITY'
$taskRunCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_TASK0_RUN_COUNT'
$taskBudget = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_TASK0_BUDGET'
$taskBudgetRemaining = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_TASK0_BUDGET_REMAINING'
$timerEnabled = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_TIMER_ENABLED'

if ($null -in @($schedTaskCount, $taskId, $taskState, $taskPriority, $taskRunCount, $taskBudget, $taskBudgetRemaining, $timerEnabled)) {
    throw 'Missing expected task-resume interrupt-timeout ready-state fields in probe output.'
}
if ($schedTaskCount -ne 1) { throw "Expected SCHED_TASK_COUNT=1. got $schedTaskCount" }
if ($taskId -le 0) { throw "Expected TASK0_ID>0. got $taskId" }
if ($taskState -ne 1) { throw "Expected TASK0_STATE=1. got $taskState" }
if ($taskPriority -ne 0) { throw "Expected TASK0_PRIORITY=0. got $taskPriority" }
if ($taskRunCount -ne 0) { throw "Expected TASK0_RUN_COUNT=0. got $taskRunCount" }
if ($taskBudget -ne 5) { throw "Expected TASK0_BUDGET=5. got $taskBudget" }
if ($taskBudgetRemaining -ne 5) { throw "Expected TASK0_BUDGET_REMAINING=5. got $taskBudgetRemaining" }
if ($timerEnabled -ne 1) { throw "Expected TIMER_ENABLED=1. got $timerEnabled" }

Write-Output 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_READY_STATE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_READY_STATE_PROBE_SOURCE=baremetal-qemu-task-resume-interrupt-timeout-probe-check.ps1'
Write-Output "SCHED_TASK_COUNT=$schedTaskCount"
Write-Output "TASK0_ID=$taskId"
Write-Output "TASK0_STATE=$taskState"
Write-Output "TASK0_PRIORITY=$taskPriority"
Write-Output "TASK0_RUN_COUNT=$taskRunCount"
Write-Output "TASK0_BUDGET=$taskBudget"
Write-Output "TASK0_BUDGET_REMAINING=$taskBudgetRemaining"
Write-Output "TIMER_ENABLED=$timerEnabled"
