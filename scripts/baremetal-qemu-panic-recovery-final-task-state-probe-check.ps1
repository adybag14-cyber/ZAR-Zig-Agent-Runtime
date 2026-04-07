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
    -SkippedReceipt 'BAREMETAL_QEMU_PANIC_RECOVERY_FINAL_TASK_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PANIC_RECOVERY_FINAL_TASK_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-panic-recovery-probe-check.ps1' `
    -FailureLabel 'panic-recovery'
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$mode = Extract-IntValue -Text $probeText -Name 'MODE'
$bootPhase = Extract-IntValue -Text $probeText -Name 'BOOT_PHASE'
$taskCount = Extract-IntValue -Text $probeText -Name 'TASK_COUNT'
$runningSlot = Extract-IntValue -Text $probeText -Name 'RUNNING_SLOT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'DISPATCH_COUNT'
$taskId = Extract-IntValue -Text $probeText -Name 'TASK0_ID'
$taskRunCount = Extract-IntValue -Text $probeText -Name 'TASK0_RUN_COUNT'
$taskBudgetRemaining = Extract-IntValue -Text $probeText -Name 'TASK0_BUDGET_REMAINING'

if ($null -in @($ack, $lastOpcode, $lastResult, $mode, $bootPhase, $taskCount, $runningSlot, $dispatchCount, $taskId, $taskRunCount, $taskBudgetRemaining)) {
    throw 'Missing expected final fields in panic-recovery probe output.'
}
if ($ack -ne 7) { throw "Expected ACK=7. got $ack" }
if ($lastOpcode -ne 16) { throw "Expected LAST_OPCODE=16. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($mode -ne 1) { throw "Expected MODE=1. got $mode" }
if ($bootPhase -ne 2) { throw "Expected BOOT_PHASE=2. got $bootPhase" }
if ($taskCount -ne 1) { throw "Expected TASK_COUNT=1. got $taskCount" }
if ($runningSlot -ne 0) { throw "Expected RUNNING_SLOT=0. got $runningSlot" }
if ($dispatchCount -ne 3) { throw "Expected DISPATCH_COUNT=3. got $dispatchCount" }
if ($taskId -ne 1) { throw "Expected TASK0_ID=1. got $taskId" }
if ($taskRunCount -ne 3) { throw "Expected TASK0_RUN_COUNT=3. got $taskRunCount" }
if ($taskBudgetRemaining -ne 3) { throw "Expected TASK0_BUDGET_REMAINING=3. got $taskBudgetRemaining" }

Write-Output 'BAREMETAL_QEMU_PANIC_RECOVERY_FINAL_TASK_STATE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "MODE=$mode"
Write-Output "BOOT_PHASE=$bootPhase"
Write-Output "TASK_COUNT=$taskCount"
Write-Output "RUNNING_SLOT=$runningSlot"
Write-Output "DISPATCH_COUNT=$dispatchCount"
Write-Output "TASK0_ID=$taskId"
Write-Output "TASK0_RUN_COUNT=$taskRunCount"
Write-Output "TASK0_BUDGET_REMAINING=$taskBudgetRemaining"
