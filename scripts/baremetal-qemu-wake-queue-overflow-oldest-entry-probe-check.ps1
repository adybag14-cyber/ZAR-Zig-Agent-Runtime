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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_ENTRY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_ENTRY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_TASK_ID'
$oldestSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_SEQ'
$oldestTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_TASK_ID'
$oldestReason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_REASON'
$oldestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_TICK'

if ($null -in @($taskId, $oldestSeq, $oldestTaskId, $oldestReason, $oldestTick)) {
    throw 'Missing expected oldest-entry fields in wake-queue-overflow probe output.'
}
if ($oldestSeq -ne 3) { throw "Expected OLDEST_SEQ=3. got $oldestSeq" }
if ($oldestTaskId -ne $taskId) { throw "Expected OLDEST_TASK_ID=$taskId. got $oldestTaskId" }
if ($oldestReason -ne 3) { throw "Expected OLDEST_REASON=3. got $oldestReason" }
if ($oldestTick -le 0) { throw "Expected OLDEST_TICK > 0. got $oldestTick" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_ENTRY_PROBE=pass'
Write-Output "OLDEST_SEQ=$oldestSeq"
Write-Output "OLDEST_TASK_ID=$oldestTaskId"
Write-Output "OLDEST_REASON=$oldestReason"
Write-Output "OLDEST_TICK=$oldestTick"
