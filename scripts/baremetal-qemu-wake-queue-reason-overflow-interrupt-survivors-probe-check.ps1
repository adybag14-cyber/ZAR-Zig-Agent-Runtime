# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-overflow-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild -TimeoutSeconds 90 2>&1 } else { & $probe -TimeoutSeconds 90 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_INTERRUPT_SURVIVORS_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-reason-overflow probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
$postInterruptFirstSeq = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_FIRST_SEQ'
$postInterruptFirstReason = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_FIRST_REASON'
$postInterruptLastSeq = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_LAST_SEQ'
$postInterruptLastReason = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_LAST_REASON'

if ($null -in @($ack, $lastOpcode, $lastResult, $ticks, $postInterruptFirstSeq, $postInterruptFirstReason, $postInterruptLastSeq, $postInterruptLastReason)) {
    throw 'Missing final interrupt survivor fields in wake-queue-reason-overflow probe output.'
}
if ($ack -ne 139 -or $lastOpcode -ne 59 -or $lastResult -ne 0 -or $ticks -lt 139) {
    throw "Unexpected final command summary: ACK=$ack OPCODE=$lastOpcode RESULT=$lastResult TICKS=$ticks"
}
if ($postInterruptFirstSeq -ne 4 -or $postInterruptFirstReason -ne 2 -or $postInterruptLastSeq -ne 66 -or $postInterruptLastReason -ne 2) {
    throw "Unexpected POST_INTERRUPT survivor summary: $postInterruptFirstSeq/$postInterruptFirstReason/$postInterruptLastSeq/$postInterruptLastReason"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_INTERRUPT_SURVIVORS_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TICKS=$ticks"
Write-Output "POST_INTERRUPT_FIRST_SEQ=$postInterruptFirstSeq"
Write-Output "POST_INTERRUPT_FIRST_REASON=$postInterruptFirstReason"
Write-Output "POST_INTERRUPT_LAST_SEQ=$postInterruptLastSeq"
Write-Output "POST_INTERRUPT_LAST_REASON=$postInterruptLastReason"
