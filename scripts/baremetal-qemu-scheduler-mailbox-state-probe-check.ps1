# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_MAILBOX_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_MAILBOX_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-probe-check.ps1' `
    -FailureLabel 'scheduler'
$probeText = $probeState.Text

$mailboxOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_MAILBOX_OPCODE'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_MAILBOX_SEQ'
$timedOut = Extract-BoolValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_TIMED_OUT'

if ($null -in @($mailboxOpcode, $mailboxSeq, $timedOut)) {
    throw 'Missing expected scheduler mailbox fields in probe output.'
}
if ($mailboxOpcode -ne 24) { throw "Expected MAILBOX_OPCODE=24. got $mailboxOpcode" }
if ($mailboxSeq -ne 5) { throw "Expected MAILBOX_SEQ=5. got $mailboxSeq" }
if ($timedOut) { throw 'Expected TIMED_OUT=False.' }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_MAILBOX_STATE_PROBE=pass'
Write-Output "MAILBOX_OPCODE=$mailboxOpcode"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
Write-Output "TIMED_OUT=$timedOut"
