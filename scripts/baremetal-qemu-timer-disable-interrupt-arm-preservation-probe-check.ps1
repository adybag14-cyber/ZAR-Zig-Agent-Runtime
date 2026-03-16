# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 40,
    [int] $GdbPort = 1439
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-disable-interrupt-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$probeOutput = & $probe @invoke 2>&1
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_ARM_PRESERVATION_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_ARM_PRESERVATION_PROBE_SOURCE=baremetal-qemu-timer-disable-interrupt-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-disable interrupt probe failed with exit code $probeExitCode"
}

$timerTaskId = Extract-IntValue -Text $probeText -Name 'TIMER_TASK_ID'
$timer0Id = Extract-IntValue -Text $probeText -Name 'TIMER0_ID'
$timer0TaskId = Extract-IntValue -Text $probeText -Name 'TIMER0_TASK_ID'
$afterInterruptTimerCount = Extract-IntValue -Text $probeText -Name 'AFTER_INTERRUPT_TIMER_COUNT'
$afterInterruptPendingWakeCount = Extract-IntValue -Text $probeText -Name 'AFTER_INTERRUPT_PENDING_WAKE_COUNT'
$afterInterruptWakeQueueCount = Extract-IntValue -Text $probeText -Name 'AFTER_INTERRUPT_WAKE_QUEUE_COUNT'
$afterInterruptInterruptTaskState = Extract-IntValue -Text $probeText -Name 'AFTER_INTERRUPT_INTERRUPT_TASK_STATE'
$afterInterruptTimerTaskState = Extract-IntValue -Text $probeText -Name 'AFTER_INTERRUPT_TIMER_TASK_STATE'

if ($null -in @($timerTaskId, $timer0Id, $timer0TaskId, $afterInterruptTimerCount, $afterInterruptPendingWakeCount, $afterInterruptWakeQueueCount, $afterInterruptInterruptTaskState, $afterInterruptTimerTaskState)) {
    throw 'Missing expected timer-disable arm-preservation fields in probe output.'
}
if ($timerTaskId -le 0) { throw "Expected TIMER_TASK_ID > 0, got $timerTaskId" }
if ($timer0Id -le 0) { throw "Expected TIMER0_ID > 0, got $timer0Id" }
if ($timer0TaskId -ne $timerTaskId) { throw "Expected TIMER0_TASK_ID=$timerTaskId, got $timer0TaskId" }
if ($afterInterruptTimerCount -ne 1) { throw "Expected AFTER_INTERRUPT_TIMER_COUNT=1, got $afterInterruptTimerCount" }
if ($afterInterruptPendingWakeCount -ne 1) { throw "Expected AFTER_INTERRUPT_PENDING_WAKE_COUNT=1, got $afterInterruptPendingWakeCount" }
if ($afterInterruptWakeQueueCount -ne 1) { throw "Expected AFTER_INTERRUPT_WAKE_QUEUE_COUNT=1, got $afterInterruptWakeQueueCount" }
if ($afterInterruptInterruptTaskState -ne 1) { throw "Expected AFTER_INTERRUPT_INTERRUPT_TASK_STATE=1, got $afterInterruptInterruptTaskState" }
if ($afterInterruptTimerTaskState -ne 6) { throw "Expected AFTER_INTERRUPT_TIMER_TASK_STATE=6, got $afterInterruptTimerTaskState" }

Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_ARM_PRESERVATION_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_ARM_PRESERVATION_PROBE_SOURCE=baremetal-qemu-timer-disable-interrupt-probe-check.ps1'
Write-Output "TIMER_TASK_ID=$timerTaskId"
Write-Output "TIMER0_ID=$timer0Id"
Write-Output "TIMER0_TASK_ID=$timer0TaskId"
Write-Output "AFTER_INTERRUPT_TIMER_COUNT=$afterInterruptTimerCount"
Write-Output "AFTER_INTERRUPT_PENDING_WAKE_COUNT=$afterInterruptPendingWakeCount"
