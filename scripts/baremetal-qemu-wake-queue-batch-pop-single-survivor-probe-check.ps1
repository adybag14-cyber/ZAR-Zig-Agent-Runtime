# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-batch-pop-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_SINGLE_SURVIVOR_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_SINGLE_SURVIVOR_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-batch-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue batch-pop' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$afterSingleCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_SINGLE_COUNT'
$afterSingleTail = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_SINGLE_TAIL'
$afterSingleSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_SINGLE_SEQ'

if ($null -in @($afterSingleCount, $afterSingleTail, $afterSingleSeq)) {
    throw 'Missing expected single-survivor fields in wake-queue-batch-pop probe output.'
}
if ($afterSingleCount -ne 1) { throw "Expected AFTER_SINGLE_COUNT=1. got $afterSingleCount" }
if ($afterSingleTail -ne 1) { throw "Expected AFTER_SINGLE_TAIL=1. got $afterSingleTail" }
if ($afterSingleSeq -ne 66) { throw "Expected AFTER_SINGLE_SEQ=66. got $afterSingleSeq" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_SINGLE_SURVIVOR_PROBE=pass'
Write-Output "AFTER_SINGLE_COUNT=$afterSingleCount"
Write-Output "AFTER_SINGLE_TAIL=$afterSingleTail"
Write-Output "AFTER_SINGLE_SEQ=$afterSingleSeq"
