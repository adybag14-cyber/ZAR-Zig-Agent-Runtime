# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-wake-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_TIMER_WAKE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_TIMER_WAKE_MAILBOX_STATE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-wake probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_LAST_RESULT'
$mailboxOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_MAILBOX_OPCODE'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_MAILBOX_SEQ'

if ($null -in @($ack, $lastOpcode, $lastResult, $mailboxOpcode, $mailboxSeq)) {
    throw 'Missing expected mailbox fields in timer-wake probe output.'
}
if ($ack -ne 5) { throw "Expected ACK=5. got $ack" }
if ($lastOpcode -ne 53) { throw "Expected LAST_OPCODE=53. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($mailboxOpcode -ne 53) { throw "Expected MAILBOX_OPCODE=53. got $mailboxOpcode" }
if ($mailboxSeq -ne 5) { throw "Expected MAILBOX_SEQ=5. got $mailboxSeq" }

Write-Output 'BAREMETAL_QEMU_TIMER_WAKE_MAILBOX_STATE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "MAILBOX_OPCODE=$mailboxOpcode"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
