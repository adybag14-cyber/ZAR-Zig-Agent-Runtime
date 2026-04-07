# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-dispatch-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_EXCEPTION_HISTORY_MAILBOX_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_EXCEPTION_HISTORY_MAILBOX_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-descriptor-dispatch-probe-check.ps1' `
    -FailureLabel 'descriptor-dispatch'
$probeText = $probeState.Text


$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_LAST_RESULT'
$mailboxOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_MAILBOX_OPCODE'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_MAILBOX_SEQ'
$seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_EVENT1_SEQ'
$vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_EVENT1_VECTOR'
$code = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_EVENT1_CODE'
$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_EVENT1_INTERRUPT_COUNT'
$exceptionCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_EVENT1_EXCEPTION_COUNT'

if ($null -in @($ack, $lastOpcode, $lastResult, $mailboxOpcode, $mailboxSeq, $seq, $vector, $code, $interruptCount, $exceptionCount)) {
    throw 'Missing exception-history or mailbox fields in descriptor-dispatch probe output.'
}
if ($ack -ne 8) { throw "Expected ACK=8. got $ack" }
if ($lastOpcode -ne 12) { throw "Expected LAST_OPCODE=12. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($mailboxOpcode -ne 12) { throw "Expected MAILBOX_OPCODE=12. got $mailboxOpcode" }
if ($mailboxSeq -ne 8) { throw "Expected MAILBOX_SEQ=8. got $mailboxSeq" }
if ($seq -ne 1 -or $vector -ne 13 -or $code -ne 51966 -or $interruptCount -ne 2 -or $exceptionCount -ne 1) {
    throw "Unexpected exception event payload: seq=$seq vector=$vector code=$code interrupt_count=$interruptCount exception_count=$exceptionCount"
}

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_EXCEPTION_HISTORY_MAILBOX_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "MAILBOX_OPCODE=$mailboxOpcode"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
Write-Output "EXCEPTION_EVENT1_SEQ=$seq"
Write-Output "EXCEPTION_EVENT1_VECTOR=$vector"
Write-Output "EXCEPTION_EVENT1_CODE=$code"
Write-Output "EXCEPTION_EVENT1_INTERRUPT_COUNT=$interruptCount"
Write-Output "EXCEPTION_EVENT1_EXCEPTION_COUNT=$exceptionCount"
