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
    Write-Output 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_TELEMETRY_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying masked interrupt-timeout probe failed with exit code $probeExitCode"
}

$maskedIgnoredAfterInterrupt = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_MASKED_IGNORED_AFTER_INTERRUPT'
$maskedInterruptIgnoredCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_MASKED_INTERRUPT_IGNORED_COUNT'
$lastMaskedInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_LAST_MASKED_INTERRUPT_VECTOR'
$timerLastInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_TIMER_LAST_INTERRUPT_COUNT'
$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_INTERRUPT_COUNT'
$lastInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_LAST_INTERRUPT_VECTOR'
if ($null -in @($maskedIgnoredAfterInterrupt, $maskedInterruptIgnoredCount, $lastMaskedInterruptVector, $timerLastInterruptCount, $interruptCount, $lastInterruptVector)) {
    throw 'Missing telemetry-preserve fields in probe output.'
}
if ($maskedIgnoredAfterInterrupt -ne 1) { throw "Expected masked-stage ignored count to be 1. got $maskedIgnoredAfterInterrupt" }
if ($maskedInterruptIgnoredCount -ne 1) { throw "Expected final ignored count to remain 1. got $maskedInterruptIgnoredCount" }
if ($lastMaskedInterruptVector -ne 200) { throw "Expected final last masked vector 200. got $lastMaskedInterruptVector" }
if ($timerLastInterruptCount -ne 0) { throw "Expected timer last interrupt count to remain 0. got $timerLastInterruptCount" }
if ($interruptCount -ne 0) { throw "Expected final interrupt count to remain 0. got $interruptCount" }
if ($lastInterruptVector -ne 0) { throw "Expected final last interrupt vector to remain 0. got $lastInterruptVector" }

Write-Output 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_TELEMETRY_PRESERVE_PROBE=pass'
Write-Output "MASKED_IGNORED_AFTER_INTERRUPT=$maskedIgnoredAfterInterrupt"
Write-Output "MASKED_INTERRUPT_IGNORED_COUNT=$maskedInterruptIgnoredCount"
Write-Output "LAST_MASKED_INTERRUPT_VECTOR=$lastMaskedInterruptVector"
Write-Output "TIMER_LAST_INTERRUPT_COUNT=$timerLastInterruptCount"
Write-Output "INTERRUPT_COUNT=$interruptCount"
Write-Output "LAST_INTERRUPT_VECTOR=$lastInterruptVector"
