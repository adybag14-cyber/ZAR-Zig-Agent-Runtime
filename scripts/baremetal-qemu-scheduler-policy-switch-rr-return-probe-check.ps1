# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-policy-switch-probe-check.ps1"
$schedulerRoundRobinPolicy = 0
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_RR_RETURN_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_RR_RETURN_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-policy-switch-probe-check.ps1' `
    -FailureLabel 'scheduler-policy-switch'
$probeText = $probeState.Text

$policy = Extract-IntValue -Text $probeText -Name 'RR_RETURN_POLICY'
$lowRun = Extract-IntValue -Text $probeText -Name 'RR_RETURN_LOW_RUN'
$highRun = Extract-IntValue -Text $probeText -Name 'RR_RETURN_HIGH_RUN'
$highBudgetRemaining = Extract-IntValue -Text $probeText -Name 'RR_RETURN_HIGH_BUDGET_REMAINING'

if ($null -in @($policy, $lowRun, $highRun, $highBudgetRemaining)) {
    throw 'Missing expected round-robin return fields in probe output.'
}
if ($policy -ne $schedulerRoundRobinPolicy) {
    throw "Expected round-robin policy=0 after restoring scheduler policy. got $policy"
}
if ($lowRun -ne 2 -or $highRun -ne 3) {
    throw "Expected round-robin return to hand the next slot to the high task. got low=$lowRun high=$highRun"
}
if ($highBudgetRemaining -ne 3) {
    throw "Expected high task budget remaining to drop to 3 after round-robin return. got $highBudgetRemaining"
}

Write-Output 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_RR_RETURN_PROBE=pass'
Write-Output "RR_RETURN_POLICY=$policy"
Write-Output "RR_RETURN_LOW_RUN=$lowRun"
Write-Output "RR_RETURN_HIGH_RUN=$highRun"
Write-Output "RR_RETURN_HIGH_BUDGET_REMAINING=$highBudgetRemaining"
