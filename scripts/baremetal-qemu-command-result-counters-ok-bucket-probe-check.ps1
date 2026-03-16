# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-command-result-counters-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_OK_BUCKET_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying command-result counters probe failed with exit code $probeExitCode"
}

$preCounterOk = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_OK'
$preCounterTotal = Extract-IntValue -Text $probeText -Name 'PRE_COUNTER_TOTAL'
$preHealthCode = Extract-IntValue -Text $probeText -Name 'PRE_HEALTH_CODE'

if ($null -in @($preCounterOk, $preCounterTotal, $preHealthCode)) {
    throw 'Missing ok-bucket command-result fields.'
}
if ($preCounterOk -ne 1) { throw "Expected PRE_COUNTER_OK=1. got $preCounterOk" }
if ($preCounterTotal -ne 4) { throw "Expected PRE_COUNTER_TOTAL=4. got $preCounterTotal" }
if ($preHealthCode -ne 200) { throw "Expected PRE_HEALTH_CODE=200. got $preHealthCode" }

Write-Output 'BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_OK_BUCKET_PROBE=pass'
Write-Output "PRE_COUNTER_OK=$preCounterOk"
Write-Output "PRE_COUNTER_TOTAL=$preCounterTotal"
Write-Output "PRE_HEALTH_CODE=$preHealthCode"
