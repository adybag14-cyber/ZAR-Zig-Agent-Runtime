# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-cancel-task-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_ZERO_WAKE_TELEMETRY_PROBE' `
    -FailureLabel 'timer-cancel-task' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
$probeText = $probeState.Text
$timerEnabled = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_TIMER_ENABLED'
$timerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_TIMER_ENTRY_COUNT'
$pendingWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_PENDING_WAKE_COUNT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_TIMER_DISPATCH_COUNT'
$lastWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_TIMER_LAST_WAKE_TICK'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_WAKE_QUEUE_COUNT'

if ($null -in @($timerEnabled, $timerEntryCount, $pendingWakeCount, $dispatchCount, $lastWakeTick, $wakeQueueCount)) {
    throw 'Missing zero-wake telemetry timer-cancel-task fields.'
}
if ($timerEnabled -ne 1) { throw "Expected TIMER_ENABLED=1. got $timerEnabled" }
if ($timerEntryCount -ne 0) { throw "Expected TIMER_ENTRY_COUNT=0. got $timerEntryCount" }
if ($pendingWakeCount -ne 0) { throw "Expected PENDING_WAKE_COUNT=0. got $pendingWakeCount" }
if ($dispatchCount -ne 0) { throw "Expected TIMER_DISPATCH_COUNT=0. got $dispatchCount" }
if ($lastWakeTick -ne 0) { throw "Expected TIMER_LAST_WAKE_TICK=0. got $lastWakeTick" }
if ($wakeQueueCount -ne 0) { throw "Expected WAKE_QUEUE_COUNT=0. got $wakeQueueCount" }

Write-Output 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_ZERO_WAKE_TELEMETRY_PROBE=pass'
Write-Output "TIMER_ENABLED=$timerEnabled"
Write-Output "TIMER_ENTRY_COUNT=$timerEntryCount"
Write-Output "PENDING_WAKE_COUNT=$pendingWakeCount"
Write-Output "TIMER_DISPATCH_COUNT=$dispatchCount"
Write-Output "TIMER_LAST_WAKE_TICK=$lastWakeTick"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
