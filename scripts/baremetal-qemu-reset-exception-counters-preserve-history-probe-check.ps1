# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-history-clear-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^\{0}=(-?\d+)\r?$' -f $Name
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_RESET_EXCEPTION_COUNTERS_PRESERVE_HISTORY_PROBE' `
    -FailureLabel 'vector-history-clear' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text
$preExceptionHistoryLen = Extract-IntValue -Text $probeText -Name "PRE_EXCEPTION_HISTORY_LEN"
$preInterruptHistoryLen = Extract-IntValue -Text $probeText -Name "PRE_INTERRUPT_HISTORY_LEN"
$postExceptionResetCount = Extract-IntValue -Text $probeText -Name "POST_EXCEPTION_RESET_COUNT"
$postExceptionResetLastVector = Extract-IntValue -Text $probeText -Name "POST_EXCEPTION_RESET_LAST_VECTOR"
$postExceptionResetLastCode = Extract-IntValue -Text $probeText -Name "POST_EXCEPTION_RESET_LAST_CODE"
$postExceptionResetHistoryLen = Extract-IntValue -Text $probeText -Name "POST_EXCEPTION_RESET_HISTORY_LEN"
$postExceptionResetInterruptHistoryLen = Extract-IntValue -Text $probeText -Name "POST_EXCEPTION_RESET_INTERRUPT_HISTORY_LEN"
$postExceptionResetVector13 = Extract-IntValue -Text $probeText -Name "POST_EXCEPTION_RESET_VECTOR_13"

if ($null -in @($preExceptionHistoryLen, $preInterruptHistoryLen, $postExceptionResetCount, $postExceptionResetLastVector, $postExceptionResetLastCode, $postExceptionResetHistoryLen, $postExceptionResetInterruptHistoryLen, $postExceptionResetVector13)) {
    throw "Missing expected exception-reset preservation fields in probe output."
}
if ($postExceptionResetCount -ne 0) {
    throw "Expected exception count reset to 0. got $postExceptionResetCount"
}
if ($postExceptionResetLastVector -ne 0) {
    throw "Expected last exception vector reset to 0. got $postExceptionResetLastVector"
}
if ($postExceptionResetLastCode -ne 0) {
    throw "Expected last exception code reset to 0. got $postExceptionResetLastCode"
}
if ($postExceptionResetHistoryLen -ne $preExceptionHistoryLen) {
    throw "Exception history length drifted across exception-counter reset. pre=$preExceptionHistoryLen post=$postExceptionResetHistoryLen"
}
if ($postExceptionResetInterruptHistoryLen -ne $preInterruptHistoryLen) {
    throw "Interrupt history length drifted across exception-counter reset. pre=$preInterruptHistoryLen post=$postExceptionResetInterruptHistoryLen"
}
if ($postExceptionResetVector13 -ne 1) {
    throw "Expected exception vector 13 count to remain 1 immediately after exception-counter reset. got $postExceptionResetVector13"
}

Write-Output "BAREMETAL_QEMU_RESET_EXCEPTION_COUNTERS_PRESERVE_HISTORY_PROBE=pass"
Write-Output "PRE_EXCEPTION_HISTORY_LEN=$preExceptionHistoryLen"
Write-Output "POST_EXCEPTION_RESET_HISTORY_LEN=$postExceptionResetHistoryLen"
Write-Output "PRE_INTERRUPT_HISTORY_LEN=$preInterruptHistoryLen"
Write-Output "POST_EXCEPTION_RESET_INTERRUPT_HISTORY_LEN=$postExceptionResetInterruptHistoryLen"
Write-Output "POST_EXCEPTION_RESET_VECTOR_13=$postExceptionResetVector13"

