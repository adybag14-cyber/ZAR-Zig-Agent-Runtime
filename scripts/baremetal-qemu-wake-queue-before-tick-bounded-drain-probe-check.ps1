# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-before-tick-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_BOUNDED_DRAIN_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_BOUNDED_DRAIN_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-before-tick-probe-check.ps1' `
    -FailureLabel 'wake-queue before-tick'
$probeText = $probeState.Text


$task4Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_TASK4_ID'
$preTick3 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_PRE_TICK3'
$postCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_POST_COUNT'
$postTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_POST_TASK0'
$postTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_POST_TASK1'
$postVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_POST_VECTOR0'
$postVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_POST_VECTOR1'
$postTick0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_POST_TICK0'
if ($null -in @($task4Id,$preTick3,$postCount,$postTask0,$postTask1,$postVector0,$postVector1,$postTick0)) {
    throw 'Missing expected bounded-drain fields in wake-queue before-tick probe output.'
}
if ($postCount -ne 1) { throw "Expected POST_COUNT=1. got $postCount" }
if ($postTask0 -ne $task4Id -or $postTask1 -ne 0) {
    throw "Unexpected post-drain task state: $postTask0,$postTask1"
}
if ($postVector0 -ne 31 -or $postVector1 -ne 0) {
    throw "Unexpected post-drain vector state: $postVector0,$postVector1"
}
if ($postTick0 -ne $preTick3) { throw "Expected POST_TICK0=$preTick3. got $postTick0" }
Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BEFORE_TICK_BOUNDED_DRAIN_PROBE=pass'
Write-Output "POST_COUNT=$postCount"
Write-Output "POST_TASK0=$postTask0"
Write-Output "POST_VECTOR0=$postVector0"
Write-Output "POST_TICK0=$postTick0"

