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
    -SkippedReceipt 'BAREMETAL_QEMU_CLEAR_INTERRUPT_HISTORY_PRESERVE_EXCEPTION_PROBE' `
    -FailureLabel 'vector-history-clear' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text
$preExceptionHistoryLen = Extract-IntValue -Text $probeText -Name "PRE_EXCEPTION_HISTORY_LEN"
$postInterruptHistoryLen = Extract-IntValue -Text $probeText -Name "POST_INTERRUPT_HISTORY_LEN"
$postInterruptHistoryOverflow = Extract-IntValue -Text $probeText -Name "POST_INTERRUPT_HISTORY_OVERFLOW"
$postExceptionHistoryLenAfterInterruptClear = Extract-IntValue -Text $probeText -Name "POST_EXCEPTION_HISTORY_LEN_AFTER_INTERRUPT_CLEAR"

if ($null -in @($preExceptionHistoryLen, $postInterruptHistoryLen, $postInterruptHistoryOverflow, $postExceptionHistoryLenAfterInterruptClear)) {
    throw "Missing expected interrupt-history clear preservation fields in probe output."
}
if ($postInterruptHistoryLen -ne 0) {
    throw "Expected interrupt history length to collapse to 0 after clear. got $postInterruptHistoryLen"
}
if ($postInterruptHistoryOverflow -ne 0) {
    throw "Expected interrupt history overflow to collapse to 0 after clear. got $postInterruptHistoryOverflow"
}
if ($postExceptionHistoryLenAfterInterruptClear -ne $preExceptionHistoryLen) {
    throw "Exception history length drifted across interrupt-history clear. pre=$preExceptionHistoryLen post=$postExceptionHistoryLenAfterInterruptClear"
}

Write-Output "BAREMETAL_QEMU_CLEAR_INTERRUPT_HISTORY_PRESERVE_EXCEPTION_PROBE=pass"
Write-Output "PRE_EXCEPTION_HISTORY_LEN=$preExceptionHistoryLen"
Write-Output "POST_EXCEPTION_HISTORY_LEN_AFTER_INTERRUPT_CLEAR=$postExceptionHistoryLenAfterInterruptClear"
Write-Output "POST_INTERRUPT_HISTORY_LEN=$postInterruptHistoryLen"
Write-Output "POST_INTERRUPT_HISTORY_OVERFLOW=$postInterruptHistoryOverflow"

