# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 40,
    [int] $GdbPort = 1441
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
    Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_DEFERRED_TIMER_WAKE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_DEFERRED_TIMER_WAKE_PROBE_SOURCE=baremetal-qemu-timer-disable-interrupt-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-disable interrupt probe failed with exit code $probeExitCode"
}

$timerTaskId = Extract-IntValue -Text $probeText -Name 'TIMER_TASK_ID'
$timer0Id = Extract-IntValue -Text $probeText -Name 'TIMER0_ID'
$timerEnabled = Extract-IntValue -Text $probeText -Name 'TIMER_ENABLED'
$timerEntryCount = Extract-IntValue -Text $probeText -Name 'TIMER_ENTRY_COUNT'
$timerDispatchCount = Extract-IntValue -Text $probeText -Name 'TIMER_DISPATCH_COUNT'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'WAKE_QUEUE_COUNT'
$wake1TaskId = Extract-IntValue -Text $probeText -Name 'WAKE1_TASK_ID'
$wake1TimerId = Extract-IntValue -Text $probeText -Name 'WAKE1_TIMER_ID'
$wake1Reason = Extract-IntValue -Text $probeText -Name 'WAKE1_REASON'
$wake1Vector = Extract-IntValue -Text $probeText -Name 'WAKE1_VECTOR'
$wake1Tick = Extract-IntValue -Text $probeText -Name 'WAKE1_TICK'
$timer0LastFireTick = Extract-IntValue -Text $probeText -Name 'TIMER0_LAST_FIRE_TICK'

if ($null -in @($timerTaskId, $timer0Id, $timerEnabled, $timerEntryCount, $timerDispatchCount, $wakeQueueCount, $wake1TaskId, $wake1TimerId, $wake1Reason, $wake1Vector, $wake1Tick, $timer0LastFireTick)) {
    throw 'Missing expected timer-disable deferred-timer-wake fields in probe output.'
}
if ($timerTaskId -le 0) { throw "Expected TIMER_TASK_ID > 0, got $timerTaskId" }
if ($timer0Id -le 0) { throw "Expected TIMER0_ID > 0, got $timer0Id" }
if ($timerEnabled -ne 1) { throw "Expected TIMER_ENABLED=1, got $timerEnabled" }
if ($timerEntryCount -ne 0) { throw "Expected TIMER_ENTRY_COUNT=0, got $timerEntryCount" }
if ($timerDispatchCount -ne 1) { throw "Expected TIMER_DISPATCH_COUNT=1, got $timerDispatchCount" }
if ($wakeQueueCount -ne 2) { throw "Expected WAKE_QUEUE_COUNT=2, got $wakeQueueCount" }
if ($wake1TaskId -ne $timerTaskId) { throw "Expected WAKE1_TASK_ID=$timerTaskId, got $wake1TaskId" }
if ($wake1TimerId -ne $timer0Id) { throw "Expected WAKE1_TIMER_ID=$timer0Id, got $wake1TimerId" }
if ($wake1Reason -ne 1) { throw "Expected WAKE1_REASON=1, got $wake1Reason" }
if ($wake1Vector -ne 0) { throw "Expected WAKE1_VECTOR=0, got $wake1Vector" }
if ($wake1Tick -ne $timer0LastFireTick) { throw "Expected WAKE1_TICK=$timer0LastFireTick, got $wake1Tick" }

Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_DEFERRED_TIMER_WAKE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_DEFERRED_TIMER_WAKE_PROBE_SOURCE=baremetal-qemu-timer-disable-interrupt-probe-check.ps1'
Write-Output "TIMER_TASK_ID=$timerTaskId"
Write-Output "TIMER0_ID=$timer0Id"
Write-Output "TIMER_DISPATCH_COUNT=$timerDispatchCount"
Write-Output "WAKE1_TASK_ID=$wake1TaskId"
Write-Output "WAKE1_TIMER_ID=$wake1TimerId"
Write-Output "WAKE1_REASON=$wake1Reason"
Write-Output "WAKE1_VECTOR=$wake1Vector"
