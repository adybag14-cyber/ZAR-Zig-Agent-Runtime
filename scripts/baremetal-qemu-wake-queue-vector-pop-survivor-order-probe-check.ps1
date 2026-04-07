# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-vector-pop-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_SURVIVOR_ORDER_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_SURVIVOR_ORDER_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-vector-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue vector-pop'
$probeText = $probeState.Text

$task1Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_TASK1_ID'
$task4Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_TASK4_ID'
$postCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_POST_COUNT'
$postTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_POST_TASK0'
$postTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_POST_TASK1'
$postVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_POST_VECTOR0'
$postVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_POST_VECTOR1'
if ($null -in @($task1Id,$task4Id,$postCount,$postTask0,$postTask1,$postVector0,$postVector1)) { throw 'Missing expected survivor-order fields in wake-queue vector-pop probe output.' }
if ($postCount -ne 2) { throw "Expected POST_COUNT=2. got $postCount" }
if ($postTask0 -ne $task1Id -or $postTask1 -ne $task4Id) { throw "Unexpected survivor task ordering: $postTask0,$postTask1" }
if ($postVector0 -ne 0 -or $postVector1 -ne 31) { throw "Unexpected survivor vector ordering: $postVector0,$postVector1" }
Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_VECTOR_POP_SURVIVOR_ORDER_PROBE=pass'
Write-Output "POST_COUNT=$postCount"
Write-Output "POST_TASK0=$postTask0"
Write-Output "POST_TASK1=$postTask1"
Write-Output "POST_VECTOR0=$postVector0"
Write-Output "POST_VECTOR1=$postVector1"
