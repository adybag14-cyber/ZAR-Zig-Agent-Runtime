# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-before-tick-overflow-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-before-tick-overflow-probe-check.ps1' `
    -FailureLabel 'wake-queue before-tick overflow' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$wakeCycles = Extract-IntValue -Text $probeText -Name 'WAKE_CYCLES'
$taskId = Extract-IntValue -Text $probeText -Name 'TASK_ID'
$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
$preCount = Extract-IntValue -Text $probeText -Name 'PRE_COUNT'
$preHead = Extract-IntValue -Text $probeText -Name 'PRE_HEAD'
$preTail = Extract-IntValue -Text $probeText -Name 'PRE_TAIL'
$preOverflow = Extract-IntValue -Text $probeText -Name 'PRE_OVERFLOW'

if ($null -in @($wakeCycles, $taskId, $ticks, $preCount, $preHead, $preTail, $preOverflow)) {
    throw 'Missing expected baseline fields in wake-queue before-tick overflow probe output.'
}
if ($wakeCycles -ne 66) { throw "Expected WAKE_CYCLES=66. got $wakeCycles" }
if ($taskId -ne 1) { throw "Expected TASK_ID=1. got $taskId" }
if ($ticks -lt 136) { throw "Expected TICKS >= 136. got $ticks" }
if ($preCount -ne 64) { throw "Expected PRE_COUNT=64. got $preCount" }
if ($preHead -ne 2) { throw "Expected PRE_HEAD=2. got $preHead" }
if ($preTail -ne 2) { throw "Expected PRE_TAIL=2. got $preTail" }
if ($preOverflow -ne 2) { throw "Expected PRE_OVERFLOW=2. got $preOverflow" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_OVERFLOW_BASELINE_PROBE=pass'
Write-Output "WAKE_CYCLES=$wakeCycles"
Write-Output "TASK_ID=$taskId"
Write-Output "TICKS=$ticks"
Write-Output "PRE_COUNT=$preCount"
Write-Output "PRE_HEAD=$preHead"
Write-Output "PRE_TAIL=$preTail"
Write-Output "PRE_OVERFLOW=$preOverflow"
