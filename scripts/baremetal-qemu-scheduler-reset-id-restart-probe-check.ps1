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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_ID_RESTART_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_ID_RESTART_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-reset-probe-check.ps1' `
    -FailureLabel 'scheduler-reset'
$probeText = $probeState.Text

$postResetNextTaskId = Extract-IntValue -Text $probeText -Name 'POST_RESET_NEXT_TASK_ID'
$postCreateTaskId = Extract-IntValue -Text $probeText -Name 'POST_CREATE_TASK0_ID'
$nextTaskId = Extract-IntValue -Text $probeText -Name 'NEXT_TASK_ID'

if ($null -in @($postResetNextTaskId, $postCreateTaskId, $nextTaskId)) {
    throw 'Missing expected task-id restart fields in scheduler-reset probe output.'
}
if ($postResetNextTaskId -ne 1) { throw "Expected POST_RESET_NEXT_TASK_ID=1. got $postResetNextTaskId" }
if ($postCreateTaskId -ne 1) { throw "Expected POST_CREATE_TASK0_ID=1. got $postCreateTaskId" }
if ($nextTaskId -ne 2) { throw "Expected NEXT_TASK_ID=2. got $nextTaskId" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_ID_RESTART_PROBE=pass'
Write-Output "POST_RESET_NEXT_TASK_ID=$postResetNextTaskId"
Write-Output "POST_CREATE_TASK0_ID=$postCreateTaskId"
Write-Output "NEXT_TASK_ID=$nextTaskId"
