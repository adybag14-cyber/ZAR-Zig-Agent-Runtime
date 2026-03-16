# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-fifo-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_SURVIVOR_PROBE=skipped'

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

$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_TASK_ID'
$preWake1Task = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE1_TASK'
$preWake1Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE1_REASON'
$preWake1Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE1_TICK'
$postPop1Task = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_POST_POP1_TASK'
$postPop1Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_POST_POP1_REASON'
$postPop1Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_POST_POP1_TICK'
if ($null -in @($taskId,$preWake1Task,$preWake1Reason,$preWake1Tick,$postPop1Task,$postPop1Reason,$postPop1Tick)) {
    throw 'Missing expected survivor fields in wake-queue FIFO probe output.'
}
if ($preWake1Task -ne $taskId -or $postPop1Task -ne $taskId) {
    throw "Unexpected survivor task id: pre=$preWake1Task post=$postPop1Task expected=$taskId"
}
if ($preWake1Reason -ne 3 -or $postPop1Reason -ne 3) {
    throw "Unexpected survivor reason: pre=$preWake1Reason post=$postPop1Reason"
}
if ($postPop1Tick -ne $preWake1Tick) {
    throw "Expected survivor tick to be preserved. got pre=$preWake1Tick post=$postPop1Tick"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_SURVIVOR_PROBE=pass'
Write-Output "POST_POP1_TASK=$postPop1Task"
Write-Output "POST_POP1_REASON=$postPop1Reason"
Write-Output "POST_POP1_TICK=$postPop1Tick"
