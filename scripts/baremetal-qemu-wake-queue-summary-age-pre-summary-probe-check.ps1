# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-summary-age-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PRE_SUMMARY_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue summary/age probe failed with exit code $probeExitCode"
}

$len = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_LEN'
$overflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_OVERFLOW'
$timerCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_TIMER_COUNT'
$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_INTERRUPT_COUNT'
$manualCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_MANUAL_COUNT'
$nonzeroVectorCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_NONZERO_VECTOR_COUNT'
$staleCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_STALE_COUNT'
$oldestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_OLDEST_TICK'
$newestTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PROBE_PRE_SUMMARY_NEWEST_TICK'
if ($null -in @($len,$overflow,$timerCount,$interruptCount,$manualCount,$nonzeroVectorCount,$staleCount,$oldestTick,$newestTick)) {
    throw 'Missing expected pre-summary fields in wake-queue summary/age probe output.'
}
if ($len -ne 5 -or $overflow -ne 0 -or $timerCount -ne 1 -or $interruptCount -ne 3 -or $manualCount -ne 1 -or $nonzeroVectorCount -ne 3 -or $staleCount -ne 5 -or $oldestTick -ne 8 -or $newestTick -ne 20) {
    throw "Unexpected pre-summary snapshot: len=$len overflow=$overflow timer=$timerCount interrupt=$interruptCount manual=$manualCount nonzero=$nonzeroVectorCount stale=$staleCount oldest=$oldestTick newest=$newestTick"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_SUMMARY_AGE_PRE_SUMMARY_PROBE=pass'
Write-Output "PRE_SUMMARY_LEN=$len"
Write-Output "PRE_SUMMARY_INTERRUPT_COUNT=$interruptCount"
Write-Output "PRE_SUMMARY_MANUAL_COUNT=$manualCount"
Write-Output "PRE_SUMMARY_OLDEST_TICK=$oldestTick"
Write-Output "PRE_SUMMARY_NEWEST_TICK=$newestTick"