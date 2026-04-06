# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-command-result-counters-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^\{0}=(-?\d+)$' -f $Name
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_COMMAND_RESULT_COUNTERS_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_RESET_COMMAND_RESULT_PRESERVE_RUNTIME_PROBE' `
    -FailureLabel 'command-result' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text
$postMode = Extract-IntValue -Text $probeText -Name "POST_MODE"
$postHealthCode = Extract-IntValue -Text $probeText -Name "POST_HEALTH_CODE"
$postCounterTotal = Extract-IntValue -Text $probeText -Name "POST_COUNTER_TOTAL"
$postCounterLastOpcode = Extract-IntValue -Text $probeText -Name "POST_COUNTER_LAST_OPCODE"
$postLastOpcode = Extract-IntValue -Text $probeText -Name "POST_LAST_OPCODE"
$postLastResult = Extract-IntValue -Text $probeText -Name "POST_LAST_RESULT"

if ($null -eq $postMode -or
    $null -eq $postHealthCode -or
    $null -eq $postCounterTotal -or
    $null -eq $postCounterLastOpcode -or
    $null -eq $postLastOpcode -or
    $null -eq $postLastResult) {
    throw "Missing expected command-result preservation fields in probe output."
}
if ($postMode -ne 1) {
    throw "Expected runtime mode to remain running after command_reset_command_result_counters. got $postMode"
}
if ($postHealthCode -ne 200) {
    throw "Expected health code to remain 200 after command_reset_command_result_counters. got $postHealthCode"
}
if ($postCounterTotal -ne 1) {
    throw "Expected command-result counters to collapse to one reset receipt. got total=$postCounterTotal"
}
if ($postCounterLastOpcode -ne 23 -or $postLastOpcode -ne 23) {
    throw "Expected reset-command-result opcode 23 in status and counters. got status=$postLastOpcode counters=$postCounterLastOpcode"
}
if ($postLastResult -ne 0) {
    throw "Expected reset-command-result to finish with result 0. got $postLastResult"
}

Write-Output "BAREMETAL_QEMU_RESET_COMMAND_RESULT_PRESERVE_RUNTIME_PROBE=pass"
Write-Output "POST_MODE=$postMode"
Write-Output "POST_HEALTH_CODE=$postHealthCode"
Write-Output "POST_COUNTER_TOTAL=$postCounterTotal"
Write-Output "POST_COUNTER_LAST_OPCODE=$postCounterLastOpcode"
Write-Output "POST_LAST_OPCODE=$postLastOpcode"
Write-Output "POST_LAST_RESULT=$postLastResult"
