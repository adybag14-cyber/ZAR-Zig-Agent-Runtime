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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_DISPATCH_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_DISPATCH_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-round-robin-probe-check.ps1' `
    -FailureLabel 'scheduler-round-robin'
$probeText = $probeState.Text

$firstRunAfterFirst = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_RUN_AFTER_FIRST'
$secondRunAfterFirst = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_SECOND_RUN_AFTER_FIRST'
$firstBudgetAfterFirst = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_BUDGET_AFTER_FIRST'

if ($null -in @($firstRunAfterFirst, $secondRunAfterFirst, $firstBudgetAfterFirst)) {
    throw 'Missing expected first-dispatch fields in scheduler-round-robin probe output.'
}
if ($firstRunAfterFirst -ne 1) { throw "Expected FIRST_RUN_AFTER_FIRST=1. got $firstRunAfterFirst" }
if ($secondRunAfterFirst -ne 0) { throw "Expected SECOND_RUN_AFTER_FIRST=0. got $secondRunAfterFirst" }
if ($firstBudgetAfterFirst -ne 3) { throw "Expected FIRST_BUDGET_AFTER_FIRST=3. got $firstBudgetAfterFirst" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_DISPATCH_PROBE=pass'
Write-Output "FIRST_RUN_AFTER_FIRST=$firstRunAfterFirst"
Write-Output "SECOND_RUN_AFTER_FIRST=$secondRunAfterFirst"
Write-Output "FIRST_BUDGET_AFTER_FIRST=$firstBudgetAfterFirst"
