# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_INTERRUPT_SURVIVORS_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_INTERRUPT_SURVIVORS_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


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
