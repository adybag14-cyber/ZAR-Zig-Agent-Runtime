# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-priority-budget-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_REPRIORITIZE_LOW_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_REPRIORITIZE_LOW_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-priority-budget-probe-check.ps1' `
    -FailureLabel 'scheduler-priority-budget'
$probeText = $probeState.Text

$lowPriorityAfter = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_LOW_PRIORITY_AFTER'
$lowRunAfter = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_LOW_RUN_AFTER'
$highRunBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_HIGH_RUN_BEFORE'
$highRunAfter = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_HIGH_RUN_AFTER'

if ($null -in @($lowPriorityAfter, $lowRunAfter, $highRunBefore, $highRunAfter)) {
    throw 'Missing expected scheduler-priority-budget reprioritize fields in probe output.'
}
if ($lowPriorityAfter -ne 15) { throw "Expected LOW_PRIORITY_AFTER=15. got $lowPriorityAfter" }
if ($lowRunAfter -lt 1) { throw "Expected LOW_RUN_AFTER >= 1. got $lowRunAfter" }
if ($highRunBefore -lt 1) { throw "Expected HIGH_RUN_BEFORE >= 1. got $highRunBefore" }
if ($highRunAfter -lt $highRunBefore) { throw "Expected HIGH_RUN_AFTER >= HIGH_RUN_BEFORE. got before=$highRunBefore after=$highRunAfter" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_REPRIORITIZE_LOW_PROBE=pass'
Write-Output "LOW_PRIORITY_AFTER=$lowPriorityAfter"
Write-Output "LOW_RUN_AFTER=$lowRunAfter"
Write-Output "HIGH_RUN_BEFORE=$highRunBefore"
Write-Output "HIGH_RUN_AFTER=$highRunAfter"
