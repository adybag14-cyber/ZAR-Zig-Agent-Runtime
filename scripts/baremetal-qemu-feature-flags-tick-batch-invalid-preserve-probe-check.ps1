# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-feature-flags-tick-batch-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$probeOutput = & $probe @invoke 2>&1
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_INVALID_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying feature-flags/tick-batch probe failed with exit code $probeExitCode"
}

$expected = @{
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE3_ACK' = 3
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE3_LAST_OPCODE' = 6
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE3_LAST_RESULT' = -22
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE3_TICKS' = 9
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE3_FEATURE_FLAGS' = 2774181210
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE3_TICK_BATCH_HINT' = 4
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_INVALID_PRESERVE_PROBE=pass'
Write-Output 'STAGE3_ACK=3'
Write-Output 'STAGE3_LAST_OPCODE=6'
Write-Output 'STAGE3_LAST_RESULT=-22'
Write-Output 'STAGE3_TICKS=9'
Write-Output 'STAGE3_FEATURE_FLAGS=2774181210'
Write-Output 'STAGE3_TICK_BATCH_HINT=4'
