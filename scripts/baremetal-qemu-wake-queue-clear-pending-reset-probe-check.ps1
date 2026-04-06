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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PENDING_RESET_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PENDING_RESET_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-clear-probe-check.ps1' `
    -FailureLabel 'wake-queue clear' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$postClearPendingWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_CLEAR_PENDING_WAKE_COUNT'

if ($null -eq $postClearPendingWakeCount) {
    throw 'Missing expected post-clear pending-wake field in wake-queue-clear probe output.'
}
if ($postClearPendingWakeCount -ne 0) {
    throw "Expected POST_CLEAR_PENDING_WAKE_COUNT=0. got $postClearPendingWakeCount"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PENDING_RESET_PROBE=pass'
Write-Output "POST_CLEAR_PENDING_WAKE_COUNT=$postClearPendingWakeCount"
