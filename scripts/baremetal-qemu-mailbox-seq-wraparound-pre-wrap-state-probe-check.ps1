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
$probeState = Invoke-WrapperProbe -ProbePath $probe -SkipBuild:$SkipBuild -SkippedPattern '(?m)^BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_PROBE=skipped\r?$' -SkippedReceipt 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_PRE_WRAP_STATE_PROBE' -SkippedSourceReceipt 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_PRE_WRAP_STATE_PROBE_SOURCE' -SkippedSourceValue 'baremetal-qemu-mailbox-seq-wraparound-probe-check.ps1' -FailureLabel 'mailbox seq-wraparound' -InvokeArgs $invoke
$probeText = $probeState.Text
$expected = @{
    'PRE_WRAP_ACK' = 4294967295
    'PRE_WRAP_LAST_OPCODE' = 6
    'PRE_WRAP_LAST_RESULT' = 0
    'PRE_WRAP_TICK_BATCH_HINT' = 6
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_MAILBOX_SEQ_WRAPAROUND_PRE_WRAP_STATE_PROBE=pass'
Write-Output 'PRE_WRAP_ACK=4294967295'
Write-Output 'PRE_WRAP_LAST_OPCODE=6'
Write-Output 'PRE_WRAP_TICK_BATCH_HINT=6'
