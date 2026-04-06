# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-history-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_MAILBOX_STATE_PROBE' `
    -FailureLabel 'vector-history-overflow' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$interruptHistoryLen = Extract-IntValue -Text $probeText -Name 'INTERRUPT_HISTORY_LEN_PHASE_B'
$interruptHistoryOverflow = Extract-IntValue -Text $probeText -Name 'INTERRUPT_HISTORY_OVERFLOW_PHASE_B'
$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'

if ($null -in @($interruptHistoryLen, $interruptHistoryOverflow, $ack, $lastOpcode, $lastResult)) {
    throw 'Missing final mailbox-state vector-history-overflow fields.'
}
if ($interruptHistoryLen -ne 19) { throw "Expected INTERRUPT_HISTORY_LEN_PHASE_B=19. got $interruptHistoryLen" }
if ($interruptHistoryOverflow -ne 0) { throw "Expected INTERRUPT_HISTORY_OVERFLOW_PHASE_B=0. got $interruptHistoryOverflow" }
if ($ack -ne 62) { throw "Expected ACK=62. got $ack" }
if ($lastOpcode -ne 12) { throw "Expected LAST_OPCODE=12. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }

Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_OVERFLOW_MAILBOX_STATE_PROBE=pass'
Write-Output "INTERRUPT_HISTORY_LEN_PHASE_B=$interruptHistoryLen"
Write-Output "INTERRUPT_HISTORY_OVERFLOW_PHASE_B=$interruptHistoryOverflow"
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
