# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-disable-enable-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-disable-enable-probe-check.ps1' `
    -FailureLabel 'scheduler-disable-enable'
$probeText = $probeState.Text

$preEnabled = Extract-IntValue -Text $probeText -Name 'PRE_ENABLED'
$preDispatch = Extract-IntValue -Text $probeText -Name 'PRE_DISPATCH_COUNT'
$preRun = Extract-IntValue -Text $probeText -Name 'PRE_RUN_COUNT'
$preBudget = Extract-IntValue -Text $probeText -Name 'PRE_BUDGET_REMAINING'

if ($null -in @($preEnabled, $preDispatch, $preRun, $preBudget)) {
    throw 'Missing expected baseline fields in scheduler-disable-enable probe output.'
}
if ($preEnabled -ne 1) { throw "Expected PRE_ENABLED=1. got $preEnabled" }
if ($preDispatch -ne 1) { throw "Expected PRE_DISPATCH_COUNT=1. got $preDispatch" }
if ($preRun -ne 1) { throw "Expected PRE_RUN_COUNT=1. got $preRun" }
if ($preBudget -ne 4) { throw "Expected PRE_BUDGET_REMAINING=4. got $preBudget" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_BASELINE_PROBE=pass'
Write-Output "PRE_ENABLED=$preEnabled"
Write-Output "PRE_DISPATCH_COUNT=$preDispatch"
Write-Output "PRE_RUN_COUNT=$preRun"
Write-Output "PRE_BUDGET_REMAINING=$preBudget"