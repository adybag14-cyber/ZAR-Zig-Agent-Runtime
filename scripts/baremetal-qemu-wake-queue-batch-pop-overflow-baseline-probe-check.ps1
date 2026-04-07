# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-batch-pop-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_OVERFLOW_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_OVERFLOW_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-batch-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue batch-pop' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$wakeCycles = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_WAKE_CYCLES'
$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_TASK_ID'
$taskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_TASK_STATE'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_TICKS'

if ($null -in @($wakeCycles, $taskId, $taskState, $ticks)) {
    throw 'Missing expected overflow-baseline fields in wake-queue-batch-pop probe output.'
}
if ($wakeCycles -ne 66) { throw "Expected WAKE_CYCLES=66. got $wakeCycles" }
if ($taskId -le 0) { throw "Expected TASK_ID > 0. got $taskId" }
if ($taskState -ne 1) { throw "Expected TASK_STATE=1. got $taskState" }
if ($ticks -lt 141) { throw "Expected TICKS >= 141. got $ticks" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_OVERFLOW_BASELINE_PROBE=pass'
Write-Output "WAKE_CYCLES=$wakeCycles"
Write-Output "TASK_ID=$taskId"
Write-Output "TASK_STATE=$taskState"
Write-Output "TICKS=$ticks"
