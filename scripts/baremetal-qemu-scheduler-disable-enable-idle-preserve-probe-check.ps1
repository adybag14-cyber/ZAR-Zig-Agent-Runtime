# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-disable-enable-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_IDLE_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_IDLE_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-disable-enable-probe-check.ps1' `
    -FailureLabel 'scheduler-disable-enable'
$probeText = $probeState.Text

$idleTicks = Extract-IntValue -Text $probeText -Name 'IDLE_DISABLED_TICKS'
$idleDispatch = Extract-IntValue -Text $probeText -Name 'IDLE_DISABLED_DISPATCH_COUNT'
$idleRun = Extract-IntValue -Text $probeText -Name 'IDLE_DISABLED_RUN_COUNT'
$idleBudget = Extract-IntValue -Text $probeText -Name 'IDLE_DISABLED_BUDGET_REMAINING'

if ($null -in @($idleTicks, $idleDispatch, $idleRun, $idleBudget)) {
    throw 'Missing expected idle-disabled fields in scheduler-disable-enable probe output.'
}
if ($idleTicks -lt 5) { throw "Expected IDLE_DISABLED_TICKS>=5. got $idleTicks" }
if ($idleDispatch -ne 1) { throw "Expected IDLE_DISABLED_DISPATCH_COUNT=1. got $idleDispatch" }
if ($idleRun -ne 1) { throw "Expected IDLE_DISABLED_RUN_COUNT=1. got $idleRun" }
if ($idleBudget -ne 4) { throw "Expected IDLE_DISABLED_BUDGET_REMAINING=4. got $idleBudget" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_DISABLE_ENABLE_IDLE_PRESERVE_PROBE=pass'
Write-Output "IDLE_DISABLED_TICKS=$idleTicks"
Write-Output "IDLE_DISABLED_DISPATCH_COUNT=$idleDispatch"
Write-Output "IDLE_DISABLED_RUN_COUNT=$idleRun"
Write-Output "IDLE_DISABLED_BUDGET_REMAINING=$idleBudget"