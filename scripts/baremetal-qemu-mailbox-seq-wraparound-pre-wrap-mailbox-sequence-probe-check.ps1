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
$probeState = Invoke-WrapperProbe 
    -ProbePath $probe 
    -SkipBuild:$SkipBuild 
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_PROBE=skipped\r?$' 
    -SkippedReceipt 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_PRE_WRAP_MAILBOX_SEQUENCE_PROBE' 
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_PRE_WRAP_MAILBOX_SEQUENCE_PROBE_SOURCE' 
    -SkippedSourceValue 'baremetal-qemu-mailbox-seq-wraparound-probe-check.ps1' 
    -FailureLabel 'mailbox seq-wraparound' 
    -InvokeArgs $invoke
$probeText = $probeState.Text
$preWrapMailboxSeq = Extract-IntValue -Text $probeText -Name 'PRE_WRAP_MAILBOX_SEQ'
if ($null -eq $preWrapMailboxSeq) { throw 'Missing output value for PRE_WRAP_MAILBOX_SEQ' }
if ($preWrapMailboxSeq -ne 4294967295) { throw "Unexpected PRE_WRAP_MAILBOX_SEQ: got $preWrapMailboxSeq expected 4294967295" }

Write-Output 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_PRE_WRAP_MAILBOX_SEQUENCE_PROBE=pass'
Write-Output 'PRE_WRAP_MAILBOX_SEQ=4294967295'
