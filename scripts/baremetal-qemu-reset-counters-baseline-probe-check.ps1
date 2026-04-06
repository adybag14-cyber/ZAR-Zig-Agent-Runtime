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
    -SkippedReceipt 'BAREMETAL_QEMU_RESET_COUNTERS_BASELINE_PROBE' `
    -FailureLabel 'reset-counters' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$postAck = Extract-IntValue -Text $probeText -Name "POST_ACK"
$postLastOpcode = Extract-IntValue -Text $probeText -Name "POST_LAST_OPCODE"
$postLastResult = Extract-IntValue -Text $probeText -Name "POST_LAST_RESULT"
$postTicks = Extract-IntValue -Text $probeText -Name "POST_TICKS"
$postMode = Extract-IntValue -Text $probeText -Name "POST_MODE"

if ($null -in @($postAck, $postLastOpcode, $postLastResult, $postTicks, $postMode)) {
    throw "Missing reset-counters baseline fields in probe output."
}
if ($postAck -ne 13) { throw "Expected POST_ACK=13. got $postAck" }
if ($postLastOpcode -ne 3) { throw "Expected POST_LAST_OPCODE=3. got $postLastOpcode" }
if ($postLastResult -ne 0) { throw "Expected POST_LAST_RESULT=0. got $postLastResult" }
if ($postTicks -ne 4) { throw "Expected POST_TICKS=4. got $postTicks" }
if ($postMode -ne 1) { throw "Expected POST_MODE=1. got $postMode" }

Write-Output "__NAME__=pass"
Write-Output "POST_ACK=$postAck"
Write-Output "POST_LAST_OPCODE=$postLastOpcode"
Write-Output "POST_LAST_RESULT=$postLastResult"
Write-Output "POST_TICKS=$postTicks"
Write-Output "POST_MODE=$postMode"
