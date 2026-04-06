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
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_INVALID_PRESERVE_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_INVALID_PRESERVE_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-reason-pop-probe-check.ps1' `
    -FailureLabel 'wake-queue reason-pop'
$probeText = $probeState.Text


$finalCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FINAL_COUNT'
$finalTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FINAL_TASK0'
$finalTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FINAL_TASK1'
$finalVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FINAL_VECTOR0'
$finalVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_FINAL_VECTOR1'

if ($null -in @($finalCount, $finalTask0, $finalTask1, $finalVector0, $finalVector1)) {
    throw 'Missing expected invalid-preserve-state fields in wake-queue reason-pop probe output.'
}
if ($finalCount -ne 1) { throw "Expected FINAL_COUNT=1. got $finalCount" }
if ($finalTask0 -ne 1 -or $finalTask1 -ne 0) {
    throw "Unexpected final task state after invalid reason: $finalTask0,$finalTask1"
}
if ($finalVector0 -ne 0 -or $finalVector1 -ne 0) {
    throw "Unexpected final vector state after invalid reason: $finalVector0,$finalVector1"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_INVALID_PRESERVE_STATE_PROBE=pass'
Write-Output "FINAL_COUNT=$finalCount"
Write-Output "FINAL_TASK0=$finalTask0"
Write-Output "FINAL_TASK1=$finalTask1"
Write-Output "FINAL_VECTOR0=$finalVector0"
Write-Output "FINAL_VECTOR1=$finalVector1"
