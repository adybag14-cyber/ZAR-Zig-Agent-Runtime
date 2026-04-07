# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_IDLE_STABILITY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_IDLE_STABILITY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1' `
    -FailureLabel 'scheduler-reset mixed-state' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true
$probeText = $probeState.Text

$afterIdleWakeCount = Extract-IntValue -Text $probeText -Name 'AFTER_IDLE_WAKE_COUNT'
$afterIdleTimerCount = Extract-IntValue -Text $probeText -Name 'AFTER_IDLE_TIMER_COUNT'

if ($null -in @($afterIdleWakeCount, $afterIdleTimerCount)) {
    throw 'Missing expected scheduler-reset mixed-state idle fields in probe output.'
}
if ($afterIdleWakeCount -ne 0) { throw "Expected AFTER_IDLE_WAKE_COUNT=0. got $afterIdleWakeCount" }
if ($afterIdleTimerCount -ne 0) { throw "Expected AFTER_IDLE_TIMER_COUNT=0. got $afterIdleTimerCount" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_IDLE_STABILITY_PROBE=pass'
Write-Output "AFTER_IDLE_WAKE_COUNT=$afterIdleWakeCount"
Write-Output "AFTER_IDLE_TIMER_COUNT=$afterIdleTimerCount"
