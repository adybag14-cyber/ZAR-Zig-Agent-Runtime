# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-fifo-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_DRAIN_EMPTY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_DRAIN_EMPTY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-fifo-probe-check.ps1' `
    -FailureLabel 'wake-queue FIFO'
$probeText = $probeState.Text


$postPop2Len = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_POST_POP2_LEN'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_WAKE_QUEUE_COUNT'
if ($null -in @($postPop2Len,$wakeQueueCount)) {
    throw 'Missing expected drain-empty fields in wake-queue FIFO probe output.'
}
if ($postPop2Len -ne 0 -or $wakeQueueCount -ne 0) {
    throw "Expected empty queue after second pop. got post2=$postPop2Len final=$wakeQueueCount"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_DRAIN_EMPTY_PROBE=pass'
Write-Output "POST_POP2_LEN=$postPop2Len"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
