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
    -SkippedReceipt 'BAREMETAL_QEMU_PANIC_WAKE_RECOVERY_FREEZE_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PANIC_WAKE_RECOVERY_FREEZE_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-panic-wake-recovery-probe-check.ps1' `
    -FailureLabel 'panic-wake recovery'
$probeText = $probeState.Text

$lastOpcode = Extract-IntValue -Text $probeText -Name 'PANIC_FREEZE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'PANIC_FREEZE_LAST_RESULT'
$mode = Extract-IntValue -Text $probeText -Name 'PANIC_FREEZE_MODE'
$bootPhase = Extract-IntValue -Text $probeText -Name 'PANIC_FREEZE_BOOT_PHASE'
$panicCount = Extract-IntValue -Text $probeText -Name 'PANIC_FREEZE_PANIC_COUNT'
$taskCount = Extract-IntValue -Text $probeText -Name 'PANIC_FREEZE_TASK_COUNT'
$runningSlot = Extract-IntValue -Text $probeText -Name 'PANIC_FREEZE_RUNNING_SLOT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'PANIC_FREEZE_DISPATCH_COUNT'

if ($null -in @($lastOpcode, $lastResult, $mode, $bootPhase, $panicCount, $taskCount, $runningSlot, $dispatchCount)) {
    throw 'Missing expected freeze-state fields in panic-wake recovery probe output.'
}
if ($lastOpcode -ne 5) { throw "Expected PANIC_FREEZE_LAST_OPCODE=5. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected PANIC_FREEZE_LAST_RESULT=0. got $lastResult" }
if ($mode -ne 255) { throw "Expected PANIC_FREEZE_MODE=255. got $mode" }
if ($bootPhase -ne 255) { throw "Expected PANIC_FREEZE_BOOT_PHASE=255. got $bootPhase" }
if ($panicCount -ne 1) { throw "Expected PANIC_FREEZE_PANIC_COUNT=1. got $panicCount" }
if ($taskCount -ne 0) { throw "Expected PANIC_FREEZE_TASK_COUNT=0. got $taskCount" }
if ($runningSlot -ne 255) { throw "Expected PANIC_FREEZE_RUNNING_SLOT=255. got $runningSlot" }
if ($dispatchCount -ne 0) { throw "Expected PANIC_FREEZE_DISPATCH_COUNT=0. got $dispatchCount" }

Write-Output 'BAREMETAL_QEMU_PANIC_WAKE_RECOVERY_FREEZE_STATE_PROBE=pass'
Write-Output "PANIC_FREEZE_LAST_OPCODE=$lastOpcode"
Write-Output "PANIC_FREEZE_LAST_RESULT=$lastResult"
Write-Output "PANIC_FREEZE_MODE=$mode"
Write-Output "PANIC_FREEZE_BOOT_PHASE=$bootPhase"
Write-Output "PANIC_FREEZE_PANIC_COUNT=$panicCount"
Write-Output "PANIC_FREEZE_TASK_COUNT=$taskCount"
Write-Output "PANIC_FREEZE_RUNNING_SLOT=$runningSlot"
Write-Output "PANIC_FREEZE_DISPATCH_COUNT=$dispatchCount"