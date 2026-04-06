# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-fifo-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_NOTFOUND_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_NOTFOUND_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-fifo-probe-check.ps1' `
    -FailureLabel 'wake-queue FIFO'
$probeText = $probeState.Text


$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_LAST_RESULT'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_MAILBOX_SEQ'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_WAKE_QUEUE_COUNT'
if ($null -in @($ack,$lastOpcode,$lastResult,$mailboxSeq,$wakeQueueCount)) {
    throw 'Missing expected notfound-preserve fields in wake-queue FIFO probe output.'
}
if ($ack -ne 11 -or $mailboxSeq -ne 11) { throw "Expected final ack/seq at 11. got ack=$ack seq=$mailboxSeq" }
if ($lastOpcode -ne 54 -or $lastResult -ne -2) { throw "Expected final notfound receipt 54/-2. got $lastOpcode/$lastResult" }
if ($wakeQueueCount -ne 0) { throw "Expected queue to remain empty after rejected pop. got $wakeQueueCount" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_NOTFOUND_PRESERVE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
