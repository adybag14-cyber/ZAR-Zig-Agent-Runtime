# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-pressure-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_TIMER_PRESSURE_BASELINE_PROBE=skipped'

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
if ($probeText -match 'BAREMETAL_QEMU_TIMER_PRESSURE_PROBE=skipped') {
    Write-Output $skipToken
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-pressure probe failed with exit code $probeExitCode"
}

$taskCapacity = Extract-IntValue -Text $probeText -Name 'TASK_CAPACITY'
$fullTaskCount = Extract-IntValue -Text $probeText -Name 'FULL_TASK_COUNT'
$fullTimerCount = Extract-IntValue -Text $probeText -Name 'FULL_TIMER_COUNT'
$firstTimerId = Extract-IntValue -Text $probeText -Name 'FIRST_TIMER_ID'
$lastTimerId = Extract-IntValue -Text $probeText -Name 'LAST_TIMER_ID'
$nextTimerIdAfterFull = Extract-IntValue -Text $probeText -Name 'NEXT_TIMER_ID_AFTER_FULL'
if ($null -in @($taskCapacity,$fullTaskCount,$fullTimerCount,$firstTimerId,$lastTimerId,$nextTimerIdAfterFull)) {
    throw 'Missing timer-pressure baseline fields.'
}
if ($fullTaskCount -ne $taskCapacity) { throw "Expected FULL_TASK_COUNT=$taskCapacity. got $fullTaskCount" }
if ($fullTimerCount -ne $taskCapacity) { throw "Expected FULL_TIMER_COUNT=$taskCapacity. got $fullTimerCount" }
if ($firstTimerId -ne 1) { throw "Expected FIRST_TIMER_ID=1. got $firstTimerId" }
if ($lastTimerId -ne $taskCapacity) { throw "Expected LAST_TIMER_ID=$taskCapacity. got $lastTimerId" }
if ($nextTimerIdAfterFull -ne ($taskCapacity + 1)) { throw "Expected NEXT_TIMER_ID_AFTER_FULL=$($taskCapacity + 1). got $nextTimerIdAfterFull" }

Write-Output 'BAREMETAL_QEMU_TIMER_PRESSURE_BASELINE_PROBE=pass'
Write-Output "TASK_CAPACITY=$taskCapacity"
Write-Output "FULL_TASK_COUNT=$fullTaskCount"
Write-Output "FULL_TIMER_COUNT=$fullTimerCount"
Write-Output "FIRST_TIMER_ID=$firstTimerId"
Write-Output "LAST_TIMER_ID=$lastTimerId"
Write-Output "NEXT_TIMER_ID_AFTER_FULL=$nextTimerIdAfterFull"
