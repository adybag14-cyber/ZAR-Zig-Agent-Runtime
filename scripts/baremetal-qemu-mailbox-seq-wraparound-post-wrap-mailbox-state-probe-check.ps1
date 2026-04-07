# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-mailbox-seq-wraparound-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe 
    -SkipBuild:$SkipBuild 
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_PROBE=skipped\r?$' 
    -SkippedReceipt 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_POST_WRAP_MAILBOX_STATE_PROBE' 
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_POST_WRAP_MAILBOX_STATE_PROBE_SOURCE' 
    -SkippedSourceValue 'baremetal-qemu-mailbox-seq-wraparound-probe-check.ps1' 
    -FailureLabel 'mailbox seq-wraparound' 
    -InvokeArgs $invoke
$probeText = $probeState.Text
$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'MAILBOX_SEQ'
if ($null -eq $ticks) { throw 'Missing output value for TICKS' }
if ($null -eq $mailboxSeq) { throw 'Missing output value for MAILBOX_SEQ' }
if ($ticks -lt 2) { throw "Expected TICKS >= 2, got $ticks" }
if ($mailboxSeq -ne 0) { throw "Unexpected MAILBOX_SEQ: got $mailboxSeq expected 0" }

Write-Output 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_POST_WRAP_MAILBOX_STATE_PROBE=pass'
Write-Output "TICKS=$ticks"
Write-Output 'MAILBOX_SEQ=0'
