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
    -SkippedReceipt 'BAREMETAL_QEMU_PANIC_RECOVERY_FREEZE_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PANIC_RECOVERY_FREEZE_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-panic-recovery-probe-check.ps1' `
    -FailureLabel 'panic-recovery'
$probeText = $probeState.Text

$panicMode = Extract-IntValue -Text $probeText -Name 'PANIC_MODE'
$panicCount = Extract-IntValue -Text $probeText -Name 'PANIC_COUNT'
$panicBootPhase = Extract-IntValue -Text $probeText -Name 'PANIC_BOOT_PHASE'
$panicRunningSlot = Extract-IntValue -Text $probeText -Name 'PANIC_RUNNING_SLOT'
$panicDispatchCount = Extract-IntValue -Text $probeText -Name 'PANIC_DISPATCH_COUNT'

if ($null -in @($panicMode, $panicCount, $panicBootPhase, $panicRunningSlot, $panicDispatchCount)) {
    throw 'Missing expected panic freeze-state fields in panic-recovery probe output.'
}
if ($panicMode -ne 255) { throw "Expected PANIC_MODE=255. got $panicMode" }
if ($panicCount -ne 1) { throw "Expected PANIC_COUNT=1. got $panicCount" }
if ($panicBootPhase -ne 255) { throw "Expected PANIC_BOOT_PHASE=255. got $panicBootPhase" }
if ($panicRunningSlot -ne 255) { throw "Expected PANIC_RUNNING_SLOT=255. got $panicRunningSlot" }
if ($panicDispatchCount -ne 1) { throw "Expected PANIC_DISPATCH_COUNT=1. got $panicDispatchCount" }

Write-Output 'BAREMETAL_QEMU_PANIC_RECOVERY_FREEZE_STATE_PROBE=pass'
Write-Output "PANIC_MODE=$panicMode"
Write-Output "PANIC_COUNT=$panicCount"
Write-Output "PANIC_BOOT_PHASE=$panicBootPhase"
Write-Output "PANIC_RUNNING_SLOT=$panicRunningSlot"
Write-Output "PANIC_DISPATCH_COUNT=$panicDispatchCount"
