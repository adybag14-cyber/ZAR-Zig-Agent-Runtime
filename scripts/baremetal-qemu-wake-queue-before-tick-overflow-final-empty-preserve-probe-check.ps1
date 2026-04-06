# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-before-tick-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_FINAL_EMPTY_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_FINAL_EMPTY_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-before-tick-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue before-tick overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$finalCount = Extract-IntValue -Text $probeText -Name 'FINAL_COUNT'
$finalHead = Extract-IntValue -Text $probeText -Name 'FINAL_HEAD'
$finalTail = Extract-IntValue -Text $probeText -Name 'FINAL_TAIL'
$finalOverflow = Extract-IntValue -Text $probeText -Name 'FINAL_OVERFLOW'

if ($null -in @($ack, $lastOpcode, $lastResult, $finalCount, $finalHead, $finalTail, $finalOverflow)) {
    throw 'Missing expected final empty-preserve fields in wake-queue before-tick overflow probe output.'
}
if ($ack -ne 141) { throw "Expected ACK=141. got $ack" }
if ($lastOpcode -ne 61) { throw "Expected LAST_OPCODE=61. got $lastOpcode" }
if ($lastResult -ne -2) { throw "Expected LAST_RESULT=-2. got $lastResult" }
if ($finalCount -ne 0) { throw "Expected FINAL_COUNT=0. got $finalCount" }
if ($finalHead -ne 0) { throw "Expected FINAL_HEAD=0. got $finalHead" }
if ($finalTail -ne 0) { throw "Expected FINAL_TAIL=0. got $finalTail" }
if ($finalOverflow -ne 2) { throw "Expected FINAL_OVERFLOW=2. got $finalOverflow" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_FINAL_EMPTY_PRESERVE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "FINAL_COUNT=$finalCount"
Write-Output "FINAL_HEAD=$finalHead"
Write-Output "FINAL_TAIL=$finalTail"
Write-Output "FINAL_OVERFLOW=$finalOverflow"
