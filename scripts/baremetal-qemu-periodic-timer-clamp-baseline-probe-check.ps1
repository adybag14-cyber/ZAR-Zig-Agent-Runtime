# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-clamp-probe-check.ps1"
$nearMaxTick = [uint64]::MaxValue - 1
$maxTick = [uint64]::MaxValue
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
    -SkippedReceipt 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-periodic-timer-clamp-probe-check.ps1' `
    -FailureLabel 'periodic-timer-clamp'
$probeText = $probeState.Text


$taskId = Extract-IntValue -Text $probeText -Name 'TASK_ID'
$preScheduleTicks = Extract-IntValue -Text $probeText -Name 'PRE_SCHEDULE_TICKS'
$armTicks = Extract-IntValue -Text $probeText -Name 'ARM_TICKS'
$armTimerId = Extract-IntValue -Text $probeText -Name 'ARM_TIMER_ID'

if ($null -in @($taskId, $preScheduleTicks, $armTicks, $armTimerId)) {
    throw 'Missing expected baseline fields in periodic-timer-clamp probe output.'
}
if ($taskId -ne 1) { throw "Expected TASK_ID=1. got $taskId" }
if ($preScheduleTicks -ne $nearMaxTick) { throw "Expected PRE_SCHEDULE_TICKS=$nearMaxTick. got $preScheduleTicks" }
if ($armTicks -ne $maxTick) { throw "Expected ARM_TICKS=$maxTick. got $armTicks" }
if ($armTimerId -ne 1) { throw "Expected ARM_TIMER_ID=1. got $armTimerId" }

Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_BASELINE_PROBE=pass'
Write-Output "TASK_ID=$taskId"
Write-Output "PRE_SCHEDULE_TICKS=$preScheduleTicks"
Write-Output "ARM_TICKS=$armTicks"
Write-Output "ARM_TIMER_ID=$armTimerId"
