# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-saturation-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_SATURATION_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSE_STATE_PROBE' `
    -FailureLabel 'scheduler saturation' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$lastTaskId = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_LAST_TASK_ID"
$newTaskId = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSED_SLOT_NEW_ID"
$reusedPriority = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSED_PRIORITY"
$reusedBudget = Get-Int "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSED_BUDGET_TICKS"

if ($newTaskId -le $lastTaskId) { throw "Expected REUSED_SLOT_NEW_ID > LAST_TASK_ID, got NEW=$newTaskId LAST=$lastTaskId" }
if ($reusedPriority -ne 99) { throw "Expected REUSED_PRIORITY=99, got $reusedPriority" }
if ($reusedBudget -ne 7) { throw "Expected REUSED_BUDGET_TICKS=7, got $reusedBudget" }

Write-Output "BAREMETAL_QEMU_SCHEDULER_SATURATION_REUSE_STATE_PROBE=pass"
Write-Output "LAST_TASK_ID=$lastTaskId"
Write-Output "REUSED_SLOT_NEW_ID=$newTaskId"
Write-Output "REUSED_PRIORITY=$reusedPriority"
Write-Output "REUSED_BUDGET_TICKS=$reusedBudget"
