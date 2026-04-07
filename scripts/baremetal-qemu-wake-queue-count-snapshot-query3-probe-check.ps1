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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_QUERY3_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_QUERY3_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-count-snapshot-probe-check.ps1' `
    -FailureLabel 'wake-queue count-snapshot'
$probeText = $probeState.Text


$query2Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_QUERY2_TICK'
$query3Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_QUERY3_TICK'
$query3VectorCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_QUERY3_VECTOR_COUNT'
$query3BeforeTickCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_QUERY3_BEFORE_TICK_COUNT'
$query3ReasonVectorCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_PROBE_QUERY3_REASON_VECTOR_COUNT'

if ($null -in @($query2Tick, $query3Tick, $query3VectorCount, $query3BeforeTickCount, $query3ReasonVectorCount)) {
    throw 'Missing expected query3 fields in wake-queue-count-snapshot probe output.'
}
if ($query3VectorCount -ne 1) { throw "Expected QUERY3_VECTOR_COUNT=1. got $query3VectorCount" }
if ($query3BeforeTickCount -ne 5) { throw "Expected QUERY3_BEFORE_TICK_COUNT=5. got $query3BeforeTickCount" }
if ($query3ReasonVectorCount -ne 0) { throw "Expected QUERY3_REASON_VECTOR_COUNT=0. got $query3ReasonVectorCount" }
if ($query3Tick -lt $query2Tick) { throw "Expected QUERY3_TICK >= QUERY2_TICK. query2=$query2Tick query3=$query3Tick" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_COUNT_SNAPSHOT_QUERY3_PROBE=pass'
Write-Output "QUERY3_TICK=$query3Tick"
Write-Output "QUERY3_VECTOR_COUNT=$query3VectorCount"
Write-Output "QUERY3_BEFORE_TICK_COUNT=$query3BeforeTickCount"
Write-Output "QUERY3_REASON_VECTOR_COUNT=$query3ReasonVectorCount"
