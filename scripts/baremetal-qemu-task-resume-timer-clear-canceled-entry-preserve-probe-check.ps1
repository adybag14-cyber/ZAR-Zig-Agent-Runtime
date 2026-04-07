# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-task-resume-timer-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_CANCELED_ENTRY_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_CANCELED_ENTRY_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-resume-timer-clear-probe-check.ps1' `
    -FailureLabel 'task-resume timer-clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$POST_RESUME_ENTRY_STATE = Extract-IntValue -Text $probeText -Name 'POST_RESUME_ENTRY_STATE'
$POST_RESUME_NEXT_TIMER_ID = Extract-IntValue -Text $probeText -Name 'POST_RESUME_NEXT_TIMER_ID'
$POST_RESUME_DISPATCH_COUNT = Extract-IntValue -Text $probeText -Name 'POST_RESUME_DISPATCH_COUNT'
if ($null -in @($POST_RESUME_ENTRY_STATE, $POST_RESUME_NEXT_TIMER_ID, $POST_RESUME_DISPATCH_COUNT)) {
    throw 'Missing expected task-resume timer-clear canceled-entry fields in probe output.'
}
if ($POST_RESUME_ENTRY_STATE -ne 3) { throw "Expected POST_RESUME_ENTRY_STATE=3. got $POST_RESUME_ENTRY_STATE" }
if ($POST_RESUME_NEXT_TIMER_ID -ne 2) { throw "Expected POST_RESUME_NEXT_TIMER_ID=2. got $POST_RESUME_NEXT_TIMER_ID" }
if ($POST_RESUME_DISPATCH_COUNT -ne 0) { throw "Expected POST_RESUME_DISPATCH_COUNT=0. got $POST_RESUME_DISPATCH_COUNT" }

Write-Output 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_CANCELED_ENTRY_PRESERVE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TASK_RESUME_TIMER_CLEAR_CANCELED_ENTRY_PRESERVE_PROBE_SOURCE=baremetal-qemu-task-resume-timer-clear-probe-check.ps1'
Write-Output "POST_RESUME_ENTRY_STATE=$POST_RESUME_ENTRY_STATE"
Write-Output "POST_RESUME_NEXT_TIMER_ID=$POST_RESUME_NEXT_TIMER_ID"
Write-Output "POST_RESUME_DISPATCH_COUNT=$POST_RESUME_DISPATCH_COUNT"
