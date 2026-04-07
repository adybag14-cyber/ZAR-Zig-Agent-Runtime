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
    -SkippedReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_FINAL_TELEMETRY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_FINAL_TELEMETRY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-manual-wait-interrupt-probe-check.ps1' `
    -FailureLabel 'manual-wait interrupt' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_INTERRUPT_COUNT'
$lastVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_LAST_INTERRUPT_VECTOR'
$manualWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_TICK'
if ($null -in @($interruptCount, $lastVector, $manualWakeTick)) { throw 'Missing final-telemetry fields in manual-wait-interrupt probe output.' }
if ($interruptCount -ne 1) { throw "Expected INTERRUPT_COUNT=1, got $interruptCount" }
if ($lastVector -ne 44) { throw "Expected LAST_INTERRUPT_VECTOR=44, got $lastVector" }
if ($manualWakeTick -le 0) { throw "Expected MANUAL_WAKE_TICK > 0, got $manualWakeTick" }
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_FINAL_TELEMETRY_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_FINAL_TELEMETRY_PROBE_SOURCE=baremetal-qemu-manual-wait-interrupt-probe-check.ps1'
Write-Output 'INTERRUPT_COUNT=1'
Write-Output 'LAST_INTERRUPT_VECTOR=44'
Write-Output "MANUAL_WAKE_TICK=$manualWakeTick"
