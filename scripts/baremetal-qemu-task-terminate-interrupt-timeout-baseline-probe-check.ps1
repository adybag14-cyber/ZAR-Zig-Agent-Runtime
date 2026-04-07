# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-task-terminate-interrupt-timeout-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-terminate-interrupt-timeout-probe-check.ps1' `
    -FailureLabel 'task-terminate interrupt-timeout' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$preTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_PRE_TICKS'
$preTask0Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_PRE_TASK0_ID'
$preTask0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_PRE_TASK0_STATE'
$preWaitKind0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_PRE_WAIT_KIND0'
$preWaitVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_PRE_WAIT_VECTOR0'
$preWaitTimeout0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_PRE_WAIT_TIMEOUT0'
$preTimerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_PRE_TIMER_ENTRY_COUNT'
$preTimerPendingWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_PRE_TIMER_PENDING_WAKE_COUNT'
$preTimerNextTimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_PRE_TIMER_NEXT_TIMER_ID'
$preWakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_PRE_WAKE_QUEUE_COUNT'

if ($null -in @($preTicks, $preTask0Id, $preTask0State, $preWaitKind0, $preWaitVector0, $preWaitTimeout0, $preTimerEntryCount, $preTimerPendingWakeCount, $preTimerNextTimerId, $preWakeQueueCount)) {
    throw 'Missing expected baseline fields in task-terminate interrupt-timeout probe output.'
}
if ($preTask0Id -le 0) { throw "Expected PRE_TASK0_ID>0. got $preTask0Id" }
if ($preTask0State -ne 6) { throw "Expected PRE_TASK0_STATE=6. got $preTask0State" }
if ($preWaitKind0 -ne 3) { throw "Expected PRE_WAIT_KIND0=3. got $preWaitKind0" }
if ($preWaitVector0 -ne 0) { throw "Expected PRE_WAIT_VECTOR0=0. got $preWaitVector0" }
if ($preWaitTimeout0 -le $preTicks) { throw "Expected PRE_WAIT_TIMEOUT0 > PRE_TICKS. got timeout=$preWaitTimeout0 ticks=$preTicks" }
if ($preTimerEntryCount -ne 0) { throw "Expected PRE_TIMER_ENTRY_COUNT=0. got $preTimerEntryCount" }
if ($preTimerPendingWakeCount -ne 0) { throw "Expected PRE_TIMER_PENDING_WAKE_COUNT=0. got $preTimerPendingWakeCount" }
if ($preTimerNextTimerId -ne 1) { throw "Expected PRE_TIMER_NEXT_TIMER_ID=1. got $preTimerNextTimerId" }
if ($preWakeQueueCount -ne 0) { throw "Expected PRE_WAKE_QUEUE_COUNT=0. got $preWakeQueueCount" }

Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_BASELINE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_BASELINE_PROBE_SOURCE=baremetal-qemu-task-terminate-interrupt-timeout-probe-check.ps1'
Write-Output "PRE_TICKS=$preTicks"
Write-Output "PRE_TASK0_ID=$preTask0Id"
Write-Output "PRE_TASK0_STATE=$preTask0State"
Write-Output "PRE_WAIT_KIND0=$preWaitKind0"
Write-Output "PRE_WAIT_VECTOR0=$preWaitVector0"
Write-Output "PRE_WAIT_TIMEOUT0=$preWaitTimeout0"
Write-Output "PRE_TIMER_ENTRY_COUNT=$preTimerEntryCount"
Write-Output "PRE_TIMER_PENDING_WAKE_COUNT=$preTimerPendingWakeCount"
Write-Output "PRE_TIMER_NEXT_TIMER_ID=$preTimerNextTimerId"
Write-Output "PRE_WAKE_QUEUE_COUNT=$preWakeQueueCount"
