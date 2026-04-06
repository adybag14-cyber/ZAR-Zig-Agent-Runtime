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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_INVALID_PRESERVE_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_INVALID_PRESERVE_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-vector-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-vector-pop'
$probeText = $probeState.Text


$task1Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_TASK1_ID'
$task4Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_TASK4_ID'
$finalCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_FINAL_COUNT'
$finalTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_FINAL_TASK0'
$finalTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_FINAL_TASK1'
$finalVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_FINAL_VECTOR0'
$finalVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_FINAL_VECTOR1'
if ($null -in @($task1Id,$task4Id,$finalCount,$finalTask0,$finalTask1,$finalVector0,$finalVector1)) {
    throw 'Missing expected invalid-preserve-state fields in wake-queue reason-vector-pop probe output.'
}
if ($finalCount -ne 2) { throw "Expected FINAL_COUNT=2. got $finalCount" }
if ($finalTask0 -ne $task1Id -or $finalTask1 -ne $task4Id) {
    throw "Unexpected final preserved task ordering: $finalTask0,$finalTask1"
}
if ($finalVector0 -ne 0 -or $finalVector1 -ne 19) {
    throw "Unexpected final preserved vector ordering: $finalVector0,$finalVector1"
}
Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_VECTOR_POP_INVALID_PRESERVE_STATE_PROBE=pass'
Write-Output "FINAL_COUNT=$finalCount"
Write-Output "FINAL_TASK0=$finalTask0"
Write-Output "FINAL_TASK1=$finalTask1"
Write-Output "FINAL_VECTOR0=$finalVector0"
Write-Output "FINAL_VECTOR1=$finalVector1"
