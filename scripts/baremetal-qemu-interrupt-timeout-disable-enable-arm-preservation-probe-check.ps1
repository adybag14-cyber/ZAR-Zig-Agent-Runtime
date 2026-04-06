# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-disable-enable-probe-check.ps1"
$waitConditionInterruptAny = 3
$taskStateWaiting = 6

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
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_ARM_PRESERVATION_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout disable-enable probe failed with exit code $probeExitCode"
}

$armedWaitTimeout = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_ARMED_WAIT_TIMEOUT'
$disabledTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_DISABLED_TICK'
$disabledWaitKind0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_DISABLED_WAIT_KIND0'
$disabledWaitTimeout0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_DISABLED_WAIT_TIMEOUT0'
$disabledTask0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_DISABLED_TASK0_STATE'
$disabledWakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_DISABLED_WAKE_QUEUE_COUNT'
$disabledTimerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_DISABLED_TIMER_ENTRY_COUNT'
$disabledInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_PROBE_DISABLED_INTERRUPT_COUNT'

if ($null -in @($armedWaitTimeout, $disabledTick, $disabledWaitKind0, $disabledWaitTimeout0, $disabledTask0State, $disabledWakeQueueCount, $disabledTimerEntryCount, $disabledInterruptCount)) {
    throw 'Missing expected disable-state fields in probe output.'
}
if ($disabledTick -lt 1) {
    throw "Expected disable snapshot after runtime advanced. got disabledTick=$disabledTick"
}
if ($disabledWaitKind0 -ne $waitConditionInterruptAny) {
    throw "Expected wait kind to stay interrupt_any immediately after disable. got $disabledWaitKind0"
}
if ($disabledWaitTimeout0 -ne $armedWaitTimeout) {
    throw "Expected timeout arm to remain unchanged immediately after disable. armed=$armedWaitTimeout disabled=$disabledWaitTimeout0"
}
if ($disabledTask0State -ne $taskStateWaiting) {
    throw "Expected task to remain waiting immediately after disable. got state=$disabledTask0State"
}
if ($disabledWakeQueueCount -ne 0) {
    throw "Expected no queued wakes immediately after disable. got $disabledWakeQueueCount"
}
if ($disabledTimerEntryCount -ne 0) {
    throw "Expected no timer-entry table usage for interrupt-timeout wait immediately after disable. got $disabledTimerEntryCount"
}
if ($disabledInterruptCount -ne 0) {
    throw "Expected zero interrupt telemetry immediately after disable. got $disabledInterruptCount"
}

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_ENABLE_ARM_PRESERVATION_PROBE=pass'
Write-Output "ARMED_WAIT_TIMEOUT=$armedWaitTimeout"
Write-Output "DISABLED_TICK=$disabledTick"
Write-Output "DISABLED_WAIT_KIND0=$disabledWaitKind0"
Write-Output "DISABLED_WAIT_TIMEOUT0=$disabledWaitTimeout0"
Write-Output "DISABLED_TASK0_STATE=$disabledTask0State"
