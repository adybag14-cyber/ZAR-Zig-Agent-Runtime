# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 40,
    [int] $GdbPort = 1442
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-disable-interrupt-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$probeOutput = & $probe @invoke 2>&1
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_TELEMETRY_PRESERVE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_TELEMETRY_PRESERVE_PROBE_SOURCE=baremetal-qemu-timer-disable-interrupt-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-disable interrupt probe failed with exit code $probeExitCode"
}

$wake0Reason = Extract-IntValue -Text $probeText -Name 'WAKE0_REASON'
$wake0InterruptCount = Extract-IntValue -Text $probeText -Name 'WAKE0_INTERRUPT_COUNT'
$wake1Reason = Extract-IntValue -Text $probeText -Name 'WAKE1_REASON'
$wake1InterruptCount = Extract-IntValue -Text $probeText -Name 'WAKE1_INTERRUPT_COUNT'
$timerLastInterruptCount = Extract-IntValue -Text $probeText -Name 'TIMER_LAST_INTERRUPT_COUNT'
$interruptCount = Extract-IntValue -Text $probeText -Name 'INTERRUPT_COUNT'
$lastInterruptVector = Extract-IntValue -Text $probeText -Name 'LAST_INTERRUPT_VECTOR'

if ($null -in @($wake0Reason, $wake0InterruptCount, $wake1Reason, $wake1InterruptCount, $timerLastInterruptCount, $interruptCount, $lastInterruptVector)) {
    throw 'Missing expected timer-disable interrupt-telemetry fields in probe output.'
}
if ($wake0Reason -ne 2) { throw "Expected WAKE0_REASON=2, got $wake0Reason" }
if ($wake1Reason -ne 1) { throw "Expected WAKE1_REASON=1, got $wake1Reason" }
if ($wake0InterruptCount -lt 1) { throw "Expected WAKE0_INTERRUPT_COUNT >= 1, got $wake0InterruptCount" }
if ($wake1InterruptCount -ne $wake0InterruptCount) { throw "Expected WAKE1_INTERRUPT_COUNT=$wake0InterruptCount, got $wake1InterruptCount" }
if ($timerLastInterruptCount -ne $wake0InterruptCount) { throw "Expected TIMER_LAST_INTERRUPT_COUNT=$wake0InterruptCount, got $timerLastInterruptCount" }
if ($interruptCount -ne $wake0InterruptCount) { throw "Expected INTERRUPT_COUNT=$wake0InterruptCount, got $interruptCount" }
if ($lastInterruptVector -ne 200) { throw "Expected LAST_INTERRUPT_VECTOR=200, got $lastInterruptVector" }

Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_TELEMETRY_PRESERVE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_TELEMETRY_PRESERVE_PROBE_SOURCE=baremetal-qemu-timer-disable-interrupt-probe-check.ps1'
Write-Output "WAKE0_INTERRUPT_COUNT=$wake0InterruptCount"
Write-Output "WAKE1_INTERRUPT_COUNT=$wake1InterruptCount"
Write-Output "TIMER_LAST_INTERRUPT_COUNT=$timerLastInterruptCount"
Write-Output "INTERRUPT_COUNT=$interruptCount"
Write-Output "LAST_INTERRUPT_VECTOR=$lastInterruptVector"
