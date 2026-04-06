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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_OVERFLOW_REASON_VECTOR_DRAIN_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_OVERFLOW_REASON_VECTOR_DRAIN_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-selective-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue selective overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$postCount = Extract-IntValue -Text $probeText -Name 'POST_REASON_VECTOR_COUNT'
$postHead = Extract-IntValue -Text $probeText -Name 'POST_REASON_VECTOR_HEAD'
$postTail = Extract-IntValue -Text $probeText -Name 'POST_REASON_VECTOR_TAIL'
$postOverflow = Extract-IntValue -Text $probeText -Name 'POST_REASON_VECTOR_OVERFLOW'

if ($null -in @($postCount, $postHead, $postTail, $postOverflow)) {
    throw 'Missing expected post-reason-vector summary fields in wake-queue-selective-overflow probe output.'
}
if ($postCount -ne 32 -or $postHead -ne 32 -or $postTail -ne 0 -or $postOverflow -ne 2) {
    throw "Unexpected POST_REASON_VECTOR summary: $postCount/$postHead/$postTail/$postOverflow"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_OVERFLOW_REASON_VECTOR_DRAIN_PROBE=pass'
Write-Output "POST_REASON_VECTOR_COUNT=$postCount"
Write-Output "POST_REASON_VECTOR_HEAD=$postHead"
Write-Output "POST_REASON_VECTOR_TAIL=$postTail"
Write-Output "POST_REASON_VECTOR_OVERFLOW=$postOverflow"
