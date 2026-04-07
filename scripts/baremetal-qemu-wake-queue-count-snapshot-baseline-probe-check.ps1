# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-count-snapshot-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-count-snapshot-probe-check.ps1' `
    -FailureLabel 'wake-queue count-snapshot'
$probeText = $probeState.Text


$preLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_PRE_LEN'
$preTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_PRE_TASK0'
$preTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_PRE_TASK1'
$preTask2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_PRE_TASK2'
$preTask3 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_PRE_TASK3'
$preTask4 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_PRE_TASK4'
$preOldestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_PRE_OLDEST_TICK'
$preNewestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_PRE_NEWEST_TICK'

if ($null -in @($preLen, $preTask0, $preTask1, $preTask2, $preTask3, $preTask4, $preOldestTick, $preNewestTick)) {
    throw 'Missing expected baseline fields in wake-queue-count-snapshot probe output.'
}
if ($preLen -ne 5) { throw "Expected PRE_LEN=5. got $preLen" }
if ($preTask0 -ne 1 -or $preTask1 -ne 2 -or $preTask2 -ne 3 -or $preTask3 -ne 4 -or $preTask4 -ne 5) {
    throw "Unexpected baseline task ordering: $preTask0,$preTask1,$preTask2,$preTask3,$preTask4"
}
if ($preOldestTick -ne 8) { throw "Expected PRE_OLDEST_TICK=8. got $preOldestTick" }
if ($preNewestTick -ne 20) { throw "Expected PRE_NEWEST_TICK=20. got $preNewestTick" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_BASELINE_PROBE=pass'
Write-Output "PRE_LEN=$preLen"
Write-Output "PRE_TASK0=$preTask0"
Write-Output "PRE_TASK1=$preTask1"
Write-Output "PRE_TASK2=$preTask2"
Write-Output "PRE_TASK3=$preTask3"
Write-Output "PRE_TASK4=$preTask4"
Write-Output "PRE_OLDEST_TICK=$preOldestTick"
Write-Output "PRE_NEWEST_TICK=$preNewestTick"
