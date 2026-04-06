# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-pop-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_SURVIVOR_ORDER_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_SURVIVOR_ORDER_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-pop'
$probeText = $probeState.Text


$postCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_POST_COUNT'
$postTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_POST_TASK0'
$postTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_POST_TASK1'
$postVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_POST_VECTOR0'
$postVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_POST_VECTOR1'

if ($null -in @($postCount, $postTask0, $postTask1, $postVector0, $postVector1)) {
    throw 'Missing expected survivor-order fields in wake-queue reason-pop probe output.'
}
if ($postCount -ne 1) { throw "Expected POST_COUNT=1. got $postCount" }
if ($postTask0 -ne 1 -or $postTask1 -ne 0) {
    throw "Unexpected post-survivor task state: $postTask0,$postTask1"
}
if ($postVector0 -ne 0 -or $postVector1 -ne 0) {
    throw "Unexpected post-survivor vectors: $postVector0,$postVector1"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_SURVIVOR_ORDER_PROBE=pass'
Write-Output "POST_COUNT=$postCount"
Write-Output "POST_TASK0=$postTask0"
Write-Output "POST_TASK1=$postTask1"
Write-Output "POST_VECTOR0=$postVector0"
Write-Output "POST_VECTOR1=$postVector1"
