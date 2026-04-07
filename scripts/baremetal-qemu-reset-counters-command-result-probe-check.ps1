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
    -SkippedReceipt 'BAREMETAL_QEMU_RESET_COUNTERS_COMMAND_RESULT_PROBE' `
    -FailureLabel 'reset-counters' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$preCommandResultTotal = Extract-IntValue -Text $probeText -Name "PRE_COMMAND_RESULT_TOTAL"
$postCommandResultOk = Extract-IntValue -Text $probeText -Name "POST_COMMAND_RESULT_OK"
$postCommandResultInvalid = Extract-IntValue -Text $probeText -Name "POST_COMMAND_RESULT_INVALID"
$postCommandResultNotSupported = Extract-IntValue -Text $probeText -Name "POST_COMMAND_RESULT_NOT_SUPPORTED"
$postCommandResultOther = Extract-IntValue -Text $probeText -Name "POST_COMMAND_RESULT_OTHER"
$postCommandResultTotal = Extract-IntValue -Text $probeText -Name "POST_COMMAND_RESULT_TOTAL"
$postCommandResultLastResult = Extract-IntValue -Text $probeText -Name "POST_COMMAND_RESULT_LAST_RESULT"
$postCommandResultLastOpcode = Extract-IntValue -Text $probeText -Name "POST_COMMAND_RESULT_LAST_OPCODE"
$postCommandResultLastSeq = Extract-IntValue -Text $probeText -Name "POST_COMMAND_RESULT_LAST_SEQ"

if ($null -in @($preCommandResultTotal,$postCommandResultOk,$postCommandResultInvalid,$postCommandResultNotSupported,$postCommandResultOther,$postCommandResultTotal,$postCommandResultLastResult,$postCommandResultLastOpcode,$postCommandResultLastSeq)) {
    throw "Missing command-result reset fields in probe output."
}
if ($preCommandResultTotal -lt 12) { throw "Expected dirty command-result counters before reset." }
if ($postCommandResultOk -ne 1 -or $postCommandResultInvalid -ne 0 -or $postCommandResultNotSupported -ne 0 -or $postCommandResultOther -ne 0 -or $postCommandResultTotal -ne 1) {
    throw "Command-result counters did not collapse to the reset receipt."
}
if ($postCommandResultLastResult -ne 0 -or $postCommandResultLastOpcode -ne 3 -or $postCommandResultLastSeq -ne 13) {
    throw "Command-result last receipt does not match reset-counters."
}

Write-Output "__NAME__=pass"
Write-Output "PRE_COMMAND_RESULT_TOTAL=$preCommandResultTotal"
Write-Output "POST_COMMAND_RESULT_TOTAL=$postCommandResultTotal"
Write-Output "POST_COMMAND_RESULT_LAST_OPCODE=$postCommandResultLastOpcode"
Write-Output "POST_COMMAND_RESULT_LAST_SEQ=$postCommandResultLastSeq"
