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
    Write-Output "BAREMETAL_QEMU_CLEAR_INTERRUPT_HISTORY_PRESERVE_EXCEPTION_PROBE=skipped"
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying vector-history-clear probe failed with exit code $probeExitCode"
}

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

