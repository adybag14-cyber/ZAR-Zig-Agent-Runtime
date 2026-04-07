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
    -SkippedReceipt 'BAREMETAL_QEMU_PANIC_RECOVERY_MODE_RECOVERY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PANIC_RECOVERY_MODE_RECOVERY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-panic-recovery-probe-check.ps1' `
    -FailureLabel 'panic-recovery'
$probeText = $probeState.Text

$recoverMode = Extract-IntValue -Text $probeText -Name 'RECOVER_MODE'
$recoverBootPhaseBefore = Extract-IntValue -Text $probeText -Name 'RECOVER_BOOT_PHASE_BEFORE'
$recoverDispatchCount = Extract-IntValue -Text $probeText -Name 'RECOVER_DISPATCH_COUNT'
$recoverRunCount = Extract-IntValue -Text $probeText -Name 'RECOVER_RUN_COUNT'

if ($null -in @($recoverMode, $recoverBootPhaseBefore, $recoverDispatchCount, $recoverRunCount)) {
    throw 'Missing expected recovery fields in panic-recovery probe output.'
}
if ($recoverMode -ne 1) { throw "Expected RECOVER_MODE=1. got $recoverMode" }
if ($recoverBootPhaseBefore -ne 255) { throw "Expected RECOVER_BOOT_PHASE_BEFORE=255. got $recoverBootPhaseBefore" }
if ($recoverDispatchCount -ne 2) { throw "Expected RECOVER_DISPATCH_COUNT=2. got $recoverDispatchCount" }
if ($recoverRunCount -ne 2) { throw "Expected RECOVER_RUN_COUNT=2. got $recoverRunCount" }

Write-Output 'BAREMETAL_QEMU_PANIC_RECOVERY_MODE_RECOVERY_PROBE=pass'
Write-Output "RECOVER_MODE=$recoverMode"
Write-Output "RECOVER_BOOT_PHASE_BEFORE=$recoverBootPhaseBefore"
Write-Output "RECOVER_DISPATCH_COUNT=$recoverDispatchCount"
Write-Output "RECOVER_RUN_COUNT=$recoverRunCount"
