# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-reset-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_RESET_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_DEFAULTS_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_DEFAULTS_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-reset-probe-check.ps1' `
    -FailureLabel 'scheduler-reset'
$probeText = $probeState.Text

$postResetTimeslice = Extract-IntValue -Text $probeText -Name 'POST_RESET_TIMESLICE'
$postResetDefaultBudget = Extract-IntValue -Text $probeText -Name 'POST_RESET_DEFAULT_BUDGET'
$timeslice = Extract-IntValue -Text $probeText -Name 'TIMESLICE'
$defaultBudget = Extract-IntValue -Text $probeText -Name 'DEFAULT_BUDGET'

if ($null -in @($postResetTimeslice, $postResetDefaultBudget, $timeslice, $defaultBudget)) {
    throw 'Missing expected defaults-preserve fields in scheduler-reset probe output.'
}
if ($postResetTimeslice -ne 1) { throw "Expected POST_RESET_TIMESLICE=1. got $postResetTimeslice" }
if ($postResetDefaultBudget -ne 8) { throw "Expected POST_RESET_DEFAULT_BUDGET=8. got $postResetDefaultBudget" }
if ($timeslice -ne 1) { throw "Expected final TIMESLICE=1. got $timeslice" }
if ($defaultBudget -ne 8) { throw "Expected final DEFAULT_BUDGET=8. got $defaultBudget" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_DEFAULTS_PRESERVE_PROBE=pass'
Write-Output "POST_RESET_TIMESLICE=$postResetTimeslice"
Write-Output "POST_RESET_DEFAULT_BUDGET=$postResetDefaultBudget"
Write-Output "TIMESLICE=$timeslice"
Write-Output "DEFAULT_BUDGET=$defaultBudget"
