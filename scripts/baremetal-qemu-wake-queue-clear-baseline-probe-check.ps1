# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-clear-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = 90 }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-wake-queue-clear-probe-check.ps1' `
    -FailureLabel 'wake-queue clear' `
    -InvokeArgs $invoke
$probeText = $probeState.Text


$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_TICKS'
$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_TASK_ID'
$preCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PRE_COUNT'
$preHead = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PRE_HEAD'
$preTail = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PRE_TAIL'
$preOverflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PRE_OVERFLOW'
$preOldestSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PRE_OLDEST_SEQ'
$preNewestSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_PRE_NEWEST_SEQ'

if ($null -in @($ack, $lastOpcode, $lastResult, $ticks, $taskId, $preCount, $preHead, $preTail, $preOverflow, $preOldestSeq, $preNewestSeq)) {
    throw 'Missing expected baseline fields in wake-queue-clear probe output.'
}
if ($ack -ne 139 -or $lastOpcode -ne 45 -or $lastResult -ne 0) {
    throw "Unexpected final mailbox state: $ack/$lastOpcode/$lastResult"
}
if ($ticks -lt 139) { throw "Expected TICKS >= 139. got $ticks" }
if ($taskId -le 0) { throw "Expected TASK_ID > 0. got $taskId" }
if ($preCount -ne 64 -or $preHead -ne 2 -or $preTail -ne 2 -or $preOverflow -ne 2) {
    throw "Unexpected PRE queue summary: $preCount/$preHead/$preTail/$preOverflow"
}
if ($preOldestSeq -ne 3 -or $preNewestSeq -ne 66) {
    throw "Unexpected PRE seq window: $preOldestSeq/$preNewestSeq"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_CLEAR_BASELINE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TICKS=$ticks"
Write-Output "TASK_ID=$taskId"
Write-Output "PRE_COUNT=$preCount"
Write-Output "PRE_HEAD=$preHead"
Write-Output "PRE_TAIL=$preTail"
Write-Output "PRE_OVERFLOW=$preOverflow"
Write-Output "PRE_OLDEST_SEQ=$preOldestSeq"
Write-Output "PRE_NEWEST_SEQ=$preNewestSeq"
