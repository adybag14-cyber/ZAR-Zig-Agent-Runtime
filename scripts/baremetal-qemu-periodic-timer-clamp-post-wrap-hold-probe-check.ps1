# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-clamp-probe-check.ps1"
$maxTick = [uint64]::MaxValue
$taskStateReady = 1
function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\\d+)\\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [decimal]::Parse($match.Groups[1].Value)
}

if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_POST_WRAP_HOLD_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_POST_WRAP_HOLD_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-periodic-timer-clamp-probe-check.ps1' `
    -FailureLabel 'periodic-timer-clamp'
$probeText = $probeState.Text


$holdTicks = Extract-IntValue -Text $probeText -Name 'HOLD_TICKS'
$holdFireCount = Extract-IntValue -Text $probeText -Name 'HOLD_FIRE_COUNT'
$holdWakeCount = Extract-IntValue -Text $probeText -Name 'HOLD_WAKE_COUNT'
$holdNextFire = Extract-IntValue -Text $probeText -Name 'HOLD_NEXT_FIRE'
$holdTaskState = Extract-IntValue -Text $probeText -Name 'HOLD_TASK_STATE'

if ($null -in @($holdTicks, $holdFireCount, $holdWakeCount, $holdNextFire, $holdTaskState)) {
    throw 'Missing expected post-wrap hold fields in periodic-timer-clamp probe output.'
}
if ($holdTicks -ne 1) { throw "Expected HOLD_TICKS=1. got $holdTicks" }
if ($holdFireCount -ne 1) { throw "Expected HOLD_FIRE_COUNT=1. got $holdFireCount" }
if ($holdWakeCount -ne 1) { throw "Expected HOLD_WAKE_COUNT=1. got $holdWakeCount" }
if ($holdNextFire -ne $maxTick) { throw "Expected HOLD_NEXT_FIRE=$maxTick. got $holdNextFire" }
if ($holdTaskState -ne $taskStateReady) { throw "Expected HOLD_TASK_STATE=$taskStateReady. got $holdTaskState" }

Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_POST_WRAP_HOLD_PROBE=pass'
Write-Output "HOLD_TICKS=$holdTicks"
Write-Output "HOLD_FIRE_COUNT=$holdFireCount"
Write-Output "HOLD_WAKE_COUNT=$holdWakeCount"
Write-Output "HOLD_NEXT_FIRE=$holdNextFire"
Write-Output "HOLD_TASK_STATE=$holdTaskState"
