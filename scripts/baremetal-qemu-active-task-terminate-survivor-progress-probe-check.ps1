# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-active-task-terminate-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_SURVIVOR_PROGRESS_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_SURVIVOR_PROGRESS_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-active-task-terminate-probe-check.ps1' `
    -FailureLabel 'active-task terminate'
$probeText = $probeState.Text

$lowRun = Extract-IntValue -Text $probeText -Name 'REPEAT_TERMINATE_LOW_RUN'
$lowBudget = Extract-IntValue -Text $probeText -Name 'REPEAT_TERMINATE_LOW_BUDGET_REMAINING'
if ($null -in @($lowRun, $lowBudget)) {
    throw 'Missing repeat survivor progress fields in active-task terminate probe output.'
}
if ($lowRun -ne 2) { throw "Expected REPEAT_TERMINATE_LOW_RUN=2. got $lowRun" }
if ($lowBudget -ne 4) { throw "Expected REPEAT_TERMINATE_LOW_BUDGET_REMAINING=4. got $lowBudget" }

Write-Output 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_SURVIVOR_PROGRESS_PROBE=pass'
Write-Output "REPEAT_TERMINATE_LOW_RUN=$lowRun"
Write-Output "REPEAT_TERMINATE_LOW_BUDGET_REMAINING=$lowBudget"
