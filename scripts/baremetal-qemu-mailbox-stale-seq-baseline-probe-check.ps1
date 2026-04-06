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
    -SkippedReceipt 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-mailbox-stale-seq-probe-check.ps1' `
    -FailureLabel 'mailbox stale-seq' `
    -InvokeArgs $invoke
$probeText = $probeState.Text

$required = @('FIRST_ACK','FIRST_LAST_OPCODE','FIRST_LAST_RESULT','FIRST_TICK_BATCH_HINT','FIRST_MAILBOX_SEQ','STALE_ACK','STALE_LAST_OPCODE','STALE_LAST_RESULT','STALE_TICK_BATCH_HINT','STALE_MAILBOX_SEQ','ACK','LAST_OPCODE','LAST_RESULT','TICKS','TICK_BATCH_HINT','MAILBOX_SEQ')
foreach ($name in $required) {
    $actual = Extract-IntValue -Text $probeText -Name $name
    if ($null -eq $actual) { throw "Missing output value for $name" }
}

$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
if ($ticks -lt 2) { throw "Expected TICKS >= 2, got $ticks" }

Write-Output 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_BASELINE_PROBE=pass'
Write-Output "FIRST_ACK=$(Extract-IntValue -Text $probeText -Name 'FIRST_ACK')"
Write-Output "STALE_ACK=$(Extract-IntValue -Text $probeText -Name 'STALE_ACK')"
Write-Output "ACK=$(Extract-IntValue -Text $probeText -Name 'ACK')"
