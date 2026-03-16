# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-history-clear-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PROBE=skipped') {
    Write-Output "BAREMETAL_QEMU_RESET_EXCEPTION_COUNTERS_PRESERVE_HISTORY_PROBE=skipped"
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying vector-history-clear probe failed with exit code $probeExitCode"
}

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

