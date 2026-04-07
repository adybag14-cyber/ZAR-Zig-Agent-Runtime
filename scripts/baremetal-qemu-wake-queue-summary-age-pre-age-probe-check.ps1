# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-summary-age-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PRE_AGE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PRE_AGE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-summary-age-probe-check.ps1' `
    -FailureLabel 'wake-queue summary-age'
$probeText = $probeState.Text


$currentTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_AGE_CURRENT_TICK'
$quantum = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_AGE_QUANTUM_TICKS'
$stale = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_AGE_STALE_COUNT'
$oldStale = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_AGE_STALE_OLDER_THAN_QUANTUM_COUNT'
$future = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_AGE_FUTURE_COUNT'
if ($null -in @($currentTick,$quantum,$stale,$oldStale,$future)) {
    throw 'Missing expected pre-age fields in wake-queue summary/age probe output.'
}
if ($currentTick -ne 21 -or $quantum -ne 2 -or $stale -ne 5 -or $oldStale -ne 4 -or $future -ne 0) {
    throw "Unexpected pre-age snapshot: current=$currentTick quantum=$quantum stale=$stale oldStale=$oldStale future=$future"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PRE_AGE_PROBE=pass'
Write-Output "PRE_AGE_CURRENT_TICK=$currentTick"
Write-Output "PRE_AGE_QUANTUM_TICKS=$quantum"
Write-Output "PRE_AGE_STALE_COUNT=$stale"
Write-Output "PRE_AGE_STALE_OLDER_THAN_QUANTUM_COUNT=$oldStale"
Write-Output "PRE_AGE_FUTURE_COUNT=$future"