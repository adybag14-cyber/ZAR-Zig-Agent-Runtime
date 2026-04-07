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
$probeState = Invoke-WrapperProbe -ProbePath $probe -SkipBuild:$SkipBuild -SkippedPattern '(?m)^BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_PROBE=skipped\r?$' -SkippedReceipt 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_BASELINE_PROBE' -SkippedSourceReceipt 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_BASELINE_PROBE_SOURCE' -SkippedSourceValue 'baremetal-qemu-mailbox-seq-wraparound-probe-check.ps1' -FailureLabel 'mailbox seq-wraparound' -InvokeArgs $invoke
$probeText = $probeState.Text
$required = @(
    'PRE_WRAP_ACK',
    'PRE_WRAP_LAST_OPCODE',
    'PRE_WRAP_LAST_RESULT',
    'PRE_WRAP_TICK_BATCH_HINT',
    'PRE_WRAP_MAILBOX_SEQ',
    'ACK',
    'LAST_OPCODE',
    'LAST_RESULT',
    'TICKS',
    'TICK_BATCH_HINT',
    'MAILBOX_SEQ'
)

foreach ($name in $required) {
    $actual = Extract-IntValue -Text $probeText -Name $name
    if ($null -eq $actual) { throw "Missing output value for $name" }
}

$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
if ($ticks -lt 2) { throw "Expected TICKS >= 2, got $ticks" }

Write-Output 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_BASELINE_PROBE=pass'
Write-Output "PRE_WRAP_ACK=$(Extract-IntValue -Text $probeText -Name 'PRE_WRAP_ACK')"
Write-Output "ACK=$(Extract-IntValue -Text $probeText -Name 'ACK')"
Write-Output "TICKS=$ticks"
