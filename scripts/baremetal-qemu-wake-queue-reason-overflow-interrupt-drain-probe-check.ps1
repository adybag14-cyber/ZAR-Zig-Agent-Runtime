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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_INTERRUPT_DRAIN_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_INTERRUPT_DRAIN_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$postInterruptCount = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_COUNT'
$postInterruptHead = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_HEAD'
$postInterruptTail = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_TAIL'
$postInterruptOverflow = Extract-IntValue -Text $probeText -Name 'POST_INTERRUPT_OVERFLOW'

if ($null -in @($postInterruptCount, $postInterruptHead, $postInterruptTail, $postInterruptOverflow)) {
    throw 'Missing post-interrupt drain summary fields in wake-queue-reason-overflow probe output.'
}
if ($postInterruptCount -ne 32 -or $postInterruptHead -ne 32 -or $postInterruptTail -ne 0 -or $postInterruptOverflow -ne 2) {
    throw "Unexpected POST_INTERRUPT summary: $postInterruptCount/$postInterruptHead/$postInterruptTail/$postInterruptOverflow"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_INTERRUPT_DRAIN_PROBE=pass'
Write-Output "POST_INTERRUPT_COUNT=$postInterruptCount"
Write-Output "POST_INTERRUPT_HEAD=$postInterruptHead"
Write-Output "POST_INTERRUPT_TAIL=$postInterruptTail"
Write-Output "POST_INTERRUPT_OVERFLOW=$postInterruptOverflow"
