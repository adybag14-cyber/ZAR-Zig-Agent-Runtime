# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-history-clear-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_INTERRUPT_RESET_PRESERVE_PROBE' `
    -FailureLabel 'vector-history-clear' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

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
