# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-syscall-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-allocator-syscall-probe-check.ps1' `
    -FailureLabel 'allocator-syscall'
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_TICKS'
$mailboxOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_MAILBOX_OPCODE'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_PROBE_MAILBOX_SEQ'
if ($null -in @($ack,$lastOpcode,$lastResult,$ticks,$mailboxOpcode,$mailboxSeq)) { throw 'Missing baseline allocator-syscall fields.' }
if ($ack -ne 16) { throw "Expected ACK=16. got $ack" }
if ($lastOpcode -ne 37) { throw "Expected LAST_OPCODE=37. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($ticks -lt 16) { throw "Expected TICKS >= 16. got $ticks" }
if ($mailboxOpcode -ne 37) { throw "Expected MAILBOX_OPCODE=37. got $mailboxOpcode" }
if ($mailboxSeq -ne 16) { throw "Expected MAILBOX_SEQ=16. got $mailboxSeq" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SYSCALL_BASELINE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TICKS=$ticks"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
