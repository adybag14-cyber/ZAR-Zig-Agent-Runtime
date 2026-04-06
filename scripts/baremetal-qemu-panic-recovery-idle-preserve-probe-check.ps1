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
    -SkippedReceipt 'BAREMETAL_QEMU_PANIC_RECOVERY_IDLE_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PANIC_RECOVERY_IDLE_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-panic-recovery-probe-check.ps1' `
    -FailureLabel 'panic-recovery'
$probeText = $probeState.Text

$idleTicks = Extract-IntValue -Text $probeText -Name 'IDLE_PANIC_TICKS'
$idleDispatchCount = Extract-IntValue -Text $probeText -Name 'IDLE_PANIC_DISPATCH_COUNT'
$idleRunCount = Extract-IntValue -Text $probeText -Name 'IDLE_PANIC_RUN_COUNT'

if ($null -in @($idleTicks, $idleDispatchCount, $idleRunCount)) {
    throw 'Missing expected idle panic fields in panic-recovery probe output.'
}
if ($idleTicks -lt 1) { throw "Expected IDLE_PANIC_TICKS>=1. got $idleTicks" }
if ($idleDispatchCount -ne 1) { throw "Expected IDLE_PANIC_DISPATCH_COUNT=1. got $idleDispatchCount" }
if ($idleRunCount -ne 1) { throw "Expected IDLE_PANIC_RUN_COUNT=1. got $idleRunCount" }

Write-Output 'BAREMETAL_QEMU_PANIC_RECOVERY_IDLE_PRESERVE_PROBE=pass'
Write-Output "IDLE_PANIC_TICKS=$idleTicks"
Write-Output "IDLE_PANIC_DISPATCH_COUNT=$idleDispatchCount"
Write-Output "IDLE_PANIC_RUN_COUNT=$idleRunCount"
