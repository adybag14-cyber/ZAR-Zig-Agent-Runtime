# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-manual-wait-interrupt-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\\d+)\\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_INTERRUPT_TELEMETRY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_INTERRUPT_TELEMETRY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-manual-wait-interrupt-probe-check.ps1' `
    -FailureLabel 'manual-wait interrupt' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$afterInterruptInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_INTERRUPT_COUNT'
$afterInterruptLastVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_LAST_VECTOR'
$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_INTERRUPT_COUNT'
$lastInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_LAST_INTERRUPT_VECTOR'
if ($null -in @($afterInterruptInterruptCount, $afterInterruptLastVector, $interruptCount, $lastInterruptVector)) {
    throw 'Missing expected interrupt telemetry fields in manual-wait interrupt probe output.'
}
if ($afterInterruptInterruptCount -lt 1) { throw "Expected AFTER_INTERRUPT_INTERRUPT_COUNT >= 1, got $afterInterruptInterruptCount" }
if ($afterInterruptLastVector -ne 44) { throw "Expected AFTER_INTERRUPT_LAST_VECTOR=44, got $afterInterruptLastVector" }
if ($interruptCount -ne $afterInterruptInterruptCount) { throw "Expected INTERRUPT_COUNT to remain $afterInterruptInterruptCount, got $interruptCount" }
if ($lastInterruptVector -ne 44) { throw "Expected LAST_INTERRUPT_VECTOR=44, got $lastInterruptVector" }

Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_INTERRUPT_TELEMETRY_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_INTERRUPT_TELEMETRY_PROBE_SOURCE=baremetal-qemu-manual-wait-interrupt-probe-check.ps1'
Write-Output "AFTER_INTERRUPT_INTERRUPT_COUNT=$afterInterruptInterruptCount"
Write-Output "AFTER_INTERRUPT_LAST_VECTOR=$afterInterruptLastVector"
Write-Output "INTERRUPT_COUNT=$interruptCount"
Write-Output "LAST_INTERRUPT_VECTOR=$lastInterruptVector"
