# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-filter-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe -ProbePath $probe -SkipBuild:$SkipBuild -SkippedPattern '(?m)^BAREMETAL_QEMU_INTERRUPT_FILTER_PROBE=skipped\r?$' -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_FILTER_INVALID_VECTOR_PRESERVE_STATE_PROBE' -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_FILTER_INVALID_VECTOR_PRESERVE_STATE_PROBE_SOURCE' -SkippedSourceValue 'baremetal-qemu-interrupt-filter-probe-check.ps1' -FailureLabel 'interrupt-filter' -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text
ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_LAST_RESULT'
$finalTask1State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_FINAL_TASK1_STATE'
$finalWaitKind1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_FINAL_WAIT_KIND1'
$finalWaitVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_FINAL_WAIT_VECTOR1'
$finalWakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_FINAL_WAKE_QUEUE_COUNT'
$finalWake0TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_FINAL_WAKE0_TASK_ID'
$finalWake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_FINAL_WAKE0_REASON'
$finalWake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_WAKE0_VECTOR'
if ($null -in @($ack, $lastOpcode, $lastResult, $finalTask1State, $finalWaitKind1, $finalWaitVector1, $finalWakeQueueCount, $finalWake0TaskId, $finalWake0Reason, $finalWake0Vector)) { throw 'Missing invalid-vector preserve fields in interrupt-filter probe output.' }
if ($ack -ne 14) { throw "Expected ACK=14, got $ack" }
if ($lastOpcode -ne 57) { throw "Expected LAST_OPCODE=57, got $lastOpcode" }
if ($lastResult -ne -22) { throw "Expected LAST_RESULT=-22, got $lastResult" }
if ($finalTask1State -ne 1) { throw "Expected FINAL_TASK1_STATE=1, got $finalTask1State" }
if ($finalWaitKind1 -ne 0) { throw "Expected FINAL_WAIT_KIND1=0, got $finalWaitKind1" }
if ($finalWaitVector1 -ne 0) { throw "Expected FINAL_WAIT_VECTOR1=0, got $finalWaitVector1" }
if ($finalWakeQueueCount -ne 1) { throw "Expected FINAL_WAKE_QUEUE_COUNT=1, got $finalWakeQueueCount" }
if ($finalWake0TaskId -le 0) { throw "Expected FINAL_WAKE0_TASK_ID > 0, got $finalWake0TaskId" }
if ($finalWake0Reason -ne 2) { throw "Expected FINAL_WAKE0_REASON=2, got $finalWake0Reason" }
if ($finalWake0Vector -ne 13) { throw "Expected FINAL_WAKE0_VECTOR=13, got $finalWake0Vector" }
Write-Output 'BAREMETAL_QEMU_INTERRUPT_FILTER_INVALID_VECTOR_PRESERVE_STATE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_FILTER_INVALID_VECTOR_PRESERVE_STATE_PROBE_SOURCE=baremetal-qemu-interrupt-filter-probe-check.ps1'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "FINAL_TASK1_STATE=$finalTask1State"
Write-Output "FINAL_WAIT_KIND1=$finalWaitKind1"
Write-Output "FINAL_WAIT_VECTOR1=$finalWaitVector1"
Write-Output "FINAL_WAKE_QUEUE_COUNT=$finalWakeQueueCount"
Write-Output "FINAL_WAKE0_TASK_ID=$finalWake0TaskId"
Write-Output "FINAL_WAKE0_REASON=$finalWake0Reason"
Write-Output "FINAL_WAKE0_VECTOR=$finalWake0Vector"
