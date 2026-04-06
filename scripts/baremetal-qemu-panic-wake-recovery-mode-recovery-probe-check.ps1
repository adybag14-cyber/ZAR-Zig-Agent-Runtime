# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-panic-wake-recovery-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_PANIC_WAKE_RECOVERY_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_PANIC_WAKE_RECOVERY_MODE_RECOVERY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PANIC_WAKE_RECOVERY_MODE_RECOVERY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-panic-wake-recovery-probe-check.ps1' `
    -FailureLabel 'panic-wake recovery'
$probeText = $probeState.Text

$mode = Extract-IntValue -Text $probeText -Name 'RECOVER1_MODE'
$bootPhase = Extract-IntValue -Text $probeText -Name 'RECOVER1_BOOT_PHASE'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'RECOVER1_DISPATCH_COUNT'
$runningSlot = Extract-IntValue -Text $probeText -Name 'RECOVER1_RUNNING_SLOT'
$task0RunCount = Extract-IntValue -Text $probeText -Name 'RECOVER1_TASK0_RUN_COUNT'
$task0BudgetRemaining = Extract-IntValue -Text $probeText -Name 'RECOVER1_TASK0_BUDGET_REMAINING'

if ($null -in @($mode, $bootPhase, $dispatchCount, $runningSlot, $task0RunCount, $task0BudgetRemaining)) {
    throw 'Missing expected mode-recovery fields in panic-wake recovery probe output.'
}
if ($mode -ne 1) { throw "Expected RECOVER1_MODE=1. got $mode" }
if ($bootPhase -ne 255) { throw "Expected RECOVER1_BOOT_PHASE=255. got $bootPhase" }
if ($dispatchCount -ne 1) { throw "Expected RECOVER1_DISPATCH_COUNT=1. got $dispatchCount" }
if ($runningSlot -ne 0) { throw "Expected RECOVER1_RUNNING_SLOT=0. got $runningSlot" }
if ($task0RunCount -ne 1) { throw "Expected RECOVER1_TASK0_RUN_COUNT=1. got $task0RunCount" }
if ($task0BudgetRemaining -ne 5) { throw "Expected RECOVER1_TASK0_BUDGET_REMAINING=5. got $task0BudgetRemaining" }

Write-Output 'BAREMETAL_QEMU_PANIC_WAKE_RECOVERY_MODE_RECOVERY_PROBE=pass'
Write-Output "RECOVER1_MODE=$mode"
Write-Output "RECOVER1_BOOT_PHASE=$bootPhase"
Write-Output "RECOVER1_DISPATCH_COUNT=$dispatchCount"
Write-Output "RECOVER1_RUNNING_SLOT=$runningSlot"
Write-Output "RECOVER1_TASK0_RUN_COUNT=$task0RunCount"
Write-Output "RECOVER1_TASK0_BUDGET_REMAINING=$task0BudgetRemaining"