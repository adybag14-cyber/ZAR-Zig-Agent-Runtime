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
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_CANCEL_COLLAPSE_PROBE' `
    -FailureLabel 'timer-cancel-task' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
$probeText = $probeState.Text
$cancelTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_CANCEL_TICKS'
$cancelEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_CANCEL_ENTRY_COUNT'
$timerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_TIMER_ENTRY_COUNT'
$pendingWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_PENDING_WAKE_COUNT'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_WAKE_QUEUE_COUNT'

if ($null -in @($cancelTicks, $cancelEntryCount, $timerEntryCount, $pendingWakeCount, $wakeQueueCount)) {
    throw 'Missing collapse timer-cancel-task fields.'
}
if ($cancelTicks -le 0) { throw "Expected CANCEL_TICKS>0. got $cancelTicks" }
if ($cancelEntryCount -ne 0) { throw "Expected CANCEL_ENTRY_COUNT=0. got $cancelEntryCount" }
if ($timerEntryCount -ne 0) { throw "Expected TIMER_ENTRY_COUNT=0. got $timerEntryCount" }
if ($pendingWakeCount -ne 0) { throw "Expected PENDING_WAKE_COUNT=0. got $pendingWakeCount" }
if ($wakeQueueCount -ne 0) { throw "Expected WAKE_QUEUE_COUNT=0. got $wakeQueueCount" }

Write-Output 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_CANCEL_COLLAPSE_PROBE=pass'
Write-Output "CANCEL_TICKS=$cancelTicks"
Write-Output "CANCEL_ENTRY_COUNT=$cancelEntryCount"
Write-Output "TIMER_ENTRY_COUNT=$timerEntryCount"
Write-Output "PENDING_WAKE_COUNT=$pendingWakeCount"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
