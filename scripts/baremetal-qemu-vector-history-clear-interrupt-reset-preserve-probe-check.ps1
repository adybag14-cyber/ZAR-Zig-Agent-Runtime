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
    Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_INTERRUPT_RESET_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying vector-history-clear probe failed with exit code $probeExitCode"
}

$postInterruptResetCount = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_RESET_COUNT'
$postInterruptResetLastVector = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_RESET_LAST_VECTOR'
$postInterruptResetHistoryLen = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_RESET_HISTORY_LEN'
$postInterruptResetExceptionCount = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_RESET_EXCEPTION_COUNT'
$postInterruptResetVector200 = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_RESET_VECTOR_200'
$postInterruptHistoryLen = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_HISTORY_LEN'
$postInterruptHistoryOverflow = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_HISTORY_OVERFLOW'
$postExceptionHistoryLenAfterInterruptClear = Extract-IntValue -Text $probeText -Name 'POST_EXCEPTION_HISTORY_LEN_AFTER_INTERRUPT_CLEAR'

if ($null -in @($postInterruptResetCount, $postInterruptResetLastVector, $postInterruptResetHistoryLen, $postInterruptResetExceptionCount, $postInterruptResetVector200, $postInterruptHistoryLen, $postInterruptHistoryOverflow, $postExceptionHistoryLenAfterInterruptClear)) {
    throw 'Missing interrupt reset/clear fields in probe output.'
}
if ($postInterruptResetCount -ne 0) { throw "Expected POST_INTERRUPT_RESET_COUNT=0. got $postInterruptResetCount" }
if ($postInterruptResetLastVector -ne 0) { throw "Expected POST_INTERRUPT_RESET_LAST_VECTOR=0. got $postInterruptResetLastVector" }
if ($postInterruptResetHistoryLen -ne 2) { throw "Expected POST_INTERRUPT_RESET_HISTORY_LEN=2. got $postInterruptResetHistoryLen" }
if ($postInterruptResetExceptionCount -ne 1) { throw "Expected POST_INTERRUPT_RESET_EXCEPTION_COUNT=1. got $postInterruptResetExceptionCount" }
if ($postInterruptResetVector200 -ne 1) { throw "Expected POST_INTERRUPT_RESET_VECTOR_200=1. got $postInterruptResetVector200" }
if ($postInterruptHistoryLen -ne 0) { throw "Expected POST_INTERRUPT_HISTORY_LEN=0. got $postInterruptHistoryLen" }
if ($postInterruptHistoryOverflow -ne 0) { throw "Expected POST_INTERRUPT_HISTORY_OVERFLOW=0. got $postInterruptHistoryOverflow" }
if ($postExceptionHistoryLenAfterInterruptClear -ne 1) { throw "Expected POST_EXCEPTION_HISTORY_LEN_AFTER_INTERRUPT_CLEAR=1. got $postExceptionHistoryLenAfterInterruptClear" }

Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_INTERRUPT_RESET_PRESERVE_PROBE=pass'
Write-Output "POST_INTERRUPT_RESET_HISTORY_LEN=$postInterruptResetHistoryLen"
Write-Output "POST_INTERRUPT_HISTORY_LEN=$postInterruptHistoryLen"
Write-Output "POST_EXCEPTION_HISTORY_LEN_AFTER_INTERRUPT_CLEAR=$postExceptionHistoryLenAfterInterruptClear"
