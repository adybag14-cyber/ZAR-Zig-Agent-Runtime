# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-history-clear-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_EXCEPTION_RESET_FINAL_STATE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying vector-history-clear probe failed with exit code $probeExitCode"
}

$postExceptionResetCount = Extract-IntValue -Text $probeText -Name 'POST_EXCEPTION_RESET_COUNT'
$postExceptionResetLastVector = Extract-IntValue -Text $probeText -Name 'POST_EXCEPTION_RESET_LAST_VECTOR'
$postExceptionResetLastCode = Extract-IntValue -Text $probeText -Name 'POST_EXCEPTION_RESET_LAST_CODE'
$postExceptionResetHistoryLen = Extract-IntValue -Text $probeText -Name 'POST_EXCEPTION_RESET_HISTORY_LEN'
$postExceptionResetInterruptHistoryLen = Extract-IntValue -Text $probeText -Name 'POST_EXCEPTION_RESET_INTERRUPT_HISTORY_LEN'
$postExceptionResetVector13 = Extract-IntValue -Text $probeText -Name 'POST_EXCEPTION_RESET_VECTOR_13'
$postExceptionHistoryLen = Extract-IntValue -Text $probeText -Name 'POST_EXCEPTION_HISTORY_LEN'
$postExceptionHistoryOverflow = Extract-IntValue -Text $probeText -Name 'POST_EXCEPTION_HISTORY_OVERFLOW'
$finalInterruptCount = Extract-IntValue -Text $probeText -Name 'FINAL_INTERRUPT_COUNT'
$finalExceptionCount = Extract-IntValue -Text $probeText -Name 'FINAL_EXCEPTION_COUNT'

if ($null -in @($postExceptionResetCount, $postExceptionResetLastVector, $postExceptionResetLastCode, $postExceptionResetHistoryLen, $postExceptionResetInterruptHistoryLen, $postExceptionResetVector13, $postExceptionHistoryLen, $postExceptionHistoryOverflow, $finalInterruptCount, $finalExceptionCount)) {
    throw 'Missing exception reset/final state fields in probe output.'
}
if ($postExceptionResetCount -ne 0) { throw "Expected POST_EXCEPTION_RESET_COUNT=0. got $postExceptionResetCount" }
if ($postExceptionResetLastVector -ne 0) { throw "Expected POST_EXCEPTION_RESET_LAST_VECTOR=0. got $postExceptionResetLastVector" }
if ($postExceptionResetLastCode -ne 0) { throw "Expected POST_EXCEPTION_RESET_LAST_CODE=0. got $postExceptionResetLastCode" }
if ($postExceptionResetHistoryLen -ne 1) { throw "Expected POST_EXCEPTION_RESET_HISTORY_LEN=1. got $postExceptionResetHistoryLen" }
if ($postExceptionResetInterruptHistoryLen -ne 2) { throw "Expected POST_EXCEPTION_RESET_INTERRUPT_HISTORY_LEN=2. got $postExceptionResetInterruptHistoryLen" }
if ($postExceptionResetVector13 -ne 1) { throw "Expected POST_EXCEPTION_RESET_VECTOR_13=1. got $postExceptionResetVector13" }
if ($postExceptionHistoryLen -ne 0) { throw "Expected POST_EXCEPTION_HISTORY_LEN=0. got $postExceptionHistoryLen" }
if ($postExceptionHistoryOverflow -ne 0) { throw "Expected POST_EXCEPTION_HISTORY_OVERFLOW=0. got $postExceptionHistoryOverflow" }
if ($finalInterruptCount -ne 0) { throw "Expected FINAL_INTERRUPT_COUNT=0. got $finalInterruptCount" }
if ($finalExceptionCount -ne 0) { throw "Expected FINAL_EXCEPTION_COUNT=0. got $finalExceptionCount" }

Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_EXCEPTION_RESET_FINAL_STATE_PROBE=pass'
Write-Output "POST_EXCEPTION_RESET_HISTORY_LEN=$postExceptionResetHistoryLen"
Write-Output "POST_EXCEPTION_HISTORY_LEN=$postExceptionHistoryLen"
Write-Output "FINAL_INTERRUPT_COUNT=$finalInterruptCount"
Write-Output "FINAL_EXCEPTION_COUNT=$finalExceptionCount"
