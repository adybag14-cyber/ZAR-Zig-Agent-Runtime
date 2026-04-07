# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-disable-enable-probe-check.ps1"
$schedulerNoSlot = 255
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_DISABLED_FREEZE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_DISABLED_FREEZE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-disable-enable-probe-check.ps1' `
    -FailureLabel 'scheduler-disable-enable'
$probeText = $probeState.Text

$disabledEnabled = Extract-IntValue -Text $probeText -Name 'DISABLED_ENABLED'
$disabledSlot = Extract-IntValue -Text $probeText -Name 'DISABLED_RUNNING_SLOT'
$disabledDispatch = Extract-IntValue -Text $probeText -Name 'DISABLED_DISPATCH_COUNT'
$disabledRun = Extract-IntValue -Text $probeText -Name 'DISABLED_RUN_COUNT'
$disabledBudget = Extract-IntValue -Text $probeText -Name 'DISABLED_BUDGET_REMAINING'

if ($null -in @($disabledEnabled, $disabledSlot, $disabledDispatch, $disabledRun, $disabledBudget)) {
    throw 'Missing expected disabled-state fields in scheduler-disable-enable probe output.'
}
if ($disabledEnabled -ne 0) { throw "Expected DISABLED_ENABLED=0. got $disabledEnabled" }
if ($disabledSlot -ne $schedulerNoSlot) { throw "Expected DISABLED_RUNNING_SLOT=255. got $disabledSlot" }
if ($disabledDispatch -ne 1) { throw "Expected DISABLED_DISPATCH_COUNT=1. got $disabledDispatch" }
if ($disabledRun -ne 1) { throw "Expected DISABLED_RUN_COUNT=1. got $disabledRun" }
if ($disabledBudget -ne 4) { throw "Expected DISABLED_BUDGET_REMAINING=4. got $disabledBudget" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_DISABLED_FREEZE_PROBE=pass'
Write-Output "DISABLED_ENABLED=$disabledEnabled"
Write-Output "DISABLED_RUNNING_SLOT=$disabledSlot"
Write-Output "DISABLED_DISPATCH_COUNT=$disabledDispatch"
Write-Output "DISABLED_RUN_COUNT=$disabledRun"
Write-Output "DISABLED_BUDGET_REMAINING=$disabledBudget"