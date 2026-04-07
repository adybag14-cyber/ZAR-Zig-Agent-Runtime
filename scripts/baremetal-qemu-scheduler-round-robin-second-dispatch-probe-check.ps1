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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_SECOND_DISPATCH_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_SECOND_DISPATCH_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-round-robin-probe-check.ps1' `
    -FailureLabel 'scheduler-round-robin'
$probeText = $probeState.Text

$firstRunAfterSecond = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_RUN_AFTER_SECOND'
$secondRunAfterSecond = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_SECOND_RUN_AFTER_SECOND'
$secondBudgetAfterSecond = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_SECOND_BUDGET_AFTER_SECOND'

if ($null -in @($firstRunAfterSecond, $secondRunAfterSecond, $secondBudgetAfterSecond)) {
    throw 'Missing expected second-dispatch fields in scheduler-round-robin probe output.'
}
if ($firstRunAfterSecond -ne 1) { throw "Expected FIRST_RUN_AFTER_SECOND=1. got $firstRunAfterSecond" }
if ($secondRunAfterSecond -ne 1) { throw "Expected SECOND_RUN_AFTER_SECOND=1. got $secondRunAfterSecond" }
if ($secondBudgetAfterSecond -ne 3) { throw "Expected SECOND_BUDGET_AFTER_SECOND=3. got $secondBudgetAfterSecond" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_SECOND_DISPATCH_PROBE=pass'
Write-Output "FIRST_RUN_AFTER_SECOND=$firstRunAfterSecond"
Write-Output "SECOND_RUN_AFTER_SECOND=$secondRunAfterSecond"
Write-Output "SECOND_BUDGET_AFTER_SECOND=$secondBudgetAfterSecond"
