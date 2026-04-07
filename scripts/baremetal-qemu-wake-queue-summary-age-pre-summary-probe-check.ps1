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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PRE_SUMMARY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PRE_SUMMARY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-summary-age-probe-check.ps1' `
    -FailureLabel 'wake-queue summary-age'
$probeText = $probeState.Text


$len = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_LEN'
$overflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_OVERFLOW'
$timerCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_TIMER_COUNT'
$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_INTERRUPT_COUNT'
$manualCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_MANUAL_COUNT'
$nonzeroVectorCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_NONZERO_VECTOR_COUNT'
$staleCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_STALE_COUNT'
$oldestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_OLDEST_TICK'
$newestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_NEWEST_TICK'
if ($null -in @($len,$overflow,$timerCount,$interruptCount,$manualCount,$nonzeroVectorCount,$staleCount,$oldestTick,$newestTick)) {
    throw 'Missing expected pre-summary fields in wake-queue summary/age probe output.'
}
if ($len -ne 5 -or $overflow -ne 0 -or $timerCount -ne 1 -or $interruptCount -ne 3 -or $manualCount -ne 1 -or $nonzeroVectorCount -ne 3 -or $staleCount -ne 5 -or $oldestTick -ne 8 -or $newestTick -ne 20) {
    throw "Unexpected pre-summary snapshot: len=$len overflow=$overflow timer=$timerCount interrupt=$interruptCount manual=$manualCount nonzero=$nonzeroVectorCount stale=$staleCount oldest=$oldestTick newest=$newestTick"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PRE_SUMMARY_PROBE=pass'
Write-Output "PRE_SUMMARY_LEN=$len"
Write-Output "PRE_SUMMARY_INTERRUPT_COUNT=$interruptCount"
Write-Output "PRE_SUMMARY_MANUAL_COUNT=$manualCount"
Write-Output "PRE_SUMMARY_OLDEST_TICK=$oldestTick"
Write-Output "PRE_SUMMARY_NEWEST_TICK=$newestTick"