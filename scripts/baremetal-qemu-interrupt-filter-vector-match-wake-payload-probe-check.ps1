# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-filter-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe 
    -ProbePath $probe 
    -SkipBuild:$SkipBuild 
    -SkippedPattern '(?m)^BAREMETAL_QEMU_INTERRUPT_FILTER_PROBE=skipped\r?$' 
    -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_FILTER_VECTOR_MATCH_WAKE_PAYLOAD_PROBE' 
    -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_FILTER_VECTOR_MATCH_WAKE_PAYLOAD_PROBE_SOURCE' 
    -SkippedSourceValue 'baremetal-qemu-interrupt-filter-probe-check.ps1' 
    -FailureLabel 'interrupt-filter' 
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text
task1Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_TASK1_ID'
$vecWakeSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_VEC_WAKE_SEQ'
$vecWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_VEC_WAKE_TICK'
$vecWakeTaskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_VEC_WAKE_TASK_STATE'
$vecWakeTaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_VEC_WAKE_TASK_COUNT'
$vecWakeTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_VEC_WAKE_TASK_ID'
$vecWakeReason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_VEC_WAKE_REASON'
$vecWakeVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_VEC_WAKE_VECTOR'
if ($null -in @($task1Id, $vecWakeSeq, $vecWakeTick, $vecWakeTaskState, $vecWakeTaskCount, $vecWakeTaskId, $vecWakeReason, $vecWakeVector)) { throw 'Missing vector-match wake fields in interrupt-filter probe output.' }
if ($vecWakeSeq -le 0) { throw "Expected VEC_WAKE_SEQ > 0, got $vecWakeSeq" }
if ($vecWakeTick -le 0) { throw "Expected VEC_WAKE_TICK > 0, got $vecWakeTick" }
if ($vecWakeTaskState -ne 1) { throw "Expected VEC_WAKE_TASK_STATE=1, got $vecWakeTaskState" }
if ($vecWakeTaskCount -ne 2) { throw "Expected VEC_WAKE_TASK_COUNT=2, got $vecWakeTaskCount" }
if ($vecWakeTaskId -ne $task1Id) { throw "Expected VEC_WAKE_TASK_ID=$task1Id, got $vecWakeTaskId" }
if ($vecWakeReason -ne 2) { throw "Expected VEC_WAKE_REASON=2, got $vecWakeReason" }
if ($vecWakeVector -ne 13) { throw "Expected VEC_WAKE_VECTOR=13, got $vecWakeVector" }
Write-Output 'BAREMETAL_QEMU_INTERRUPT_FILTER_VECTOR_MATCH_WAKE_PAYLOAD_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_FILTER_VECTOR_MATCH_WAKE_PAYLOAD_PROBE_SOURCE=baremetal-qemu-interrupt-filter-probe-check.ps1'
Write-Output "VEC_WAKE_SEQ=$vecWakeSeq"
Write-Output "VEC_WAKE_TICK=$vecWakeTick"
Write-Output "VEC_WAKE_TASK_STATE=$vecWakeTaskState"
Write-Output "VEC_WAKE_TASK_COUNT=$vecWakeTaskCount"
Write-Output "VEC_WAKE_TASK_ID=$vecWakeTaskId"
Write-Output "VEC_WAKE_REASON=$vecWakeReason"
Write-Output "VEC_WAKE_VECTOR=$vecWakeVector"
