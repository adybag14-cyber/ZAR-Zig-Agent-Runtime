# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_MANUAL_DRAIN_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_MANUAL_DRAIN_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$postManualCount = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_COUNT'
$postManualHead = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_HEAD'
$postManualTail = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_TAIL'
$postManualOverflow = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_OVERFLOW'

if ($null -in @($postManualCount, $postManualHead, $postManualTail, $postManualOverflow)) {
    throw 'Missing post-manual drain summary fields in wake-queue-reason-overflow probe output.'
}
if ($postManualCount -ne 33 -or $postManualHead -ne 33 -or $postManualTail -ne 0 -or $postManualOverflow -ne 2) {
    throw "Unexpected POST_MANUAL summary: $postManualCount/$postManualHead/$postManualTail/$postManualOverflow"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_MANUAL_DRAIN_PROBE=pass'
Write-Output "POST_MANUAL_COUNT=$postManualCount"
Write-Output "POST_MANUAL_HEAD=$postManualHead"
Write-Output "POST_MANUAL_TAIL=$postManualTail"
Write-Output "POST_MANUAL_OVERFLOW=$postManualOverflow"
