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
    Write-Output "BAREMETAL_QEMU_RESET_INTERRUPT_COUNTERS_PRESERVE_HISTORY_PROBE=skipped"
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying vector-history-clear probe failed with exit code $probeExitCode"
}

$preInterruptHistoryLen = Extract-IntValue -Text $probeText -Name "PRE_INTERRUPT_HISTORY_LEN"
$preExceptionCount = Extract-IntValue -Text $probeText -Name "PRE_EXCEPTION_COUNT"
$postInterruptResetCount = Extract-IntValue -Text $probeText -Name "POST_INTERRUPT_RESET_COUNT"
$postInterruptResetLastVector = Extract-IntValue -Text $probeText -Name "POST_INTERRUPT_RESET_LAST_VECTOR"
$postInterruptResetHistoryLen = Extract-IntValue -Text $probeText -Name "POST_INTERRUPT_RESET_HISTORY_LEN"
$postInterruptResetExceptionCount = Extract-IntValue -Text $probeText -Name "POST_INTERRUPT_RESET_EXCEPTION_COUNT"
$postInterruptResetVector200 = Extract-IntValue -Text $probeText -Name "POST_INTERRUPT_RESET_VECTOR_200"

if ($null -in @($preInterruptHistoryLen, $preExceptionCount, $postInterruptResetCount, $postInterruptResetLastVector, $postInterruptResetHistoryLen, $postInterruptResetExceptionCount, $postInterruptResetVector200)) {
    throw "Missing expected interrupt-reset preservation fields in probe output."
}
if ($postInterruptResetCount -ne 0) {
    throw "Expected interrupt count reset to 0. got $postInterruptResetCount"
}
if ($postInterruptResetLastVector -ne 0) {
    throw "Expected last interrupt vector reset to 0. got $postInterruptResetLastVector"
}
if ($postInterruptResetHistoryLen -ne $preInterruptHistoryLen) {
    throw "Interrupt history length drifted across interrupt-counter reset. pre=$preInterruptHistoryLen post=$postInterruptResetHistoryLen"
}
if ($postInterruptResetExceptionCount -ne $preExceptionCount) {
    throw "Exception aggregate drifted across interrupt-counter reset. pre=$preExceptionCount post=$postInterruptResetExceptionCount"
}
if ($postInterruptResetVector200 -ne 1) {
    throw "Expected interrupt vector 200 count to remain 1 immediately after interrupt-counter reset. got $postInterruptResetVector200"
}

Write-Output "BAREMETAL_QEMU_RESET_INTERRUPT_COUNTERS_PRESERVE_HISTORY_PROBE=pass"
Write-Output "PRE_INTERRUPT_HISTORY_LEN=$preInterruptHistoryLen"
Write-Output "POST_INTERRUPT_RESET_HISTORY_LEN=$postInterruptResetHistoryLen"
Write-Output "PRE_EXCEPTION_COUNT=$preExceptionCount"
Write-Output "POST_INTERRUPT_RESET_EXCEPTION_COUNT=$postInterruptResetExceptionCount"
Write-Output "POST_INTERRUPT_RESET_VECTOR_200=$postInterruptResetVector200"

