# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-reset-counters-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_RESET_COUNTERS_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_RESET_COUNTERS_VECTOR_RESET_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying reset-counters probe failed with exit code $probeExitCode"
}

$preInterruptCount = Extract-IntValue -Text $probeText -Name "PRE_INTERRUPT_COUNT"
$preExceptionCount = Extract-IntValue -Text $probeText -Name "PRE_EXCEPTION_COUNT"
$preInterruptHistoryLen = Extract-IntValue -Text $probeText -Name "PRE_INTERRUPT_HISTORY_LEN"
$preExceptionHistoryLen = Extract-IntValue -Text $probeText -Name "PRE_EXCEPTION_HISTORY_LEN"
$preInterruptVector = Extract-IntValue -Text $probeText -Name "PRE_INTERRUPT_VECTOR_200"
$preExceptionVector = Extract-IntValue -Text $probeText -Name "PRE_EXCEPTION_VECTOR_13"
$postInterruptCount = Extract-IntValue -Text $probeText -Name "POST_INTERRUPT_COUNT"
$postExceptionCount = Extract-IntValue -Text $probeText -Name "POST_EXCEPTION_COUNT"
$postInterruptHistoryLen = Extract-IntValue -Text $probeText -Name "POST_INTERRUPT_HISTORY_LEN"
$postExceptionHistoryLen = Extract-IntValue -Text $probeText -Name "POST_EXCEPTION_HISTORY_LEN"
$postInterruptVector = Extract-IntValue -Text $probeText -Name "POST_INTERRUPT_VECTOR_200"
$postExceptionVector = Extract-IntValue -Text $probeText -Name "POST_EXCEPTION_VECTOR_13"

if ($null -in @($preInterruptCount,$preExceptionCount,$preInterruptHistoryLen,$preExceptionHistoryLen,$preInterruptVector,$preExceptionVector,$postInterruptCount,$postExceptionCount,$postInterruptHistoryLen,$postExceptionHistoryLen,$postInterruptVector,$postExceptionVector)) {
    throw "Missing vector reset fields in probe output."
}
if ($preInterruptCount -lt 1 -or $preExceptionCount -lt 1) { throw "Expected dirty interrupt/exception aggregate counts before reset." }
if ($preInterruptHistoryLen -lt 2 -or $preExceptionHistoryLen -lt 1) { throw "Expected dirty vector history lengths before reset." }
if ($preInterruptVector -ne 1 -or $preExceptionVector -ne 1) { throw "Expected dirty vector counters before reset." }
if ($postInterruptCount -ne 0 -or $postExceptionCount -ne 0) { throw "Expected aggregate counts to reset to zero." }
if ($postInterruptHistoryLen -ne 0 -or $postExceptionHistoryLen -ne 0) { throw "Expected vector histories to reset to zero length." }
if ($postInterruptVector -ne 0 -or $postExceptionVector -ne 0) { throw "Expected per-vector counters to reset to zero." }

Write-Output "__NAME__=pass"
Write-Output "PRE_INTERRUPT_COUNT=$preInterruptCount"
Write-Output "PRE_EXCEPTION_COUNT=$preExceptionCount"
Write-Output "POST_INTERRUPT_COUNT=$postInterruptCount"
Write-Output "POST_EXCEPTION_COUNT=$postExceptionCount"
