# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-disable-enable-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PAUSED_WINDOW_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout disable-enable probe failed with exit code $probeExitCode"
}

$pausedWakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_PAUSED_WAKE_QUEUE_COUNT'
$pausedTimerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_PAUSED_TIMER_ENTRY_COUNT'
$pausedInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_PAUSED_INTERRUPT_COUNT'
$timerDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_TIMER_DISPATCH_COUNT'

if ($null -in @($pausedWakeQueueCount, $pausedTimerEntryCount, $pausedInterruptCount, $timerDispatchCount)) {
    throw 'Missing expected paused-window stability fields in probe output.'
}
if ($pausedWakeQueueCount -ne 0) {
    throw "Expected zero queued wakes throughout the paused disabled window. got $pausedWakeQueueCount"
}
if ($pausedTimerEntryCount -ne 0) {
    throw "Expected zero timer-entry table usage throughout the paused disabled window. got $pausedTimerEntryCount"
}
if ($pausedInterruptCount -ne 0) {
    throw "Expected zero interrupt telemetry throughout the paused disabled window. got $pausedInterruptCount"
}
if ($timerDispatchCount -ne 0) {
    throw "Expected no timer dispatches in the pure timeout disable-enable path. got $timerDispatchCount"
}

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PAUSED_WINDOW_PROBE=pass'
Write-Output "PAUSED_WAKE_QUEUE_COUNT=$pausedWakeQueueCount"
Write-Output "PAUSED_TIMER_ENTRY_COUNT=$pausedTimerEntryCount"
Write-Output "PAUSED_INTERRUPT_COUNT=$pausedInterruptCount"
Write-Output "TIMER_DISPATCH_COUNT=$timerDispatchCount"
