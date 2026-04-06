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
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_MANUAL_WAKE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_MANUAL_WAKE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-resume-interrupt-timeout-probe-check.ps1' `
    -FailureLabel 'task-resume interrupt-timeout' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

    throw "Underlying task-resume interrupt-timeout probe failed with exit code $probeExitCode"
}

$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_TASK0_ID'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_WAKE_QUEUE_COUNT'
$wakeTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_WAKE0_TASK_ID'
$wakeTimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_WAKE0_TIMER_ID'
$wakeReason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_WAKE0_REASON'
$wakeVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_WAKE0_VECTOR'
$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_INTERRUPT_COUNT'
$timerLastInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_TIMER_LAST_INTERRUPT_COUNT'
$lastInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_PROBE_LAST_INTERRUPT_VECTOR'

if ($null -in @($taskId, $wakeQueueCount, $wakeTaskId, $wakeTimerId, $wakeReason, $wakeVector, $interruptCount, $timerLastInterruptCount, $lastInterruptVector)) {
    throw 'Missing expected task-resume interrupt-timeout manual-wake fields in probe output.'
}
if ($taskId -le 0) { throw "Expected TASK0_ID>0. got $taskId" }
if ($wakeQueueCount -ne 1) { throw "Expected WAKE_QUEUE_COUNT=1. got $wakeQueueCount" }
if ($wakeTaskId -ne $taskId) { throw "Expected WAKE0_TASK_ID=$taskId. got $wakeTaskId" }
if ($wakeTimerId -ne 0) { throw "Expected WAKE0_TIMER_ID=0 for manual wake. got $wakeTimerId" }
if ($wakeReason -ne 3) { throw "Expected WAKE0_REASON=3 for manual wake. got $wakeReason" }
if ($wakeVector -ne 0) { throw "Expected WAKE0_VECTOR=0 for manual wake. got $wakeVector" }
if ($interruptCount -ne 0) { throw "Expected INTERRUPT_COUNT=0. got $interruptCount" }
if ($timerLastInterruptCount -ne 0) { throw "Expected TIMER_LAST_INTERRUPT_COUNT=0. got $timerLastInterruptCount" }
if ($lastInterruptVector -ne 0) { throw "Expected LAST_INTERRUPT_VECTOR=0. got $lastInterruptVector" }

Write-Output 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_MANUAL_WAKE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TASK_RESUME_INTERRUPT_TIMEOUT_MANUAL_WAKE_PROBE_SOURCE=baremetal-qemu-task-resume-interrupt-timeout-probe-check.ps1'
Write-Output "TASK0_ID=$taskId"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
Write-Output "WAKE0_TASK_ID=$wakeTaskId"
Write-Output "WAKE0_TIMER_ID=$wakeTimerId"
Write-Output "WAKE0_REASON=$wakeReason"
Write-Output "WAKE0_VECTOR=$wakeVector"
Write-Output "INTERRUPT_COUNT=$interruptCount"
Write-Output "TIMER_LAST_INTERRUPT_COUNT=$timerLastInterruptCount"
Write-Output "LAST_INTERRUPT_VECTOR=$lastInterruptVector"
