# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-overflow-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_ENTRY_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-overflow probe failed with exit code $probeExitCode"
}

$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_TASK_ID'
$oldestSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_SEQ'
$oldestTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_TASK_ID'
$oldestReason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_REASON'
$oldestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_TICK'

if ($null -in @($taskId, $oldestSeq, $oldestTaskId, $oldestReason, $oldestTick)) {
    throw 'Missing expected oldest-entry fields in wake-queue-overflow probe output.'
}
if ($oldestSeq -ne 3) { throw "Expected OLDEST_SEQ=3. got $oldestSeq" }
if ($oldestTaskId -ne $taskId) { throw "Expected OLDEST_TASK_ID=$taskId. got $oldestTaskId" }
if ($oldestReason -ne 3) { throw "Expected OLDEST_REASON=3. got $oldestReason" }
if ($oldestTick -le 0) { throw "Expected OLDEST_TICK > 0. got $oldestTick" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OLDEST_ENTRY_PROBE=pass'
Write-Output "OLDEST_SEQ=$oldestSeq"
Write-Output "OLDEST_TASK_ID=$oldestTaskId"
Write-Output "OLDEST_REASON=$oldestReason"
Write-Output "OLDEST_TICK=$oldestTick"
