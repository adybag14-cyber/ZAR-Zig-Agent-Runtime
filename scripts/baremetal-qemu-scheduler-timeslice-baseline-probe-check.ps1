# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-timeslice-update-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_TIMESLICE_UPDATE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-timeslice-update-probe-check.ps1' `
    -FailureLabel 'scheduler-timeslice-update'
$probeText = $probeState.Text

$preTimeslice = Extract-IntValue -Text $probeText -Name 'PRE_TIMESLICE'
$preRunCount = Extract-IntValue -Text $probeText -Name 'PRE_RUN_COUNT'
$preBudgetRemaining = Extract-IntValue -Text $probeText -Name 'PRE_BUDGET_REMAINING'

if ($null -in @($preTimeslice, $preRunCount, $preBudgetRemaining)) {
    throw 'Missing expected baseline fields in scheduler-timeslice-update probe output.'
}
if ($preTimeslice -ne 1) { throw "Expected PRE_TIMESLICE=1. got $preTimeslice" }
if ($preRunCount -ne 1) { throw "Expected PRE_RUN_COUNT=1. got $preRunCount" }
if ($preBudgetRemaining -ne 9) { throw "Expected PRE_BUDGET_REMAINING=9. got $preBudgetRemaining" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_BASELINE_PROBE=pass'
Write-Output "PRE_TIMESLICE=$preTimeslice"
Write-Output "PRE_RUN_COUNT=$preRunCount"
Write-Output "PRE_BUDGET_REMAINING=$preBudgetRemaining"