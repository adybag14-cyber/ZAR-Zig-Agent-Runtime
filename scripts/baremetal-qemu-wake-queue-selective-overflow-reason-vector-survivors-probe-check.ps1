# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-selective-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_OVERFLOW_REASON_VECTOR_SURVIVORS_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_OVERFLOW_REASON_VECTOR_SURVIVORS_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-selective-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue selective overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
$firstSeq = Extract-IntValue -Text $probeText -Name 'POST_REASON_VECTOR_FIRST_SEQ'
$firstVector = Extract-IntValue -Text $probeText -Name 'POST_REASON_VECTOR_FIRST_VECTOR'
$lastSeq = Extract-IntValue -Text $probeText -Name 'POST_REASON_VECTOR_LAST_SEQ'
$lastVector = Extract-IntValue -Text $probeText -Name 'POST_REASON_VECTOR_LAST_VECTOR'

if ($null -in @($ack, $lastOpcode, $lastResult, $ticks, $firstSeq, $firstVector, $lastSeq, $lastVector)) {
    throw 'Missing expected final survivor fields in wake-queue-selective-overflow probe output.'
}
if ($ack -ne 139) { throw "Expected ACK=139. got $ack" }
if ($lastOpcode -ne 62) { throw "Expected LAST_OPCODE=62. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($ticks -lt 139) { throw "Expected TICKS >= 139. got $ticks" }
if ($firstSeq -ne 4 -or $firstVector -ne 31 -or $lastSeq -ne 66 -or $lastVector -ne 31) {
    throw 'Unexpected POST_REASON_VECTOR survivor ordering.'
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_OVERFLOW_REASON_VECTOR_SURVIVORS_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TICKS=$ticks"
Write-Output "POST_REASON_VECTOR_FIRST_SEQ=$firstSeq"
Write-Output "POST_REASON_VECTOR_FIRST_VECTOR=$firstVector"
Write-Output "POST_REASON_VECTOR_LAST_SEQ=$lastSeq"
Write-Output "POST_REASON_VECTOR_LAST_VECTOR=$lastVector"
