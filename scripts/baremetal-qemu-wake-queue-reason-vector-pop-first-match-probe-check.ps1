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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_FIRST_MATCH_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_FIRST_MATCH_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-vector-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-vector-pop'
$probeText = $probeState.Text


$task1Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_TASK1_ID'
$task3Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_TASK3_ID'
$task4Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_TASK4_ID'
$midCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_MID_COUNT'
$midTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_MID_TASK0'
$midTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_MID_TASK1'
$midTask2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_MID_TASK2'
$midVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_MID_VECTOR0'
$midVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_MID_VECTOR1'
$midVector2 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_MID_VECTOR2'
if ($null -in @($task1Id,$task3Id,$task4Id,$midCount,$midTask0,$midTask1,$midTask2,$midVector0,$midVector1,$midVector2)) {
    throw 'Missing expected first-match fields in wake-queue reason-vector-pop probe output.'
}
if ($midCount -ne 3) { throw "Expected MID_COUNT=3. got $midCount" }
if ($midTask0 -ne $task1Id -or $midTask1 -ne $task3Id -or $midTask2 -ne $task4Id) {
    throw "Unexpected first-match task ordering: $midTask0,$midTask1,$midTask2"
}
if ($midVector0 -ne 0 -or $midVector1 -ne 13 -or $midVector2 -ne 19) {
    throw "Unexpected first-match vector ordering: $midVector0,$midVector1,$midVector2"
}
Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_FIRST_MATCH_PROBE=pass'
Write-Output "MID_COUNT=$midCount"
Write-Output "MID_TASK0=$midTask0"
Write-Output "MID_TASK1=$midTask1"
Write-Output "MID_TASK2=$midTask2"
Write-Output "MID_VECTOR0=$midVector0"
Write-Output "MID_VECTOR1=$midVector1"
Write-Output "MID_VECTOR2=$midVector2"
