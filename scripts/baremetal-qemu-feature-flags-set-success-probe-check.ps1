# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-feature-flags-tick-batch-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^\{0}=(-?\d+)\r?$' -f $Name
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_FEATURE_FLAGS_SET_SUCCESS_PROBE' `
    -FailureLabel 'feature-flags/tick-batch' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -InvokeArgs $invoke
$probeText = $probeState.Text
$expected = @{
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE1_ACK' = 1
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE1_LAST_OPCODE' = 2
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE1_LAST_RESULT' = 0
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE1_TICKS' = 1
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE1_FEATURE_FLAGS' = 2774181210
    'BAREMETAL_QEMU_FEATURE_FLAGS_TICK_BATCH_STAGE1_TICK_BATCH_HINT' = 1
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_FEATURE_FLAGS_SET_SUCCESS_PROBE=pass'
Write-Output 'STAGE1_ACK=1'
Write-Output 'STAGE1_LAST_OPCODE=2'
Write-Output 'STAGE1_LAST_RESULT=0'
Write-Output 'STAGE1_TICKS=1'
Write-Output 'STAGE1_FEATURE_FLAGS=2774181210'
Write-Output 'STAGE1_TICK_BATCH_HINT=1'
