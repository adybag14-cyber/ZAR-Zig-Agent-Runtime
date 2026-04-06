# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-task-lifecycle-probe-check.ps1"
$taskStateReady = 1
$wakeReasonManual = 3
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TASK_LIFECYCLE_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAKE1_MANUAL_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAKE1_MANUAL_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-lifecycle-probe-check.ps1' `
    -FailureLabel 'task-lifecycle'
$probeText = $probeState.Text


$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_LIFECYCLE_TASK_ID'
$wake1QueueLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAKE1_QUEUE_LEN'
$wake1State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAKE1_STATE'
$wake1Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAKE1_REASON'
$wake1TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAKE1_TASK_ID'

if ($null -in @($taskId, $wake1QueueLen, $wake1State, $wake1Reason, $wake1TaskId)) {
    throw 'Missing expected wake1 fields in task-lifecycle probe output.'
}
if ($wake1QueueLen -ne 1) { throw "Expected WAKE1_QUEUE_LEN=1. got $wake1QueueLen" }
if ($wake1State -ne $taskStateReady) { throw "Expected WAKE1_STATE=$taskStateReady. got $wake1State" }
if ($wake1Reason -ne $wakeReasonManual) { throw "Expected WAKE1_REASON=$wakeReasonManual. got $wake1Reason" }
if ($wake1TaskId -ne $taskId) { throw "Expected WAKE1_TASK_ID=$taskId. got $wake1TaskId" }

Write-Output 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAKE1_MANUAL_PROBE=pass'
Write-Output "BAREMETAL_QEMU_TASK_LIFECYCLE_WAKE1_QUEUE_LEN=$wake1QueueLen"
Write-Output "BAREMETAL_QEMU_TASK_LIFECYCLE_WAKE1_STATE=$wake1State"
Write-Output "BAREMETAL_QEMU_TASK_LIFECYCLE_WAKE1_REASON=$wake1Reason"
Write-Output "BAREMETAL_QEMU_TASK_LIFECYCLE_WAKE1_TASK_ID=$wake1TaskId"
