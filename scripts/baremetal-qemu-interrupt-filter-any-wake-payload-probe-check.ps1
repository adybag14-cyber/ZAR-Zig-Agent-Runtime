# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-filter-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe -ProbePath $probe -SkipBuild:$SkipBuild -SkippedPattern '(?m)^BAREMETAL_QEMU_INTERRUPT_FILTER_PROBE=skipped\r?$' -SkippedReceipt 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAKE_PAYLOAD_PROBE' -SkippedSourceReceipt 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAKE_PAYLOAD_PROBE_SOURCE' -SkippedSourceValue 'baremetal-qemu-interrupt-filter-probe-check.ps1' -FailureLabel 'interrupt-filter' -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text
task0Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_TASK0_ID'
$anyWakeSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAKE_SEQ'
$anyWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAKE_TICK'
$anyWakeTaskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAKE_TASK_STATE'
$anyWakeTaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAKE_TASK_COUNT'
$anyWakeTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAKE_TASK_ID'
$anyWakeReason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAKE_REASON'
$anyWakeVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAKE_VECTOR'
if ($null -in @($task0Id, $anyWakeSeq, $anyWakeTick, $anyWakeTaskState, $anyWakeTaskCount, $anyWakeTaskId, $anyWakeReason, $anyWakeVector)) { throw 'Missing any-wake payload fields in interrupt-filter probe output.' }
if ($anyWakeSeq -le 0) { throw "Expected ANY_WAKE_SEQ > 0, got $anyWakeSeq" }
if ($anyWakeTick -le 0) { throw "Expected ANY_WAKE_TICK > 0, got $anyWakeTick" }
if ($anyWakeTaskState -ne 1) { throw "Expected ANY_WAKE_TASK_STATE=1, got $anyWakeTaskState" }
if ($anyWakeTaskCount -ne 1) { throw "Expected ANY_WAKE_TASK_COUNT=1, got $anyWakeTaskCount" }
if ($anyWakeTaskId -ne $task0Id) { throw "Expected ANY_WAKE_TASK_ID=$task0Id, got $anyWakeTaskId" }
if ($anyWakeReason -ne 2) { throw "Expected ANY_WAKE_REASON=2, got $anyWakeReason" }
if ($anyWakeVector -ne 200) { throw "Expected ANY_WAKE_VECTOR=200, got $anyWakeVector" }
Write-Output 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAKE_PAYLOAD_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_FILTER_ANY_WAKE_PAYLOAD_PROBE_SOURCE=baremetal-qemu-interrupt-filter-probe-check.ps1'
Write-Output "ANY_WAKE_SEQ=$anyWakeSeq"
Write-Output "ANY_WAKE_TICK=$anyWakeTick"
Write-Output "ANY_WAKE_TASK_STATE=$anyWakeTaskState"
Write-Output "ANY_WAKE_TASK_COUNT=$anyWakeTaskCount"
Write-Output "ANY_WAKE_TASK_ID=$anyWakeTaskId"
Write-Output "ANY_WAKE_REASON=$anyWakeReason"
Write-Output "ANY_WAKE_VECTOR=$anyWakeVector"
