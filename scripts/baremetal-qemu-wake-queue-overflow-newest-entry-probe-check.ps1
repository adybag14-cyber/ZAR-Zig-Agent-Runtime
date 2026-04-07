# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_ENTRY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_ENTRY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_TASK_ID'
$oldestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_TICK'
$newestSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_SEQ'
$newestTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_TASK_ID'
$newestReason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_REASON'
$newestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_TICK'

if ($null -in @($taskId, $oldestTick, $newestSeq, $newestTaskId, $newestReason, $newestTick)) {
    throw 'Missing expected newest-entry fields in wake-queue-overflow probe output.'
}
if ($newestSeq -ne 66) { throw "Expected NEWEST_SEQ=66. got $newestSeq" }
if ($newestTaskId -ne $taskId) { throw "Expected NEWEST_TASK_ID=$taskId. got $newestTaskId" }
if ($newestReason -ne 3) { throw "Expected NEWEST_REASON=3. got $newestReason" }
if ($newestTick -le $oldestTick) { throw "Expected NEWEST_TICK > OLDEST_TICK. got oldest=$oldestTick newest=$newestTick" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_NEWEST_ENTRY_PROBE=pass'
Write-Output "NEWEST_SEQ=$newestSeq"
Write-Output "NEWEST_TASK_ID=$newestTaskId"
Write-Output "NEWEST_REASON=$newestReason"
Write-Output "NEWEST_TICK=$newestTick"
