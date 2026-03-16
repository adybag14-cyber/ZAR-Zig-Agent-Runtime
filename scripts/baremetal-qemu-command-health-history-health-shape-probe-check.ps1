# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-command-health-history-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_HEALTH_SHAPE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying command-health history probe failed with exit code $probeExitCode"
}

$len = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_LEN'
$overflow = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_OVERFLOW'
$head = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_HEAD'

if ($null -in @($len, $overflow, $head)) {
    throw 'Missing health-history shape fields.'
}
if ($len -ne 64) { throw "Expected HEALTH_HISTORY_LEN=64. got $len" }
if ($overflow -ne 7) { throw "Expected HEALTH_HISTORY_OVERFLOW=7. got $overflow" }
if ($head -ne 7) { throw "Expected HEALTH_HISTORY_HEAD=7. got $head" }

Write-Output 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_HEALTH_SHAPE_PROBE=pass'
Write-Output "HEALTH_HISTORY_LEN=$len"
Write-Output "HEALTH_HISTORY_OVERFLOW=$overflow"
Write-Output "HEALTH_HISTORY_HEAD=$head"
