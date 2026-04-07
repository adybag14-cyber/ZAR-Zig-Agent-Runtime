# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-wake-timer-clear-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_REARM_TELEMETRY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_REARM_TELEMETRY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-wake-timer-clear-probe-check.ps1' `
    -FailureLabel 'scheduler-wake timer-clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$false
$probeText = $probeState.Text

$postResumeDispatchCount = Extract-IntValue -Text $probeText -Name 'POST_RESUME_DISPATCH_COUNT'
$postIdleDispatchCount = Extract-IntValue -Text $probeText -Name 'POST_IDLE_DISPATCH_COUNT'
$rearmTimerId = Extract-IntValue -Text $probeText -Name 'REARM_TIMER_ID'
$rearmNextTimerId = Extract-IntValue -Text $probeText -Name 'REARM_NEXT_TIMER_ID'

if ($null -in @($postResumeDispatchCount, $postIdleDispatchCount, $rearmTimerId, $rearmNextTimerId)) {
    throw 'Missing expected scheduler-wake timer-clear rearm fields in probe output.'
}
if ($postResumeDispatchCount -ne 0) { throw "Expected POST_RESUME_DISPATCH_COUNT=0. got $postResumeDispatchCount" }
if ($postIdleDispatchCount -ne 0) { throw "Expected POST_IDLE_DISPATCH_COUNT=0. got $postIdleDispatchCount" }
if ($rearmTimerId -ne 2) { throw "Expected REARM_TIMER_ID=2. got $rearmTimerId" }
if ($rearmNextTimerId -ne 3) { throw "Expected REARM_NEXT_TIMER_ID=3. got $rearmNextTimerId" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_REARM_TELEMETRY_PROBE=pass'
Write-Output "POST_RESUME_DISPATCH_COUNT=$postResumeDispatchCount"
Write-Output "POST_IDLE_DISPATCH_COUNT=$postIdleDispatchCount"
Write-Output "REARM_TIMER_ID=$rearmTimerId"
Write-Output "REARM_NEXT_TIMER_ID=$rearmNextTimerId"