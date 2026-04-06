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
    -SkippedReceipt 'BAREMETAL_QEMU_PANIC_WAKE_RECOVERY_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PANIC_WAKE_RECOVERY_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-panic-wake-recovery-probe-check.ps1' `
    -FailureLabel 'panic-wake recovery'
$probeText = $probeState.Text

$taskCount = Extract-IntValue -Text $probeText -Name 'PRE_PANIC_TASK_COUNT'
$runningSlot = Extract-IntValue -Text $probeText -Name 'PRE_PANIC_RUNNING_SLOT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'PRE_PANIC_DISPATCH_COUNT'
$task0State = Extract-IntValue -Text $probeText -Name 'PRE_PANIC_TASK0_STATE'
$task1State = Extract-IntValue -Text $probeText -Name 'PRE_PANIC_TASK1_STATE'
$timerCount = Extract-IntValue -Text $probeText -Name 'PRE_PANIC_TIMER_COUNT'

if ($null -in @($taskCount, $runningSlot, $dispatchCount, $task0State, $task1State, $timerCount)) {
    throw 'Missing expected baseline fields in panic-wake recovery probe output.'
}
if ($taskCount -ne 0) { throw "Expected PRE_PANIC_TASK_COUNT=0. got $taskCount" }
if ($runningSlot -ne 255) { throw "Expected PRE_PANIC_RUNNING_SLOT=255. got $runningSlot" }
if ($dispatchCount -ne 0) { throw "Expected PRE_PANIC_DISPATCH_COUNT=0. got $dispatchCount" }
if ($task0State -ne 6) { throw "Expected PRE_PANIC_TASK0_STATE=6. got $task0State" }
if ($task1State -ne 6) { throw "Expected PRE_PANIC_TASK1_STATE=6. got $task1State" }
if ($timerCount -ne 1) { throw "Expected PRE_PANIC_TIMER_COUNT=1. got $timerCount" }

Write-Output 'BAREMETAL_QEMU_PANIC_WAKE_RECOVERY_BASELINE_PROBE=pass'
Write-Output "PRE_PANIC_TASK_COUNT=$taskCount"
Write-Output "PRE_PANIC_RUNNING_SLOT=$runningSlot"
Write-Output "PRE_PANIC_DISPATCH_COUNT=$dispatchCount"
Write-Output "PRE_PANIC_TASK0_STATE=$task0State"
Write-Output "PRE_PANIC_TASK1_STATE=$task1State"
Write-Output "PRE_PANIC_TIMER_COUNT=$timerCount"