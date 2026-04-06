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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_RR_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_RR_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-policy-switch-probe-check.ps1' `
    -FailureLabel 'scheduler-policy-switch'
$probeText = $probeState.Text

$policy = Extract-IntValue -Text $probeText -Name 'RR_BASELINE_POLICY'
$lowId = Extract-IntValue -Text $probeText -Name 'RR_BASELINE_LOW_ID'
$highId = Extract-IntValue -Text $probeText -Name 'RR_BASELINE_HIGH_ID'
$lowRun = Extract-IntValue -Text $probeText -Name 'RR_BASELINE_LOW_RUN'
$highRun = Extract-IntValue -Text $probeText -Name 'RR_BASELINE_HIGH_RUN'

if ($null -in @($policy, $lowId, $highId, $lowRun, $highRun)) {
    throw 'Missing expected round-robin baseline fields in probe output.'
}
if ($policy -ne $schedulerRoundRobinPolicy) {
    throw "Expected round-robin baseline policy=0. got $policy"
}
if ($lowId -ne 1 -or $highId -ne 2) {
    throw "Expected baseline task ids low=1 high=2. got low=$lowId high=$highId"
}
if ($lowRun -ne 1 -or $highRun -ne 1) {
    throw "Expected balanced round-robin baseline run counts low=1 high=1. got low=$lowRun high=$highRun"
}

Write-Output 'BAREMETAL_QEMU_SCHEDULER_POLICY_SWITCH_RR_BASELINE_PROBE=pass'
Write-Output "RR_BASELINE_POLICY=$policy"
Write-Output "RR_BASELINE_LOW_ID=$lowId"
Write-Output "RR_BASELINE_HIGH_ID=$highId"
Write-Output "RR_BASELINE_LOW_RUN=$lowRun"
Write-Output "RR_BASELINE_HIGH_RUN=$highRun"
