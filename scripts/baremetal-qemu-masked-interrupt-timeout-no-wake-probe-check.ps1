# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-masked-interrupt-timeout-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_NO_WAKE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying masked interrupt-timeout probe failed with exit code $probeExitCode"
}

$task0StateAfterInterrupt = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_TASK0_STATE_AFTER_INTERRUPT'
$wakeQueueCountAfterInterrupt = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_WAKE_QUEUE_COUNT_AFTER_INTERRUPT'
$interruptCountAfterInterrupt = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_INTERRUPT_COUNT_AFTER_INTERRUPT'
if ($null -in @($task0StateAfterInterrupt, $wakeQueueCountAfterInterrupt, $interruptCountAfterInterrupt)) {
    throw 'Missing no-wake fields in probe output.'
}
if ($task0StateAfterInterrupt -ne 6) { throw "Expected waiting state (6) after masked interrupt. got $task0StateAfterInterrupt" }
if ($wakeQueueCountAfterInterrupt -ne 0) { throw "Expected no queued wake after masked interrupt. got $wakeQueueCountAfterInterrupt" }
if ($interruptCountAfterInterrupt -ne 0) { throw "Expected zero delivered interrupts after masked interrupt. got $interruptCountAfterInterrupt" }

Write-Output 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_NO_WAKE_PROBE=pass'
Write-Output "TASK0_STATE_AFTER_INTERRUPT=$task0StateAfterInterrupt"
Write-Output "WAKE_QUEUE_COUNT_AFTER_INTERRUPT=$wakeQueueCountAfterInterrupt"
Write-Output "INTERRUPT_COUNT_AFTER_INTERRUPT=$interruptCountAfterInterrupt"
