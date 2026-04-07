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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_CANCELED_ENTRY_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_CANCELED_ENTRY_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-wake-timer-clear-probe-check.ps1' `
    -FailureLabel 'scheduler-wake timer-clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$false
$probeText = $probeState.Text

$postResumeEntryState = Extract-IntValue -Text $probeText -Name 'POST_RESUME_ENTRY_STATE'
$postIdleTimerCount = Extract-IntValue -Text $probeText -Name 'POST_IDLE_TIMER_COUNT'
$postIdleQuantum = Extract-IntValue -Text $probeText -Name 'POST_IDLE_QUANTUM'

if ($null -in @($postResumeEntryState, $postIdleTimerCount, $postIdleQuantum)) {
    throw 'Missing expected scheduler-wake timer-clear canceled-entry fields in probe output.'
}
if ($postResumeEntryState -ne 3) { throw "Expected POST_RESUME_ENTRY_STATE=3. got $postResumeEntryState" }
if ($postIdleTimerCount -ne 0) { throw "Expected POST_IDLE_TIMER_COUNT=0. got $postIdleTimerCount" }
if ($postIdleQuantum -ne 5) { throw "Expected POST_IDLE_QUANTUM=5. got $postIdleQuantum" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_WAKE_TIMER_CLEAR_CANCELED_ENTRY_PRESERVE_PROBE=pass'
Write-Output "POST_RESUME_ENTRY_STATE=$postResumeEntryState"
Write-Output "POST_IDLE_TIMER_COUNT=$postIdleTimerCount"
Write-Output "POST_IDLE_QUANTUM=$postIdleQuantum"