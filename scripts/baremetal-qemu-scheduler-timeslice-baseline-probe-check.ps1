# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-timeslice-update-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_UPDATE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying scheduler-timeslice-update probe failed with exit code $probeExitCode"
}

$preTimeslice = Extract-IntValue -Text $probeText -Name 'PRE_TIMESLICE'
$preRunCount = Extract-IntValue -Text $probeText -Name 'PRE_RUN_COUNT'
$preBudgetRemaining = Extract-IntValue -Text $probeText -Name 'PRE_BUDGET_REMAINING'

if ($null -in @($preTimeslice, $preRunCount, $preBudgetRemaining)) {
    throw 'Missing expected baseline fields in scheduler-timeslice-update probe output.'
}
if ($preTimeslice -ne 1) { throw "Expected PRE_TIMESLICE=1. got $preTimeslice" }
if ($preRunCount -ne 1) { throw "Expected PRE_RUN_COUNT=1. got $preRunCount" }
if ($preBudgetRemaining -ne 9) { throw "Expected PRE_BUDGET_REMAINING=9. got $preBudgetRemaining" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_BASELINE_PROBE=pass'
Write-Output "PRE_TIMESLICE=$preTimeslice"
Write-Output "PRE_RUN_COUNT=$preRunCount"
Write-Output "PRE_BUDGET_REMAINING=$preBudgetRemaining"