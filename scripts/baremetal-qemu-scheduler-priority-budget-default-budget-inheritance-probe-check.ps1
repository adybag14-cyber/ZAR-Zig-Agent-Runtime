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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_DEFAULT_BUDGET_INHERITANCE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_DEFAULT_BUDGET_INHERITANCE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-priority-budget-probe-check.ps1' `
    -FailureLabel 'scheduler-priority-budget'
$probeText = $probeState.Text

$lowBudgetTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_LOW_BUDGET_TICKS'
$lowBudgetRemaining = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_LOW_BUDGET_REMAINING'
$highBudgetTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_HIGH_BUDGET_TICKS'
$highBudgetRemaining = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_HIGH_BUDGET_REMAINING'

if ($null -in @($lowBudgetTicks, $lowBudgetRemaining, $highBudgetTicks, $highBudgetRemaining)) {
    throw 'Missing expected scheduler-priority-budget inheritance fields in probe output.'
}
if ($lowBudgetTicks -ne 9 -or $lowBudgetRemaining -ne 9) {
    throw "Expected low task to inherit default budget 9/9. got ticks=$lowBudgetTicks remaining=$lowBudgetRemaining"
}
if ($highBudgetTicks -ne 6 -or $highBudgetRemaining -ne 6) {
    throw "Expected high task explicit budget 6/6. got ticks=$highBudgetTicks remaining=$highBudgetRemaining"
}

Write-Output 'BAREMETAL_QEMU_SCHEDULER_PRIORITY_BUDGET_DEFAULT_BUDGET_INHERITANCE_PROBE=pass'
Write-Output "LOW_BUDGET_TICKS=$lowBudgetTicks"
Write-Output "LOW_BUDGET_REMAINING=$lowBudgetRemaining"
Write-Output "HIGH_BUDGET_TICKS=$highBudgetTicks"
Write-Output "HIGH_BUDGET_REMAINING=$highBudgetRemaining"
