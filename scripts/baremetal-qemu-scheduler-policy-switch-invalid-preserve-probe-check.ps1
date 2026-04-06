# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-policy-switch-probe-check.ps1"
$schedulerSetPolicyOpcode = 55
$schedulerRoundRobinPolicy = 0
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_INVALID_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_INVALID_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-policy-switch-probe-check.ps1' `
    -FailureLabel 'scheduler-policy-switch'
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$policy = Extract-IntValue -Text $probeText -Name 'POLICY'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'DISPATCH_COUNT'
$lowRun = Extract-IntValue -Text $probeText -Name 'LOW_RUN'
$highRun = Extract-IntValue -Text $probeText -Name 'HIGH_RUN'
$lowBudgetRemaining = Extract-IntValue -Text $probeText -Name 'LOW_BUDGET_REMAINING'
$highBudgetRemaining = Extract-IntValue -Text $probeText -Name 'HIGH_BUDGET_REMAINING'

if ($null -in @($ack, $lastOpcode, $lastResult, $policy, $dispatchCount, $lowRun, $highRun, $lowBudgetRemaining, $highBudgetRemaining)) {
    throw 'Missing expected invalid-policy preservation fields in probe output.'
}
if ($ack -ne 10) {
    throw "Expected invalid policy attempt to advance mailbox ack to 10. got $ack"
}
if ($lastOpcode -ne $schedulerSetPolicyOpcode -or $lastResult -ne -22) {
    throw "Expected invalid scheduler policy set to fail with opcode 55 / result -22. got opcode=$lastOpcode result=$lastResult"
}
if ($policy -ne $schedulerRoundRobinPolicy) {
    throw "Expected scheduler policy to remain round-robin after invalid input. got $policy"
}
if ($dispatchCount -ne 6) {
    throw "Expected dispatch count to stay on the validated baseline of 6 after invalid input. got $dispatchCount"
}
if ($lowRun -ne 3 -or $highRun -ne 3) {
    throw "Expected task run counts to remain balanced after invalid input. got low=$lowRun high=$highRun"
}
if ($lowBudgetRemaining -ne 3 -or $highBudgetRemaining -ne 3) {
    throw "Expected budgets to remain unchanged after invalid policy input. got low=$lowBudgetRemaining high=$highBudgetRemaining"
}

Write-Output 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_INVALID_PRESERVE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "POLICY=$policy"
Write-Output "DISPATCH_COUNT=$dispatchCount"
Write-Output "LOW_RUN=$lowRun"
Write-Output "HIGH_RUN=$highRun"
Write-Output "LOW_BUDGET_REMAINING=$lowBudgetRemaining"
Write-Output "HIGH_BUDGET_REMAINING=$highBudgetRemaining"
