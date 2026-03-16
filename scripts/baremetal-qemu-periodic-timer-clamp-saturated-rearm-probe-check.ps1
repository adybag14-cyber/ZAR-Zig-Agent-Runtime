# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-clamp-probe-check.ps1"
$maxTick = [uint64]::MaxValue
$timerEntryStateArmed = 1
$timerEntryFlagPeriodic = 1

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [decimal]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_SATURATED_REARM_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying periodic-timer-clamp probe failed with exit code $probeExitCode"
}

$armNextFire = Extract-IntValue -Text $probeText -Name 'ARM_NEXT_FIRE'
$armState = Extract-IntValue -Text $probeText -Name 'ARM_STATE'
$armFlags = Extract-IntValue -Text $probeText -Name 'ARM_FLAGS'
$fireNextFire = Extract-IntValue -Text $probeText -Name 'FIRE_NEXT_FIRE'
$fireState = Extract-IntValue -Text $probeText -Name 'FIRE_STATE'

if ($null -in @($armNextFire, $armState, $armFlags, $fireNextFire, $fireState)) {
    throw 'Missing expected saturated-rearm fields in periodic-timer-clamp probe output.'
}
if ($armNextFire -ne $maxTick) { throw "Expected ARM_NEXT_FIRE=$maxTick. got $armNextFire" }
if ($armState -ne $timerEntryStateArmed) { throw "Expected ARM_STATE=$timerEntryStateArmed. got $armState" }
if (($armFlags -band $timerEntryFlagPeriodic) -ne $timerEntryFlagPeriodic) { throw "Expected ARM_FLAGS to include periodic bit 1. got $armFlags" }
if ($fireNextFire -ne $maxTick) { throw "Expected FIRE_NEXT_FIRE=$maxTick. got $fireNextFire" }
if ($fireState -ne $timerEntryStateArmed) { throw "Expected FIRE_STATE=$timerEntryStateArmed. got $fireState" }

Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_SATURATED_REARM_PROBE=pass'
Write-Output "ARM_NEXT_FIRE=$armNextFire"
Write-Output "ARM_STATE=$armState"
Write-Output "ARM_FLAGS=$armFlags"
Write-Output "FIRE_NEXT_FIRE=$fireNextFire"
Write-Output "FIRE_STATE=$fireState"
