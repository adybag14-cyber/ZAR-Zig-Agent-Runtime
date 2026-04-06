# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-counter-reset-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_VECTOR_COUNTER_RESET_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_MAILBOX_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_MAILBOX_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-vector-counter-reset-probe-check.ps1' `
    -FailureLabel 'vector-counter-reset'
$probeText = $probeState.Text


$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_LAST_RESULT'
$mailboxOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_MAILBOX_OPCODE'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_MAILBOX_SEQ'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_TICKS'
if ($null -in @($ack, $lastOpcode, $lastResult, $mailboxOpcode, $mailboxSeq, $ticks)) {
    throw 'Missing final mailbox-state fields in vector-counter-reset output.'
}
if ($ack -ne 8 -or $lastOpcode -ne 15 -or $lastResult -ne 0 -or $mailboxOpcode -ne 15 -or $mailboxSeq -ne 8) {
    throw "Unexpected mailbox-state values after vector-counter reset: ack=$ack lastOpcode=$lastOpcode lastResult=$lastResult mailboxOpcode=$mailboxOpcode mailboxSeq=$mailboxSeq"
}
if ($ticks -lt 8) {
    throw "Expected TICKS>=8 after vector-counter reset, got $ticks"
}

Write-Output 'BAREMETAL_QEMU_VECTOR_COUNTER_RESET_MAILBOX_STATE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "MAILBOX_OPCODE=$mailboxOpcode"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
Write-Output "TICKS=$ticks"
