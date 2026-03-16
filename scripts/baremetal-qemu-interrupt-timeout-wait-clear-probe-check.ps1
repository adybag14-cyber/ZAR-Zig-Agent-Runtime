# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-probe-check.ps1"
$taskStateReady = 1
$waitConditionNone = 0

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_WAIT_CLEAR_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_WAIT_CLEAR_PROBE_SOURCE=baremetal-qemu-interrupt-timeout-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout probe failed with exit code $probeExitCode"
}

$task0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_TASK0_STATE'
$waitKind0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAIT_KIND0'
$waitVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAIT_VECTOR0'
$waitTimeout0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_WAIT_TIMEOUT0'
$timerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_TIMER_ENTRY_COUNT'
$timerDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_TIMER_DISPATCH_COUNT'

if ($null -in @($task0State, $waitKind0, $waitVector0, $waitTimeout0, $timerEntryCount, $timerDispatchCount)) {
    throw 'Missing expected interrupt-timeout wait-clear fields in probe output.'
}
if ($task0State -ne $taskStateReady) { throw "Expected TASK0_STATE=1, got $task0State" }
if ($waitKind0 -ne $waitConditionNone) { throw "Expected WAIT_KIND0=0, got $waitKind0" }
if ($waitVector0 -ne 0) { throw "Expected WAIT_VECTOR0=0, got $waitVector0" }
if ($waitTimeout0 -ne 0) { throw "Expected WAIT_TIMEOUT0=0, got $waitTimeout0" }
if ($timerEntryCount -ne 0) { throw "Expected TIMER_ENTRY_COUNT=0, got $timerEntryCount" }
if ($timerDispatchCount -ne 0) { throw "Expected TIMER_DISPATCH_COUNT=0, got $timerDispatchCount" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_WAIT_CLEAR_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_WAIT_CLEAR_PROBE_SOURCE=baremetal-qemu-interrupt-timeout-probe-check.ps1'
Write-Output "TASK0_STATE=$task0State"
Write-Output "WAIT_KIND0=$waitKind0"
Write-Output "WAIT_VECTOR0=$waitVector0"
Write-Output "WAIT_TIMEOUT0=$waitTimeout0"
Write-Output "TIMER_ENTRY_COUNT=$timerEntryCount"
Write-Output "TIMER_DISPATCH_COUNT=$timerDispatchCount"
