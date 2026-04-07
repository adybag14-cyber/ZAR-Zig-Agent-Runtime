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
    -SkippedReceipt 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_FIRST_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_FIRST_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-mailbox-stale-seq-probe-check.ps1' `
    -FailureLabel 'mailbox stale-seq' `
    -InvokeArgs $invoke
$probeText = $probeState.Text
$rawText = Get-RawProbeText `
    -ProbeText $probeText `
    -PathFieldName 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_GDB_STDOUT' `
    -MissingMessage 'Missing mailbox stale-seq GDB stdout log path.'

$expected = @{
    'FIRST_ACK' = 1
    'FIRST_LAST_OPCODE' = 6
    'FIRST_LAST_RESULT' = 0
    'FIRST_TICK_BATCH_HINT' = 4
}
foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-Field -BroadText $probeText -RawText $rawText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_FIRST_STATE_PROBE=pass'
Write-Output 'FIRST_ACK=1'
Write-Output 'FIRST_LAST_OPCODE=6'
Write-Output 'FIRST_TICK_BATCH_HINT=4'
