# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-reset-probe-check.ps1"
$schedulerNoSlot = 255
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_RESET_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_COLLAPSE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_COLLAPSE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-reset-probe-check.ps1' `
    -FailureLabel 'scheduler-reset'
$probeText = $probeState.Text

$enabled = Extract-IntValue -Text $probeText -Name 'POST_RESET_ENABLED'
$taskCount = Extract-IntValue -Text $probeText -Name 'POST_RESET_TASK_COUNT'
$runningSlot = Extract-IntValue -Text $probeText -Name 'POST_RESET_RUNNING_SLOT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'POST_RESET_DISPATCH_COUNT'
$taskId = Extract-IntValue -Text $probeText -Name 'POST_RESET_TASK0_ID'

if ($null -in @($enabled, $taskCount, $runningSlot, $dispatchCount, $taskId)) {
    throw 'Missing expected collapse fields in scheduler-reset probe output.'
}
if ($enabled -ne 0) { throw "Expected POST_RESET_ENABLED=0. got $enabled" }
if ($taskCount -ne 0) { throw "Expected POST_RESET_TASK_COUNT=0. got $taskCount" }
if ($runningSlot -ne $schedulerNoSlot) { throw "Expected POST_RESET_RUNNING_SLOT=255. got $runningSlot" }
if ($dispatchCount -ne 0) { throw "Expected POST_RESET_DISPATCH_COUNT=0. got $dispatchCount" }
if ($taskId -ne 0) { throw "Expected POST_RESET_TASK0_ID=0. got $taskId" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_COLLAPSE_PROBE=pass'
Write-Output "POST_RESET_ENABLED=$enabled"
Write-Output "POST_RESET_TASK_COUNT=$taskCount"
Write-Output "POST_RESET_RUNNING_SLOT=$runningSlot"
Write-Output "POST_RESET_DISPATCH_COUNT=$dispatchCount"
Write-Output "POST_RESET_TASK0_ID=$taskId"
