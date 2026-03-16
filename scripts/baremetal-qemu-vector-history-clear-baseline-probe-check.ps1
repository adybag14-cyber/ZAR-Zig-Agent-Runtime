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
    Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying vector-history-clear probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
$finalInterruptCount = Extract-IntValue -Text $probeText -Name 'FINAL_INTERRUPT_COUNT'
$finalExceptionCount = Extract-IntValue -Text $probeText -Name 'FINAL_EXCEPTION_COUNT'

if ($null -in @($ack, $lastOpcode, $lastResult, $ticks, $finalInterruptCount, $finalExceptionCount)) {
    throw 'Missing vector-history-clear baseline fields in probe output.'
}
if ($ack -ne 10) { throw "Expected ACK=10. got $ack" }
if ($lastOpcode -ne 13) { throw "Expected LAST_OPCODE=13. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($ticks -lt 10) { throw "Expected TICKS>=10. got $ticks" }
if ($finalInterruptCount -ne 0) { throw "Expected FINAL_INTERRUPT_COUNT=0. got $finalInterruptCount" }
if ($finalExceptionCount -ne 0) { throw "Expected FINAL_EXCEPTION_COUNT=0. got $finalExceptionCount" }

Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_BASELINE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "FINAL_INTERRUPT_COUNT=$finalInterruptCount"
Write-Output "FINAL_EXCEPTION_COUNT=$finalExceptionCount"
