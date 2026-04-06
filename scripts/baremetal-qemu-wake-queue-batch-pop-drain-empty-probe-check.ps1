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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_DRAIN_EMPTY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_DRAIN_EMPTY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-batch-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue batch-pop' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$afterDrainCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_DRAIN_COUNT'
$afterDrainHead = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_DRAIN_HEAD'
$afterDrainTail = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_DRAIN_TAIL'
$afterDrainOverflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_DRAIN_OVERFLOW'

if ($null -in @($afterDrainCount, $afterDrainHead, $afterDrainTail, $afterDrainOverflow)) {
    throw 'Missing expected drain-empty fields in wake-queue-batch-pop probe output.'
}
if ($afterDrainCount -ne 0) { throw "Expected AFTER_DRAIN_COUNT=0. got $afterDrainCount" }
if ($afterDrainHead -ne 2 -or $afterDrainTail -ne 2) { throw "Expected AFTER_DRAIN head/tail = 2/2. got $afterDrainHead/$afterDrainTail" }
if ($afterDrainOverflow -ne 2) { throw "Expected AFTER_DRAIN_OVERFLOW=2. got $afterDrainOverflow" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_DRAIN_EMPTY_PROBE=pass'
Write-Output "AFTER_DRAIN_COUNT=$afterDrainCount"
Write-Output "AFTER_DRAIN_HEAD=$afterDrainHead"
Write-Output "AFTER_DRAIN_TAIL=$afterDrainTail"
Write-Output "AFTER_DRAIN_OVERFLOW=$afterDrainOverflow"
