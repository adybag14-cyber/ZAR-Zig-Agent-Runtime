# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-fifo-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_DRAIN_EMPTY_PROBE=skipped'

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

$postPop2Len = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_POST_POP2_LEN'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_WAKE_QUEUE_COUNT'
if ($null -in @($postPop2Len,$wakeQueueCount)) {
    throw 'Missing expected drain-empty fields in wake-queue FIFO probe output.'
}
if ($postPop2Len -ne 0 -or $wakeQueueCount -ne 0) {
    throw "Expected empty queue after second pop. got post2=$postPop2Len final=$wakeQueueCount"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_DRAIN_EMPTY_PROBE=pass'
Write-Output "POST_POP2_LEN=$postPop2Len"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
