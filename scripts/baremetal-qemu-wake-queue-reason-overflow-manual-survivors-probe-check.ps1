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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_MANUAL_SURVIVORS_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_MANUAL_SURVIVORS_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$postManualFirstSeq = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_FIRST_SEQ'
$postManualFirstReason = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_FIRST_REASON'
$postManualRemainingSeq = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_REMAINING_SEQ'
$postManualRemainingReason = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_REMAINING_REASON'
$postManualLastSeq = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_LAST_SEQ'
$postManualLastReason = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_LAST_REASON'

if ($null -in @($postManualFirstSeq, $postManualFirstReason, $postManualRemainingSeq, $postManualRemainingReason, $postManualLastSeq, $postManualLastReason)) {
    throw 'Missing post-manual survivor fields in wake-queue-reason-overflow probe output.'
}
if ($postManualFirstSeq -ne 4 -or $postManualFirstReason -ne 2 -or $postManualRemainingSeq -ne 65 -or $postManualRemainingReason -ne 3 -or $postManualLastSeq -ne 66 -or $postManualLastReason -ne 2) {
    throw "Unexpected POST_MANUAL survivor summary: $postManualFirstSeq/$postManualFirstReason/$postManualRemainingSeq/$postManualRemainingReason/$postManualLastSeq/$postManualLastReason"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_MANUAL_SURVIVORS_PROBE=pass'
Write-Output "POST_MANUAL_FIRST_SEQ=$postManualFirstSeq"
Write-Output "POST_MANUAL_FIRST_REASON=$postManualFirstReason"
Write-Output "POST_MANUAL_REMAINING_SEQ=$postManualRemainingSeq"
Write-Output "POST_MANUAL_REMAINING_REASON=$postManualRemainingReason"
Write-Output "POST_MANUAL_LAST_SEQ=$postManualLastSeq"
Write-Output "POST_MANUAL_LAST_REASON=$postManualLastReason"
