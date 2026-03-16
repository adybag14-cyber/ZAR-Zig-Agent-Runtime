# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-fifo-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_FIRST_POP_PROBE=skipped'

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

$preWake1Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_PRE_WAKE1_SEQ'
$postPop1Len = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_POST_POP1_LEN'
$postPop1Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_POST_POP1_SEQ'
if ($null -in @($preWake1Seq,$postPop1Len,$postPop1Seq)) {
    throw 'Missing expected first-pop fields in wake-queue FIFO probe output.'
}
if ($postPop1Len -ne 1) { throw "Expected POST_POP1_LEN=1. got $postPop1Len" }
if ($postPop1Seq -ne $preWake1Seq) { throw "Expected POST_POP1_SEQ to match second queued wake. got $postPop1Seq vs $preWake1Seq" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_FIRST_POP_PROBE=pass'
Write-Output "POST_POP1_LEN=$postPop1Len"
Write-Output "POST_POP1_SEQ=$postPop1Seq"
