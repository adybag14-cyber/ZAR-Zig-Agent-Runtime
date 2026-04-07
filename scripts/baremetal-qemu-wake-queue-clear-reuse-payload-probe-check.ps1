# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-clear-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_REUSE_PAYLOAD_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_REUSE_PAYLOAD_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-clear-probe-check.ps1' `
    -FailureLabel 'wake-queue clear' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_TASK_ID'
$postReuseTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_REUSE_TASK_ID'
$postReuseReason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_REUSE_REASON'
$postReuseTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_POST_REUSE_TICK'

if ($null -in @($taskId, $postReuseTaskId, $postReuseReason, $postReuseTick)) {
    throw 'Missing expected post-reuse payload fields in wake-queue-clear probe output.'
}
if ($postReuseTaskId -ne $taskId) {
    throw "Expected POST_REUSE_TASK_ID to match TASK_ID ($taskId). got $postReuseTaskId"
}
if ($postReuseReason -ne 3) {
    throw "Expected POST_REUSE_REASON=3. got $postReuseReason"
}
if ($postReuseTick -le 0) {
    throw "Expected POST_REUSE_TICK > 0. got $postReuseTick"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_REUSE_PAYLOAD_PROBE=pass'
Write-Output "TASK_ID=$taskId"
Write-Output "POST_REUSE_TASK_ID=$postReuseTaskId"
Write-Output "POST_REUSE_REASON=$postReuseReason"
Write-Output "POST_REUSE_TICK=$postReuseTick"
