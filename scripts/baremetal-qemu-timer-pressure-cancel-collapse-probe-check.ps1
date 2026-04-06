# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-pressure-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TIMER_PRESSURE_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_PRESSURE_CANCEL_COLLAPSE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TIMER_PRESSURE_CANCEL_COLLAPSE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-timer-pressure-probe-check.ps1' `
    -FailureLabel 'timer-pressure'
$probeText = $probeState.Text


$taskCapacity = Extract-IntValue -Text $probeText -Name 'TASK_CAPACITY'
$reuseSlotIndex = Extract-IntValue -Text $probeText -Name 'REUSE_SLOT_INDEX'
$reuseTaskId = Extract-IntValue -Text $probeText -Name 'REUSE_TASK_ID'
$reuseOldTimerId = Extract-IntValue -Text $probeText -Name 'REUSE_OLD_TIMER_ID'
$cancelTimerCount = Extract-IntValue -Text $probeText -Name 'CANCEL_TIMER_COUNT'
$reuseCanceledState = Extract-IntValue -Text $probeText -Name 'REUSE_CANCELED_STATE'
$cancelNextTimerId = Extract-IntValue -Text $probeText -Name 'CANCEL_NEXT_TIMER_ID'
$cancelTaskState = Extract-IntValue -Text $probeText -Name 'CANCEL_TASK_STATE'
if ($null -in @($taskCapacity,$reuseSlotIndex,$reuseTaskId,$reuseOldTimerId,$cancelTimerCount,$reuseCanceledState,$cancelNextTimerId,$cancelTaskState)) {
    throw 'Missing timer-pressure cancel-collapse fields.'
}
if ($reuseTaskId -le 0) { throw "Expected REUSE_TASK_ID>0. got $reuseTaskId" }
if ($reuseOldTimerId -ne ($reuseSlotIndex + 1)) { throw "Expected REUSE_OLD_TIMER_ID=$($reuseSlotIndex + 1). got $reuseOldTimerId" }
if ($cancelTimerCount -ne ($taskCapacity - 1)) { throw "Expected CANCEL_TIMER_COUNT=$($taskCapacity - 1). got $cancelTimerCount" }
if ($reuseCanceledState -ne 3) { throw "Expected REUSE_CANCELED_STATE=3. got $reuseCanceledState" }
if ($cancelNextTimerId -ne ($taskCapacity + 1)) { throw "Expected CANCEL_NEXT_TIMER_ID=$($taskCapacity + 1). got $cancelNextTimerId" }
if ($cancelTaskState -ne 6) { throw "Expected CANCEL_TASK_STATE=6. got $cancelTaskState" }

Write-Output 'BAREMETAL_QEMU_TIMER_PRESSURE_CANCEL_COLLAPSE_PROBE=pass'
Write-Output "REUSE_SLOT_INDEX=$reuseSlotIndex"
Write-Output "REUSE_TASK_ID=$reuseTaskId"
Write-Output "REUSE_OLD_TIMER_ID=$reuseOldTimerId"
Write-Output "CANCEL_TIMER_COUNT=$cancelTimerCount"
Write-Output "REUSE_CANCELED_STATE=$reuseCanceledState"
Write-Output "CANCEL_NEXT_TIMER_ID=$cancelNextTimerId"
Write-Output "CANCEL_TASK_STATE=$cancelTaskState"
