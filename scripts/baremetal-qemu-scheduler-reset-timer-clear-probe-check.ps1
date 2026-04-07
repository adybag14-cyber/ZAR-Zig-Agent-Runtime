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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_TIMER_CLEAR_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_TIMER_CLEAR_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1' `
    -FailureLabel 'scheduler-reset mixed-state'
$probeText = $probeState.Text

$preTimerCount = Extract-IntValue -Text $probeText -Name 'PRE_TIMER_COUNT'
$prePendingWakeCount = Extract-IntValue -Text $probeText -Name 'PRE_PENDING_WAKE_COUNT'
$postTimerCount = Extract-IntValue -Text $probeText -Name 'POST_TIMER_COUNT'
$postPendingWakeCount = Extract-IntValue -Text $probeText -Name 'POST_PENDING_WAKE_COUNT'
$rearmTimerCount = Extract-IntValue -Text $probeText -Name 'REARM_TIMER_COUNT'

if ($null -in @($preTimerCount, $prePendingWakeCount, $postTimerCount, $postPendingWakeCount, $rearmTimerCount)) {
    throw 'Missing expected scheduler-reset timer-clear fields in probe output.'
}
if ($preTimerCount -ne 0) {
    throw "Expected no armed timer entries before scheduler reset in the mixed-state path. got timer_count=$preTimerCount"
}
if ($prePendingWakeCount -le 0) {
    throw "Expected stale pending timer-wake bookkeeping before scheduler reset. got pending_wake_count=$prePendingWakeCount"
}
if ($postTimerCount -ne 0) {
    throw "Expected scheduler reset to clear armed timer entries immediately. got $postTimerCount"
}
if ($postPendingWakeCount -ne 0) {
    throw "Expected scheduler reset to clear pending timer wakes immediately. got $postPendingWakeCount"
}
if ($rearmTimerCount -ne 1) {
    throw "Expected exactly one fresh timer after post-reset rearm. got $rearmTimerCount"
}

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_TIMER_CLEAR_PROBE=pass'
Write-Output "PRE_TIMER_COUNT=$preTimerCount"
Write-Output "PRE_PENDING_WAKE_COUNT=$prePendingWakeCount"
Write-Output "POST_TIMER_COUNT=$postTimerCount"
Write-Output "POST_PENDING_WAKE_COUNT=$postPendingWakeCount"
Write-Output "REARM_TIMER_COUNT=$rearmTimerCount"
