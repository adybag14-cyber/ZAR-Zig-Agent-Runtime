# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-fifo-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_BASELINE_PROBE=skipped'

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE=skipped') {
    Write-Output $skipToken
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue FIFO probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_TICKS'
$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_TASK_ID'
$taskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_TASK_STATE'
$taskPriority = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_TASK_PRIORITY'
$schedTaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_SCHED_TASK_COUNT'
$preLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_LEN'
$preWake0Task = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE0_TASK'
$preWake1Task = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE1_TASK'
$preWake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE0_REASON'
$preWake1Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE1_REASON'
$preWake0Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE0_SEQ'
$preWake1Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE1_SEQ'
$preWake0Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE0_TICK'
$preWake1Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE1_TICK'
if ($null -in @($ack,$lastOpcode,$lastResult,$ticks,$taskId,$taskState,$taskPriority,$schedTaskCount,$preLen,$preWake0Task,$preWake1Task,$preWake0Reason,$preWake1Reason,$preWake0Seq,$preWake1Seq,$preWake0Tick,$preWake1Tick)) {
    throw 'Missing expected baseline fields in wake-queue FIFO probe output.'
}
if ($ack -ne 11 -or $lastOpcode -ne 54 -or $lastResult -ne -2) {
    throw "Unexpected final mailbox state: $ack/$lastOpcode/$lastResult"
}
if ($ticks -lt 11) { throw "Expected TICKS >= 11. got $ticks" }
if ($taskId -ne 1 -or $taskState -ne 1 -or $taskPriority -ne 0 -or $schedTaskCount -ne 1) {
    throw "Unexpected task baseline: id=$taskId state=$taskState priority=$taskPriority count=$schedTaskCount"
}
if ($preLen -ne 2) { throw "Expected PRE_LEN=2. got $preLen" }
if ($preWake0Task -ne $taskId -or $preWake1Task -ne $taskId) {
    throw "Unexpected queued task ids: $preWake0Task,$preWake1Task"
}
if ($preWake0Reason -ne 3 -or $preWake1Reason -ne 3) {
    throw "Unexpected queued reasons: $preWake0Reason,$preWake1Reason"
}
if ($preWake1Seq -le $preWake0Seq -or $preWake1Tick -le $preWake0Tick) {
    throw "Expected increasing seq/tick ordering. got seq=$preWake0Seq,$preWake1Seq tick=$preWake0Tick,$preWake1Tick"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_BASELINE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TICKS=$ticks"
Write-Output "TASK_ID=$taskId"
Write-Output "PRE_LEN=$preLen"
Write-Output "PRE_WAKE0_SEQ=$preWake0Seq"
Write-Output "PRE_WAKE1_SEQ=$preWake1Seq"
Write-Output "PRE_WAKE0_TICK=$preWake0Tick"
Write-Output "PRE_WAKE1_TICK=$preWake1Tick"
