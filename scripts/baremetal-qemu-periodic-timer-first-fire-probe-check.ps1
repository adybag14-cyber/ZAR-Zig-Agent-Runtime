# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_FIRST_FIRE_PROBE_CHECK=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying periodic-timer probe failed with exit code $probeExitCode"
}

$firstFireCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_FIRST_FIRE_COUNT'
$firstDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_FIRST_DISPATCH_COUNT'
$firstWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_FIRST_WAKE_COUNT'
$firstLastFireTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_FIRST_LAST_FIRE_TICK'
$wake0Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE0_SEQ'
$wake0TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE0_TASK_ID'
$wake0TimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE0_TIMER_ID'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE0_REASON'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE0_VECTOR'
$wake0Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE0_TICK'
if ($null -in @($firstFireCount, $firstDispatchCount, $firstWakeCount, $firstLastFireTick, $wake0Seq, $wake0TaskId, $wake0TimerId, $wake0Reason, $wake0Vector, $wake0Tick)) { throw 'Missing periodic-timer first-fire fields.' }
if ($firstFireCount -ne 1) { throw "Expected FIRST_FIRE_COUNT=1. got $firstFireCount" }
if ($firstDispatchCount -ne 1) { throw "Expected FIRST_DISPATCH_COUNT=1. got $firstDispatchCount" }
if ($firstWakeCount -ne 1) { throw "Expected FIRST_WAKE_COUNT=1. got $firstWakeCount" }
if ($firstLastFireTick -ne 8) { throw "Expected FIRST_LAST_FIRE_TICK=8. got $firstLastFireTick" }
if ($wake0Seq -ne 1) { throw "Expected WAKE0_SEQ=1. got $wake0Seq" }
if ($wake0TaskId -ne 1) { throw "Expected WAKE0_TASK_ID=1. got $wake0TaskId" }
if ($wake0TimerId -ne 1) { throw "Expected WAKE0_TIMER_ID=1. got $wake0TimerId" }
if ($wake0Reason -ne 1) { throw "Expected WAKE0_REASON=1. got $wake0Reason" }
if ($wake0Vector -ne 0) { throw "Expected WAKE0_VECTOR=0. got $wake0Vector" }
if ($wake0Tick -ne 8) { throw "Expected WAKE0_TICK=8. got $wake0Tick" }
Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_FIRST_FIRE_PROBE=pass'
Write-Output "FIRST_FIRE_COUNT=$firstFireCount"
Write-Output "FIRST_DISPATCH_COUNT=$firstDispatchCount"
Write-Output "FIRST_WAKE_COUNT=$firstWakeCount"
Write-Output "FIRST_LAST_FIRE_TICK=$firstLastFireTick"
Write-Output "WAKE0_SEQ=$wake0Seq"
Write-Output "WAKE0_TASK_ID=$wake0TaskId"
Write-Output "WAKE0_TIMER_ID=$wake0TimerId"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
Write-Output "WAKE0_TICK=$wake0Tick"
