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
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_PRESSURE_REUSE_SLOT_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TIMER_PRESSURE_REUSE_SLOT_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-timer-pressure-probe-check.ps1' `
    -FailureLabel 'timer-pressure'
$probeText = $probeState.Text


$taskCapacity = Extract-IntValue -Text $probeText -Name 'TASK_CAPACITY'
$currentTimerCount = Extract-IntValue -Text $probeText -Name 'CURRENT_TIMER_COUNT'
$reuseTaskId = Extract-IntValue -Text $probeText -Name 'REUSE_TASK_ID'
$reuseNewTimerId = Extract-IntValue -Text $probeText -Name 'REUSE_NEW_TIMER_ID'
$nextTimerIdAfterReuse = Extract-IntValue -Text $probeText -Name 'NEXT_TIMER_ID_AFTER_REUSE'
$reuseState = Extract-IntValue -Text $probeText -Name 'REUSE_STATE'
$reuseEntryTaskId = Extract-IntValue -Text $probeText -Name 'REUSE_ENTRY_TASK_ID'
if ($null -in @($taskCapacity,$currentTimerCount,$reuseTaskId,$reuseNewTimerId,$nextTimerIdAfterReuse,$reuseState,$reuseEntryTaskId)) {
    throw 'Missing timer-pressure reuse-slot fields.'
}
if ($currentTimerCount -ne $taskCapacity) { throw "Expected CURRENT_TIMER_COUNT=$taskCapacity. got $currentTimerCount" }
if ($reuseNewTimerId -ne ($taskCapacity + 1)) { throw "Expected REUSE_NEW_TIMER_ID=$($taskCapacity + 1). got $reuseNewTimerId" }
if ($nextTimerIdAfterReuse -ne ($taskCapacity + 2)) { throw "Expected NEXT_TIMER_ID_AFTER_REUSE=$($taskCapacity + 2). got $nextTimerIdAfterReuse" }
if ($reuseState -ne 1) { throw "Expected REUSE_STATE=1. got $reuseState" }
if ($reuseEntryTaskId -ne $reuseTaskId) { throw "Expected REUSE_ENTRY_TASK_ID=$reuseTaskId. got $reuseEntryTaskId" }

Write-Output 'BAREMETAL_QEMU_TIMER_PRESSURE_REUSE_SLOT_PROBE=pass'
Write-Output "CURRENT_TIMER_COUNT=$currentTimerCount"
Write-Output "REUSE_TASK_ID=$reuseTaskId"
Write-Output "REUSE_NEW_TIMER_ID=$reuseNewTimerId"
Write-Output "NEXT_TIMER_ID_AFTER_REUSE=$nextTimerIdAfterReuse"
Write-Output "REUSE_STATE=$reuseState"
Write-Output "REUSE_ENTRY_TASK_ID=$reuseEntryTaskId"
