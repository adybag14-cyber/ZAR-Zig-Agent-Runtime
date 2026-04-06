# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-policy-switch-probe-check.ps1"
$schedulerPriorityPolicy = 1
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_PRIORITY_DOMINANCE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_PRIORITY_DOMINANCE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-policy-switch-probe-check.ps1' `
    -FailureLabel 'scheduler-policy-switch'
$probeText = $probeState.Text

$policy = Extract-IntValue -Text $probeText -Name 'PRIORITY_POLICY'
$lowRun = Extract-IntValue -Text $probeText -Name 'PRIORITY_LOW_RUN'
$highRun = Extract-IntValue -Text $probeText -Name 'PRIORITY_HIGH_RUN'
$highBudgetRemaining = Extract-IntValue -Text $probeText -Name 'PRIORITY_HIGH_BUDGET_REMAINING'

if ($null -in @($policy, $lowRun, $highRun, $highBudgetRemaining)) {
    throw 'Missing expected priority-dominance fields in probe output.'
}
if ($policy -ne $schedulerPriorityPolicy) {
    throw "Expected priority policy=1 after switch. got $policy"
}
if ($lowRun -ne 1 -or $highRun -ne 2) {
    throw "Expected priority switch to favor the high-priority task. got low=$lowRun high=$highRun"
}
if ($highBudgetRemaining -ne 4) {
    throw "Expected high-priority task budget remaining to drop to 4 after the extra dispatch. got $highBudgetRemaining"
}

Write-Output 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_PRIORITY_DOMINANCE_PROBE=pass'
Write-Output "PRIORITY_POLICY=$policy"
Write-Output "PRIORITY_LOW_RUN=$lowRun"
Write-Output "PRIORITY_HIGH_RUN=$highRun"
Write-Output "PRIORITY_HIGH_BUDGET_REMAINING=$highBudgetRemaining"
