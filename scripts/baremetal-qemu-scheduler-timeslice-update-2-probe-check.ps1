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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_UPDATE_2_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_UPDATE_2_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-timeslice-update-probe-check.ps1' `
    -FailureLabel 'scheduler-timeslice-update'
$probeText = $probeState.Text

$midTimeslice = Extract-IntValue -Text $probeText -Name 'MID_TIMESLICE_2'
$midRunCount = Extract-IntValue -Text $probeText -Name 'MID_RUN_COUNT_2'
$midBudgetRemaining = Extract-IntValue -Text $probeText -Name 'MID_BUDGET_REMAINING_2'

if ($null -in @($midTimeslice, $midRunCount, $midBudgetRemaining)) {
    throw 'Missing expected timeslice=2 fields in scheduler-timeslice-update probe output.'
}
if ($midTimeslice -ne 2) { throw "Expected MID_TIMESLICE_2=2. got $midTimeslice" }
if ($midRunCount -ne 3) { throw "Expected MID_RUN_COUNT_2=3. got $midRunCount" }
if ($midBudgetRemaining -ne 3) { throw "Expected MID_BUDGET_REMAINING_2=3. got $midBudgetRemaining" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_UPDATE_2_PROBE=pass'
Write-Output "MID_TIMESLICE_2=$midTimeslice"
Write-Output "MID_RUN_COUNT_2=$midRunCount"
Write-Output "MID_BUDGET_REMAINING_2=$midBudgetRemaining"