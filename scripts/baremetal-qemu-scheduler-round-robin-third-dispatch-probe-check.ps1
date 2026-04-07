# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-round-robin-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_THIRD_DISPATCH_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_THIRD_DISPATCH_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-round-robin-probe-check.ps1' `
    -FailureLabel 'scheduler-round-robin'
$probeText = $probeState.Text

$firstRunAfterThird = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_RUN_AFTER_THIRD'
$secondRunAfterThird = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_SECOND_RUN_AFTER_THIRD'
$firstBudgetAfterThird = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_BUDGET_AFTER_THIRD'

if ($null -in @($firstRunAfterThird, $secondRunAfterThird, $firstBudgetAfterThird)) {
    throw 'Missing expected third-dispatch fields in scheduler-round-robin probe output.'
}
if ($firstRunAfterThird -ne 2) { throw "Expected FIRST_RUN_AFTER_THIRD=2. got $firstRunAfterThird" }
if ($secondRunAfterThird -ne 1) { throw "Expected SECOND_RUN_AFTER_THIRD=1. got $secondRunAfterThird" }
if ($firstBudgetAfterThird -ne 2) { throw "Expected FIRST_BUDGET_AFTER_THIRD=2. got $firstBudgetAfterThird" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_THIRD_DISPATCH_PROBE=pass'
Write-Output "FIRST_RUN_AFTER_THIRD=$firstRunAfterThird"
Write-Output "SECOND_RUN_AFTER_THIRD=$secondRunAfterThird"
Write-Output "FIRST_BUDGET_AFTER_THIRD=$firstBudgetAfterThird"
