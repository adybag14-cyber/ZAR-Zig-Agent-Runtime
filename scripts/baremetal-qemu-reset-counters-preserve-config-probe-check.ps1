# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-reset-counters-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\\d+)$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_RESET_COUNTERS_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_RESET_COUNTERS_PRESERVE_CONFIG_PROBE' `
    -FailureLabel 'reset-counters' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$preFeatureFlags = Extract-IntValue -Text $probeText -Name "PRE_FEATURE_FLAGS"
$preTickBatchHint = Extract-IntValue -Text $probeText -Name "PRE_TICK_BATCH_HINT"
$postFeatureFlags = Extract-IntValue -Text $probeText -Name "POST_FEATURE_FLAGS"
$postTickBatchHint = Extract-IntValue -Text $probeText -Name "POST_TICK_BATCH_HINT"
$postCommandResultTotal = Extract-IntValue -Text $probeText -Name "POST_COMMAND_RESULT_TOTAL"
$postLastOpcode = Extract-IntValue -Text $probeText -Name "POST_LAST_OPCODE"

if ($null -eq $preFeatureFlags -or
    $null -eq $preTickBatchHint -or
    $null -eq $postFeatureFlags -or
    $null -eq $postTickBatchHint -or
    $null -eq $postCommandResultTotal -or
    $null -eq $postLastOpcode) {
    throw "Missing expected reset-counters preservation fields in probe output."
}
if ($preFeatureFlags -ne $postFeatureFlags) {
    throw "Feature flags drifted across command_reset_counters. pre=$preFeatureFlags post=$postFeatureFlags"
}
if ($preTickBatchHint -ne $postTickBatchHint) {
    throw "Tick-batch hint drifted across command_reset_counters. pre=$preTickBatchHint post=$postTickBatchHint"
}
if ($postCommandResultTotal -ne 1) {
    throw "Expected command-result counters to collapse to the reset receipt. got total=$postCommandResultTotal"
}
if ($postLastOpcode -ne 3) {
    throw "Expected POST_LAST_OPCODE=3 (command_reset_counters). got $postLastOpcode"
}

Write-Output "BAREMETAL_QEMU_RESET_COUNTERS_PRESERVE_CONFIG_PROBE=pass"
Write-Output "PRE_FEATURE_FLAGS=$preFeatureFlags"
Write-Output "POST_FEATURE_FLAGS=$postFeatureFlags"
Write-Output "PRE_TICK_BATCH_HINT=$preTickBatchHint"
Write-Output "POST_TICK_BATCH_HINT=$postTickBatchHint"
Write-Output "POST_COMMAND_RESULT_TOTAL=$postCommandResultTotal"
Write-Output "POST_LAST_OPCODE=$postLastOpcode"
