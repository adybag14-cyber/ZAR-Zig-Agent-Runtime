# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-wake-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_TIMER_WAKE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_TIMER_WAKE_TIMER_TELEMETRY_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-wake probe failed with exit code $probeExitCode"
}

$timerEnabled = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TIMER_ENABLED'
$timerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TIMER_ENTRY_COUNT'
$pendingWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_PENDING_WAKE_COUNT'
$timerDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TIMER_DISPATCH_COUNT'
$timerLastWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TIMER_LAST_WAKE_TICK'
$timerQuantum = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TIMER_QUANTUM'
$timer0Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TIMER0_ID'
$timer0TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TIMER0_TASK_ID'
$timer0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TIMER0_STATE'
$timer0FireCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TIMER0_FIRE_COUNT'
$timer0LastFireTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TIMER0_LAST_FIRE_TICK'

if ($null -in @($timerEnabled, $timerEntryCount, $pendingWakeCount, $timerDispatchCount, $timerLastWakeTick, $timerQuantum, $timer0Id, $timer0TaskId, $timer0State, $timer0FireCount, $timer0LastFireTick)) {
    throw 'Missing expected timer telemetry fields in timer-wake probe output.'
}
if ($timerEnabled -ne 1) { throw "Expected TIMER_ENABLED=1. got $timerEnabled" }
if ($timerEntryCount -ne 0) { throw "Expected TIMER_ENTRY_COUNT=0. got $timerEntryCount" }
if ($pendingWakeCount -lt 1) { throw "Expected PENDING_WAKE_COUNT>=1. got $pendingWakeCount" }
if ($timerDispatchCount -lt 1) { throw "Expected TIMER_DISPATCH_COUNT>=1. got $timerDispatchCount" }
if ($timerLastWakeTick -lt 1) { throw "Expected TIMER_LAST_WAKE_TICK>=1. got $timerLastWakeTick" }
if ($timerQuantum -ne 3) { throw "Expected TIMER_QUANTUM=3. got $timerQuantum" }
if ($timer0Id -ne 1) { throw "Expected TIMER0_ID=1. got $timer0Id" }
if ($timer0TaskId -ne 1) { throw "Expected TIMER0_TASK_ID=1. got $timer0TaskId" }
if ($timer0State -ne 2) { throw "Expected TIMER0_STATE=2. got $timer0State" }
if ($timer0FireCount -lt 1) { throw "Expected TIMER0_FIRE_COUNT>=1. got $timer0FireCount" }
if ($timer0LastFireTick -ne $timerLastWakeTick) { throw "Expected TIMER0_LAST_FIRE_TICK to equal TIMER_LAST_WAKE_TICK. got $timer0LastFireTick vs $timerLastWakeTick" }

Write-Output 'BAREMETAL_QEMU_TIMER_WAKE_TIMER_TELEMETRY_PROBE=pass'
Write-Output "TIMER_ENABLED=$timerEnabled"
Write-Output "TIMER_ENTRY_COUNT=$timerEntryCount"
Write-Output "PENDING_WAKE_COUNT=$pendingWakeCount"
Write-Output "TIMER_DISPATCH_COUNT=$timerDispatchCount"
Write-Output "TIMER_LAST_WAKE_TICK=$timerLastWakeTick"
Write-Output "TIMER_QUANTUM=$timerQuantum"
Write-Output "TIMER0_ID=$timer0Id"
Write-Output "TIMER0_TASK_ID=$timer0TaskId"
Write-Output "TIMER0_STATE=$timer0State"
Write-Output "TIMER0_FIRE_COUNT=$timer0FireCount"
Write-Output "TIMER0_LAST_FIRE_TICK=$timer0LastFireTick"
