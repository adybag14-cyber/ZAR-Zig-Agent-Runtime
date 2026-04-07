# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-panic-recovery-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_PANIC_RECOVERY_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_PANIC_RECOVERY_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PANIC_RECOVERY_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-panic-recovery-probe-check.ps1' `
    -FailureLabel 'panic-recovery'
$probeText = $probeState.Text

$taskCount = Extract-IntValue -Text $probeText -Name 'PRE_PANIC_TASK_COUNT'
$runningSlot = Extract-IntValue -Text $probeText -Name 'PRE_PANIC_RUNNING_SLOT'
$runCount = Extract-IntValue -Text $probeText -Name 'PRE_PANIC_RUN_COUNT'
$budgetRemaining = Extract-IntValue -Text $probeText -Name 'PRE_PANIC_BUDGET_REMAINING'

if ($null -in @($taskCount, $runningSlot, $runCount, $budgetRemaining)) {
    throw 'Missing expected baseline fields in panic-recovery probe output.'
}
if ($taskCount -ne 1) { throw "Expected PRE_PANIC_TASK_COUNT=1. got $taskCount" }
if ($runningSlot -ne 0) { throw "Expected PRE_PANIC_RUNNING_SLOT=0. got $runningSlot" }
if ($runCount -ne 1) { throw "Expected PRE_PANIC_RUN_COUNT=1. got $runCount" }
if ($budgetRemaining -ne 5) { throw "Expected PRE_PANIC_BUDGET_REMAINING=5. got $budgetRemaining" }

Write-Output 'BAREMETAL_QEMU_PANIC_RECOVERY_BASELINE_PROBE=pass'
Write-Output "PRE_PANIC_TASK_COUNT=$taskCount"
Write-Output "PRE_PANIC_RUNNING_SLOT=$runningSlot"
Write-Output "PRE_PANIC_RUN_COUNT=$runCount"
Write-Output "PRE_PANIC_BUDGET_REMAINING=$budgetRemaining"
