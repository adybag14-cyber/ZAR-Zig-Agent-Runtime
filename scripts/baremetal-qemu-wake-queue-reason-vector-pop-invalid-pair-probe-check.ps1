# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-vector-pop-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_INVALID_PAIR_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_INVALID_PAIR_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-vector-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-vector-pop'
$probeText = $probeState.Text


$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_LAST_RESULT'
if ($null -in @($ack,$lastOpcode,$lastResult)) {
    throw 'Missing expected invalid-pair fields in wake-queue reason-vector-pop probe output.'
}
if ($lastOpcode -ne 62) { throw "Expected LAST_OPCODE=62. got $lastOpcode" }
if ($lastResult -ne -22) { throw "Expected LAST_RESULT=-22. got $lastResult" }
Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_INVALID_PAIR_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
