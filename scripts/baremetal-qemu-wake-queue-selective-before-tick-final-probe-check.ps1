# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-selective-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_BEFORE_TICK_FINAL_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_BEFORE_TICK_FINAL_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-selective-probe-check.ps1' `
    -FailureLabel 'wake-queue selective'
$probeText = $probeState.Text


$postBeforeTickLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_BEFORE_TICK_LEN'
$preBeforeTickCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_PRE_BEFORE_TICK_COUNT'
$postBeforeTickCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_POST_BEFORE_TICK_COUNT'
$invalidReasonVectorResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_INVALID_REASON_VECTOR_RESULT'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_WAKE_QUEUE_COUNT'
$wake0TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_WAKE0_TASK_ID'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_WAKE0_REASON'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_PROBE_WAKE0_VECTOR'
if ($null -in @($postBeforeTickLen,$preBeforeTickCount,$postBeforeTickCount,$invalidReasonVectorResult,$wakeQueueCount,$wake0TaskId,$wake0Reason,$wake0Vector)) {
    throw 'Missing expected before-tick final fields in wake-queue selective probe output.'
}
if ($postBeforeTickLen -ne 1) { throw "Expected POST_BEFORE_TICK_LEN=1. got $postBeforeTickLen" }
if ($preBeforeTickCount -ne 1 -or $postBeforeTickCount -ne 0) {
    throw "Unexpected before-tick counts: pre=$preBeforeTickCount post=$postBeforeTickCount"
}
if ($invalidReasonVectorResult -ne -22) { throw "Expected INVALID_REASON_VECTOR_RESULT=-22. got $invalidReasonVectorResult" }
if ($wakeQueueCount -ne 1) { throw "Expected WAKE_QUEUE_COUNT=1. got $wakeQueueCount" }
if ($wake0TaskId -ne 5 -or $wake0Reason -ne 3 -or $wake0Vector -ne 0) {
    throw "Unexpected final wake payload: task=$wake0TaskId reason=$wake0Reason vector=$wake0Vector"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SELECTIVE_BEFORE_TICK_FINAL_PROBE=pass'
Write-Output "POST_BEFORE_TICK_LEN=$postBeforeTickLen"
Write-Output "PRE_BEFORE_TICK_COUNT=$preBeforeTickCount"
Write-Output "POST_BEFORE_TICK_COUNT=$postBeforeTickCount"
Write-Output "INVALID_REASON_VECTOR_RESULT=$invalidReasonVectorResult"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
Write-Output "WAKE0_TASK_ID=$wake0TaskId"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
