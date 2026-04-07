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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_POST_SUMMARY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_POST_SUMMARY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-summary-age-probe-check.ps1' `
    -FailureLabel 'wake-queue summary-age'
$probeText = $probeState.Text


$postLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_LEN'
$postTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_TASK0'
$postTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_TASK1'
$postTask2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_TASK2'
$postTask3 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_TASK3'
$len = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_LEN'
$overflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_OVERFLOW'
$timerCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_TIMER_COUNT'
$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_INTERRUPT_COUNT'
$manualCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_MANUAL_COUNT'
$nonzeroVectorCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_NONZERO_VECTOR_COUNT'
$staleCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_STALE_COUNT'
$oldestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_OLDEST_TICK'
$newestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_POST_SUMMARY_NEWEST_TICK'
if ($null -in @($postLen,$postTask0,$postTask1,$postTask2,$postTask3,$len,$overflow,$timerCount,$interruptCount,$manualCount,$nonzeroVectorCount,$staleCount,$oldestTick,$newestTick)) {
    throw 'Missing expected post-summary fields in wake-queue summary/age probe output.'
}
if ($postLen -ne 4 -or $postTask0 -ne 1 -or $postTask1 -ne 3 -or $postTask2 -ne 4 -or $postTask3 -ne 5) {
    throw "Unexpected post-drain task ordering: len=$postLen tasks=$postTask0,$postTask1,$postTask2,$postTask3"
}
if ($len -ne 4 -or $overflow -ne 0 -or $timerCount -ne 1 -or $interruptCount -ne 2 -or $manualCount -ne 1 -or $nonzeroVectorCount -ne 2 -or $staleCount -ne 4 -or $oldestTick -ne 8 -or $newestTick -ne 20) {
    throw "Unexpected post-summary snapshot: len=$len overflow=$overflow timer=$timerCount interrupt=$interruptCount manual=$manualCount nonzero=$nonzeroVectorCount stale=$staleCount oldest=$oldestTick newest=$newestTick"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_POST_SUMMARY_PROBE=pass'
Write-Output "POST_LEN=$postLen"
Write-Output "POST_TASK0=$postTask0"
Write-Output "POST_TASK1=$postTask1"
Write-Output "POST_TASK2=$postTask2"
Write-Output "POST_TASK3=$postTask3"
Write-Output "POST_SUMMARY_INTERRUPT_COUNT=$interruptCount"
Write-Output "POST_SUMMARY_MANUAL_COUNT=$manualCount"