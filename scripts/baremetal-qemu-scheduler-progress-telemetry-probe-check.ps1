# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_PROGRESS_TELEMETRY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_PROGRESS_TELEMETRY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-probe-check.ps1' `
    -FailureLabel 'scheduler'
$probeText = $probeState.Text

$dispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_DISPATCH_COUNT'
$runCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_TASK0_RUN_COUNT'
$budgetRemaining = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_TASK0_BUDGET_REMAINING'

if ($null -in @($dispatchCount, $runCount, $budgetRemaining)) {
    throw 'Missing expected scheduler progress fields in probe output.'
}
if ($dispatchCount -ne 2) { throw "Expected DISPATCH_COUNT=2. got $dispatchCount" }
if ($runCount -ne 2) { throw "Expected TASK0_RUN_COUNT=2. got $runCount" }
if ($budgetRemaining -ne 6) { throw "Expected TASK0_BUDGET_REMAINING=6. got $budgetRemaining" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_PROGRESS_TELEMETRY_PROBE=pass'
Write-Output "DISPATCH_COUNT=$dispatchCount"
Write-Output "TASK0_RUN_COUNT=$runCount"
Write-Output "TASK0_BUDGET_REMAINING=$budgetRemaining"
