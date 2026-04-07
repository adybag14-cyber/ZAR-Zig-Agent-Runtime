# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-mailbox-stale-seq-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MAILBOX_STALE_SEQ_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_FINAL_MAILBOX_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_FINAL_MAILBOX_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-mailbox-stale-seq-probe-check.ps1' `
    -FailureLabel 'mailbox stale-seq' `
    -InvokeArgs $invoke
$probeText = $probeState.Text

$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'MAILBOX_SEQ'
$replayLastOpcode = Extract-IntValue -Text $probeText -Name 'REPLAY_LAST_OPCODE'
$replayLastResult = Extract-IntValue -Text $probeText -Name 'REPLAY_LAST_RESULT'
if ($null -eq $ticks) { throw 'Missing output value for TICKS' }
if ($null -eq $mailboxSeq) { throw 'Missing output value for MAILBOX_SEQ' }
if ($null -eq $replayLastOpcode) { throw 'Missing output value for REPLAY_LAST_OPCODE' }
if ($null -eq $replayLastResult) { throw 'Missing output value for REPLAY_LAST_RESULT' }
if ($ticks -lt 2) { throw "Expected TICKS >= 2, got $ticks" }
if ($mailboxSeq -ne 2) { throw "Unexpected MAILBOX_SEQ: got $mailboxSeq expected 2" }
if ($replayLastOpcode -ne 6) { throw "Unexpected REPLAY_LAST_OPCODE: got $replayLastOpcode expected 6" }
if ($replayLastResult -ne 0) { throw "Unexpected REPLAY_LAST_RESULT: got $replayLastResult expected 0" }

Write-Output 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_FINAL_MAILBOX_STATE_PROBE=pass'
Write-Output "TICKS=$ticks"
Write-Output 'MAILBOX_SEQ=2'
Write-Output 'REPLAY_LAST_OPCODE=6'
