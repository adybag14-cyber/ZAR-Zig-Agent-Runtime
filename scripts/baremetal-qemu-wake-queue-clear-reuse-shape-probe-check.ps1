# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-clear-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_REUSE_SHAPE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_REUSE_SHAPE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-clear-probe-check.ps1' `
    -FailureLabel 'wake-queue clear' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$postReuseCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_REUSE_COUNT'
$postReuseHead = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_REUSE_HEAD'
$postReuseTail = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_REUSE_TAIL'
$postReuseOverflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_REUSE_OVERFLOW'
$postReusePendingWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_REUSE_PENDING_WAKE_COUNT'
$postReuseSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_REUSE_SEQ'

if ($null -in @($postReuseCount, $postReuseHead, $postReuseTail, $postReuseOverflow, $postReusePendingWakeCount, $postReuseSeq)) {
    throw 'Missing expected post-reuse shape fields in wake-queue-clear probe output.'
}
if ($postReuseCount -ne 1 -or $postReuseHead -ne 1 -or $postReuseTail -ne 0 -or $postReuseOverflow -ne 0) {
    throw "Unexpected POST_REUSE queue summary: $postReuseCount/$postReuseHead/$postReuseTail/$postReuseOverflow"
}
if ($postReusePendingWakeCount -ne 1) {
    throw "Expected POST_REUSE_PENDING_WAKE_COUNT=1. got $postReusePendingWakeCount"
}
if ($postReuseSeq -ne 1) {
    throw "Expected POST_REUSE_SEQ=1. got $postReuseSeq"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_REUSE_SHAPE_PROBE=pass'
Write-Output "POST_REUSE_COUNT=$postReuseCount"
Write-Output "POST_REUSE_HEAD=$postReuseHead"
Write-Output "POST_REUSE_TAIL=$postReuseTail"
Write-Output "POST_REUSE_OVERFLOW=$postReuseOverflow"
Write-Output "POST_REUSE_PENDING_WAKE_COUNT=$postReusePendingWakeCount"
Write-Output "POST_REUSE_SEQ=$postReuseSeq"
