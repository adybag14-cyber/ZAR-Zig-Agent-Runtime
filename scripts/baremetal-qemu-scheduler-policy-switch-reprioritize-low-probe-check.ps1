# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-policy-switch-probe-check.ps1"
$boostedLowPriority = 15
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_REPRIORITIZE_LOW_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_REPRIORITIZE_LOW_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-policy-switch-probe-check.ps1' `
    -FailureLabel 'scheduler-policy-switch'
$probeText = $probeState.Text

$lowPriority = Extract-IntValue -Text $probeText -Name 'REPRIORITIZED_LOW_PRIORITY'
$lowRun = Extract-IntValue -Text $probeText -Name 'REPRIORITIZED_LOW_RUN'
$highRun = Extract-IntValue -Text $probeText -Name 'REPRIORITIZED_HIGH_RUN'
$lowBudgetRemaining = Extract-IntValue -Text $probeText -Name 'REPRIORITIZED_LOW_BUDGET_REMAINING'

if ($null -in @($lowPriority, $lowRun, $highRun, $lowBudgetRemaining)) {
    throw 'Missing expected reprioritized-low fields in probe output.'
}
if ($lowPriority -ne $boostedLowPriority) {
    throw "Expected boosted low-priority task to move to priority 15. got $lowPriority"
}
if ($lowRun -ne 2 -or $highRun -ne 2) {
    throw "Expected reprioritization to hand the next priority dispatch to the low task. got low=$lowRun high=$highRun"
}
if ($lowBudgetRemaining -ne 4) {
    throw "Expected reprioritized low task budget remaining to drop to 4. got $lowBudgetRemaining"
}

Write-Output 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_REPRIORITIZE_LOW_PROBE=pass'
Write-Output "REPRIORITIZED_LOW_PRIORITY=$lowPriority"
Write-Output "REPRIORITIZED_LOW_RUN=$lowRun"
Write-Output "REPRIORITIZED_HIGH_RUN=$highRun"
Write-Output "REPRIORITIZED_LOW_BUDGET_REMAINING=$lowBudgetRemaining"
