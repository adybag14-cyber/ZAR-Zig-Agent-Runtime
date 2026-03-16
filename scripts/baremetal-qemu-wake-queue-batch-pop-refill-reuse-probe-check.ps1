# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-batch-pop-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild -TimeoutSeconds 90 2>&1 } else { & $probe -TimeoutSeconds 90 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_REFILL_REUSE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-batch-pop probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_LAST_RESULT'
$refillCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_REFILL_COUNT'
$refillHead = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_REFILL_HEAD'
$refillTail = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_REFILL_TAIL'
$refillOverflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_REFILL_OVERFLOW'
$refillSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_REFILL_SEQ'
$refillReason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_REFILL_REASON'
$refillTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_REFILL_TASK_ID'
$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_TASK_ID'

if ($null -in @($ack, $lastOpcode, $lastResult, $refillCount, $refillHead, $refillTail, $refillOverflow, $refillSeq, $refillReason, $refillTaskId, $taskId)) {
    throw 'Missing expected refill-reuse fields in wake-queue-batch-pop probe output.'
}
if ($ack -ne 141) { throw "Expected ACK=141. got $ack" }
if ($lastOpcode -ne 45 -or $lastResult -ne 0) { throw "Expected final scheduler wake receipt 45/0. got $lastOpcode/$lastResult" }
if ($refillCount -ne 1) { throw "Expected REFILL_COUNT=1. got $refillCount" }
if ($refillHead -ne 3 -or $refillTail -ne 2) { throw "Expected REFILL head/tail = 3/2. got $refillHead/$refillTail" }
if ($refillOverflow -ne 2) { throw "Expected REFILL_OVERFLOW=2. got $refillOverflow" }
if ($refillSeq -ne 67) { throw "Expected REFILL_SEQ=67. got $refillSeq" }
if ($refillReason -ne 3) { throw "Expected REFILL_REASON=3. got $refillReason" }
if ($refillTaskId -ne $taskId) { throw "Expected REFILL_TASK_ID=$taskId. got $refillTaskId" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_REFILL_REUSE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "REFILL_COUNT=$refillCount"
Write-Output "REFILL_HEAD=$refillHead"
Write-Output "REFILL_TAIL=$refillTail"
Write-Output "REFILL_OVERFLOW=$refillOverflow"
Write-Output "REFILL_SEQ=$refillSeq"
Write-Output "REFILL_REASON=$refillReason"
Write-Output "REFILL_TASK_ID=$refillTaskId"
