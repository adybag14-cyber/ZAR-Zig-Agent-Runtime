# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-cancel-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TIMER_CANCEL_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_CANCEL_BASELINE_PROBE' `
    -FailureLabel 'timer-cancel' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text
$armedTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_PROBE_ARMED_TICKS'
$preCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_PROBE_PRE_CANCEL_ENTRY_COUNT'
$preTimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_PROBE_PRE_CANCEL_TIMER0_ID'
$preTimerState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_PROBE_PRE_CANCEL_TIMER0_STATE'
$preTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_PROBE_PRE_CANCEL_TIMER0_TASK_ID'
$preNextFire = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_PROBE_PRE_CANCEL_TIMER0_NEXT_FIRE_TICK'

if ($null -in @($armedTicks, $preCount, $preTimerId, $preTimerState, $preTaskId, $preNextFire)) {
    throw 'Missing baseline timer-cancel fields.'
}
if ($preCount -ne 1) { throw "Expected PRE_CANCEL_ENTRY_COUNT=1. got $preCount" }
if ($preTimerId -le 0) { throw "Expected PRE_CANCEL_TIMER0_ID>0. got $preTimerId" }
if ($preTimerState -ne 1) { throw "Expected PRE_CANCEL_TIMER0_STATE=1. got $preTimerState" }
if ($preTaskId -ne 1) { throw "Expected PRE_CANCEL_TIMER0_TASK_ID=1. got $preTaskId" }
if ($preNextFire -le $armedTicks) { throw "Expected PRE_CANCEL_TIMER0_NEXT_FIRE_TICK>$armedTicks. got $preNextFire" }

Write-Output 'BAREMETAL_QEMU_TIMER_CANCEL_BASELINE_PROBE=pass'
Write-Output "ARMED_TICKS=$armedTicks"
Write-Output "PRE_CANCEL_ENTRY_COUNT=$preCount"
Write-Output "PRE_CANCEL_TIMER0_ID=$preTimerId"
Write-Output "PRE_CANCEL_TIMER0_STATE=$preTimerState"
Write-Output "PRE_CANCEL_TIMER0_TASK_ID=$preTaskId"
Write-Output "PRE_CANCEL_TIMER0_NEXT_FIRE_TICK=$preNextFire"
