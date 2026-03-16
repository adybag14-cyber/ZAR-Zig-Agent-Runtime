# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-overflow-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_MANUAL_DRAIN_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-reason-overflow probe failed with exit code $probeExitCode"
}

$postManualCount = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_COUNT'
$postManualHead = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_HEAD'
$postManualTail = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_TAIL'
$postManualOverflow = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_OVERFLOW'

if ($null -in @($postManualCount, $postManualHead, $postManualTail, $postManualOverflow)) {
    throw 'Missing post-manual drain summary fields in wake-queue-reason-overflow probe output.'
}
if ($postManualCount -ne 33 -or $postManualHead -ne 33 -or $postManualTail -ne 0 -or $postManualOverflow -ne 2) {
    throw "Unexpected POST_MANUAL summary: $postManualCount/$postManualHead/$postManualTail/$postManualOverflow"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_MANUAL_DRAIN_PROBE=pass'
Write-Output "POST_MANUAL_COUNT=$postManualCount"
Write-Output "POST_MANUAL_HEAD=$postManualHead"
Write-Output "POST_MANUAL_TAIL=$postManualTail"
Write-Output "POST_MANUAL_OVERFLOW=$postManualOverflow"
