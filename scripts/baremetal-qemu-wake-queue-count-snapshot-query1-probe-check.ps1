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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_QUERY1_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_QUERY1_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-count-snapshot-probe-check.ps1' `
    -FailureLabel 'wake-queue count-snapshot'
$probeText = $probeState.Text


$query1Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_QUERY1_TICK'
$query1VectorCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_QUERY1_VECTOR_COUNT'
$query1BeforeTickCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_QUERY1_BEFORE_TICK_COUNT'
$query1ReasonVectorCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_QUERY1_REASON_VECTOR_COUNT'
$preOldestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_PRE_OLDEST_TICK'
$preNewestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_PRE_NEWEST_TICK'

if ($null -in @($query1Tick, $query1VectorCount, $query1BeforeTickCount, $query1ReasonVectorCount, $preOldestTick, $preNewestTick)) {
    throw 'Missing expected query1 fields in wake-queue-count-snapshot probe output.'
}
if ($query1VectorCount -ne 2) { throw "Expected QUERY1_VECTOR_COUNT=2. got $query1VectorCount" }
if ($query1BeforeTickCount -ne 2) { throw "Expected QUERY1_BEFORE_TICK_COUNT=2. got $query1BeforeTickCount" }
if ($query1ReasonVectorCount -ne 2) { throw "Expected QUERY1_REASON_VECTOR_COUNT=2. got $query1ReasonVectorCount" }
if ($query1Tick -lt $preOldestTick -or $query1Tick -gt $preNewestTick) {
    throw "Expected QUERY1_TICK within baseline range. oldest=$preOldestTick query1=$query1Tick newest=$preNewestTick"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_QUERY1_PROBE=pass'
Write-Output "QUERY1_TICK=$query1Tick"
Write-Output "QUERY1_VECTOR_COUNT=$query1VectorCount"
Write-Output "QUERY1_BEFORE_TICK_COUNT=$query1BeforeTickCount"
Write-Output "QUERY1_REASON_VECTOR_COUNT=$query1ReasonVectorCount"
