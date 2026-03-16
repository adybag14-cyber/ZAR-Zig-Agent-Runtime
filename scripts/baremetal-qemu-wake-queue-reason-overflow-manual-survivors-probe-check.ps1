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
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_MANUAL_SURVIVORS_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-reason-overflow probe failed with exit code $probeExitCode"
}

$postManualFirstSeq = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_FIRST_SEQ'
$postManualFirstReason = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_FIRST_REASON'
$postManualRemainingSeq = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_REMAINING_SEQ'
$postManualRemainingReason = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_REMAINING_REASON'
$postManualLastSeq = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_LAST_SEQ'
$postManualLastReason = Extract-IntValue -Text $probeText -Name 'POST_MANUAL_LAST_REASON'

if ($null -in @($postManualFirstSeq, $postManualFirstReason, $postManualRemainingSeq, $postManualRemainingReason, $postManualLastSeq, $postManualLastReason)) {
    throw 'Missing post-manual survivor fields in wake-queue-reason-overflow probe output.'
}
if ($postManualFirstSeq -ne 4 -or $postManualFirstReason -ne 2 -or $postManualRemainingSeq -ne 65 -or $postManualRemainingReason -ne 3 -or $postManualLastSeq -ne 66 -or $postManualLastReason -ne 2) {
    throw "Unexpected POST_MANUAL survivor summary: $postManualFirstSeq/$postManualFirstReason/$postManualRemainingSeq/$postManualRemainingReason/$postManualLastSeq/$postManualLastReason"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_OVERFLOW_MANUAL_SURVIVORS_PROBE=pass'
Write-Output "POST_MANUAL_FIRST_SEQ=$postManualFirstSeq"
Write-Output "POST_MANUAL_FIRST_REASON=$postManualFirstReason"
Write-Output "POST_MANUAL_REMAINING_SEQ=$postManualRemainingSeq"
Write-Output "POST_MANUAL_REMAINING_REASON=$postManualRemainingReason"
Write-Output "POST_MANUAL_LAST_SEQ=$postManualLastSeq"
Write-Output "POST_MANUAL_LAST_REASON=$postManualLastReason"
