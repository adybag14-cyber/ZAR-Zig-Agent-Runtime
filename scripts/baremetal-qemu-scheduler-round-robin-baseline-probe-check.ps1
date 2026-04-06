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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-round-robin-probe-check.ps1' `
    -FailureLabel 'scheduler-round-robin'
$probeText = $probeState.Text

$taskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_TASK_COUNT'
$policy = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_POLICY'
$firstId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_ID'
$secondId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_SECOND_ID'
$firstState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_STATE'
$secondState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_SECOND_STATE'
$firstPriority = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_PRIORITY'
$secondPriority = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_SECOND_PRIORITY'
$firstBudgetTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_FIRST_BUDGET_TICKS'
$secondBudgetTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_SECOND_BUDGET_TICKS'

if ($null -in @($taskCount, $policy, $firstId, $secondId, $firstState, $secondState, $firstPriority, $secondPriority, $firstBudgetTicks, $secondBudgetTicks)) {
    throw 'Missing expected baseline fields in scheduler-round-robin probe output.'
}
if ($taskCount -ne 2) { throw "Expected TASK_COUNT=2. got $taskCount" }
if ($policy -ne 0) { throw "Expected POLICY=0. got $policy" }
if ($firstId -le 0) { throw "Expected FIRST_ID > 0. got $firstId" }
if ($secondId -le $firstId) { throw "Expected SECOND_ID > FIRST_ID. got FIRST_ID=$firstId SECOND_ID=$secondId" }
if ($firstState -ne 1) { throw "Expected FIRST_STATE=1. got $firstState" }
if ($secondState -ne 1) { throw "Expected SECOND_STATE=1. got $secondState" }
if ($firstPriority -ne 1) { throw "Expected FIRST_PRIORITY=1. got $firstPriority" }
if ($secondPriority -ne 9) { throw "Expected SECOND_PRIORITY=9. got $secondPriority" }
if ($firstBudgetTicks -ne 4) { throw "Expected FIRST_BUDGET_TICKS=4. got $firstBudgetTicks" }
if ($secondBudgetTicks -ne 4) { throw "Expected SECOND_BUDGET_TICKS=4. got $secondBudgetTicks" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_ROUND_ROBIN_BASELINE_PROBE=pass'
Write-Output "TASK_COUNT=$taskCount"
Write-Output "POLICY=$policy"
Write-Output "FIRST_ID=$firstId"
Write-Output "SECOND_ID=$secondId"
Write-Output "FIRST_STATE=$firstState"
Write-Output "SECOND_STATE=$secondState"
Write-Output "FIRST_PRIORITY=$firstPriority"
Write-Output "SECOND_PRIORITY=$secondPriority"
Write-Output "FIRST_BUDGET_TICKS=$firstBudgetTicks"
Write-Output "SECOND_BUDGET_TICKS=$secondBudgetTicks"
