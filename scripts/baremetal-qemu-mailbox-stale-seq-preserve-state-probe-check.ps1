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
    -SkippedReceipt 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_PRESERVE_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_PRESERVE_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-mailbox-stale-seq-probe-check.ps1' `
    -FailureLabel 'mailbox stale-seq' `
    -InvokeArgs $invoke
$probeText = $probeState.Text

$expected = @{
    'FIRST_ACK' = 1
    'FIRST_LAST_OPCODE' = 6
    'FIRST_LAST_RESULT' = 0
    'FIRST_TICK_BATCH_HINT' = 4
    'FIRST_MAILBOX_SEQ' = 1
    'STALE_ACK' = 1
    'STALE_LAST_OPCODE' = 6
    'STALE_LAST_RESULT' = 0
    'STALE_TICK_BATCH_HINT' = 4
    'STALE_MAILBOX_SEQ' = 1
    'ACK' = 2
    'TICK_BATCH_HINT' = 6
    'MAILBOX_SEQ' = 2
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_MAILBOX_STALE_SEQ_PRESERVE_STATE_PROBE=pass'
Write-Output 'FIRST_ACK=1'
Write-Output 'FIRST_TICK_BATCH_HINT=4'
Write-Output 'STALE_ACK=1'
Write-Output 'STALE_TICK_BATCH_HINT=4'
Write-Output 'ACK=2'
Write-Output 'TICK_BATCH_HINT=6'
Write-Output 'MAILBOX_SEQ=2'

