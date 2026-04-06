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
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_PRESSURE_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TIMER_PRESSURE_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-timer-pressure-probe-check.ps1' `
    -FailureLabel 'timer-pressure'
$probeText = $probeState.Text


$taskCapacity = Extract-IntValue -Text $probeText -Name 'TASK_CAPACITY'
$fullTaskCount = Extract-IntValue -Text $probeText -Name 'FULL_TASK_COUNT'
$fullTimerCount = Extract-IntValue -Text $probeText -Name 'FULL_TIMER_COUNT'
$firstTimerId = Extract-IntValue -Text $probeText -Name 'FIRST_TIMER_ID'
$lastTimerId = Extract-IntValue -Text $probeText -Name 'LAST_TIMER_ID'
$nextTimerIdAfterFull = Extract-IntValue -Text $probeText -Name 'NEXT_TIMER_ID_AFTER_FULL'
if ($null -in @($taskCapacity,$fullTaskCount,$fullTimerCount,$firstTimerId,$lastTimerId,$nextTimerIdAfterFull)) {
    throw 'Missing timer-pressure baseline fields.'
}
if ($fullTaskCount -ne $taskCapacity) { throw "Expected FULL_TASK_COUNT=$taskCapacity. got $fullTaskCount" }
if ($fullTimerCount -ne $taskCapacity) { throw "Expected FULL_TIMER_COUNT=$taskCapacity. got $fullTimerCount" }
if ($firstTimerId -ne 1) { throw "Expected FIRST_TIMER_ID=1. got $firstTimerId" }
if ($lastTimerId -ne $taskCapacity) { throw "Expected LAST_TIMER_ID=$taskCapacity. got $lastTimerId" }
if ($nextTimerIdAfterFull -ne ($taskCapacity + 1)) { throw "Expected NEXT_TIMER_ID_AFTER_FULL=$($taskCapacity + 1). got $nextTimerIdAfterFull" }

Write-Output 'BAREMETAL_QEMU_TIMER_PRESSURE_BASELINE_PROBE=pass'
Write-Output "TASK_CAPACITY=$taskCapacity"
Write-Output "FULL_TASK_COUNT=$fullTaskCount"
Write-Output "FULL_TIMER_COUNT=$fullTimerCount"
Write-Output "FIRST_TIMER_ID=$firstTimerId"
Write-Output "LAST_TIMER_ID=$lastTimerId"
Write-Output "NEXT_TIMER_ID_AFTER_FULL=$nextTimerIdAfterFull"
