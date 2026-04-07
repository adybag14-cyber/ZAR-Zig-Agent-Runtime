# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_MAILBOX_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_MAILBOX_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_LAST_RESULT'

if ($null -in @($ack, $lastOpcode, $lastResult)) {
    throw 'Missing expected mailbox-state fields in wake-queue-overflow probe output.'
}
if ($ack -ne 136) { throw "Expected ACK=136. got $ack" }
if ($lastOpcode -ne 45) { throw "Expected LAST_OPCODE=45. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_MAILBOX_STATE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
