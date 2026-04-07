# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-vector-pop-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-vector-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-vector-pop'
$probeText = $probeState.Text


$task1Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_TASK1_ID'
$task2Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_TASK2_ID'
$task3Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_TASK3_ID'
$task4Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_TASK4_ID'
$preCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_PRE_COUNT'
$preTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_PRE_TASK0'
$preTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_PRE_TASK1'
$preTask2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_PRE_TASK2'
$preTask3 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_PRE_TASK3'
$preVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_PRE_VECTOR0'
$preVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_PRE_VECTOR1'
$preVector2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_PRE_VECTOR2'
$preVector3 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_PRE_VECTOR3'
if ($null -in @($task1Id,$task2Id,$task3Id,$task4Id,$preCount,$preTask0,$preTask1,$preTask2,$preTask3,$preVector0,$preVector1,$preVector2,$preVector3)) {
    throw 'Missing expected baseline fields in wake-queue reason-vector-pop probe output.'
}
if ($preCount -ne 4) { throw "Expected PRE_COUNT=4. got $preCount" }
if ($preTask0 -ne $task1Id -or $preTask1 -ne $task2Id -or $preTask2 -ne $task3Id -or $preTask3 -ne $task4Id) {
    throw "Unexpected baseline task ordering: $preTask0,$preTask1,$preTask2,$preTask3"
}
if ($preVector0 -ne 0 -or $preVector1 -ne 13 -or $preVector2 -ne 13 -or $preVector3 -ne 19) {
    throw "Unexpected baseline vector ordering: $preVector0,$preVector1,$preVector2,$preVector3"
}
Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_BASELINE_PROBE=pass'
Write-Output "PRE_COUNT=$preCount"
Write-Output "PRE_TASK0=$preTask0"
Write-Output "PRE_TASK1=$preTask1"
Write-Output "PRE_TASK2=$preTask2"
Write-Output "PRE_TASK3=$preTask3"
Write-Output "PRE_VECTOR0=$preVector0"
Write-Output "PRE_VECTOR1=$preVector1"
Write-Output "PRE_VECTOR2=$preVector2"
Write-Output "PRE_VECTOR3=$preVector3"
