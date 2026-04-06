# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-task-lifecycle-probe-check.ps1"
$taskStateWaiting = 6
$expectedPriority = 0
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TASK_LIFECYCLE_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT1_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT1_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-lifecycle-probe-check.ps1' `
    -FailureLabel 'task-lifecycle'
$probeText = $probeState.Text


$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_LIFECYCLE_TASK_ID'
$taskPriority = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_LIFECYCLE_TASK_PRIORITY'
$wait1State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT1_STATE'
$wait1TaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT1_TASK_COUNT'

if ($null -in @($taskId, $taskPriority, $wait1State, $wait1TaskCount)) {
    throw 'Missing expected wait1 baseline fields in task-lifecycle probe output.'
}
if ($taskId -le 0) { throw "Expected TASK_ID > 0. got $taskId" }
if ($taskPriority -ne $expectedPriority) { throw "Expected TASK_PRIORITY=$expectedPriority. got $taskPriority" }
if ($wait1State -ne $taskStateWaiting) { throw "Expected WAIT1_STATE=$taskStateWaiting. got $wait1State" }
if ($wait1TaskCount -ne 0) { throw "Expected WAIT1_TASK_COUNT=0. got $wait1TaskCount" }

Write-Output 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT1_BASELINE_PROBE=pass'
Write-Output "BAREMETAL_QEMU_TASK_LIFECYCLE_TASK_ID=$taskId"
Write-Output "BAREMETAL_QEMU_TASK_LIFECYCLE_TASK_PRIORITY=$taskPriority"
Write-Output "BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT1_STATE=$wait1State"
Write-Output "BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT1_TASK_COUNT=$wait1TaskCount"
