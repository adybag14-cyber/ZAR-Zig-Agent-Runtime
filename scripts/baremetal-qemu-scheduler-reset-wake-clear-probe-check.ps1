# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_WAKE_CLEAR_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_WAKE_CLEAR_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1' `
    -FailureLabel 'scheduler-reset mixed-state'
$probeText = $probeState.Text

$preWakeCount = Extract-IntValue -Text $probeText -Name 'PRE_WAKE_COUNT'
$postWakeCount = Extract-IntValue -Text $probeText -Name 'POST_WAKE_COUNT'
$afterIdleWakeCount = Extract-IntValue -Text $probeText -Name 'AFTER_IDLE_WAKE_COUNT'

if ($null -in @($preWakeCount, $postWakeCount, $afterIdleWakeCount)) {
    throw 'Missing expected scheduler-reset wake-clear fields in probe output.'
}
if ($preWakeCount -le 0) {
    throw "Expected stale queued wakes before scheduler reset. got $preWakeCount"
}
if ($postWakeCount -ne 0) {
    throw "Expected scheduler reset to clear queued wakes immediately. got $postWakeCount"
}
if ($afterIdleWakeCount -ne 0) {
    throw "Expected no stale wakes to reappear after idle ticks post-reset. got $afterIdleWakeCount"
}

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_WAKE_CLEAR_PROBE=pass'
Write-Output "PRE_WAKE_COUNT=$preWakeCount"
Write-Output "POST_WAKE_COUNT=$postWakeCount"
Write-Output "AFTER_IDLE_WAKE_COUNT=$afterIdleWakeCount"
