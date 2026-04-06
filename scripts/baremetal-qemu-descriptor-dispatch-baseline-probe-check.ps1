# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-dispatch-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-descriptor-dispatch-probe-check.ps1' `
    -FailureLabel 'descriptor-dispatch'
$probeText = $probeState.Text

function Extract-Value {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(.+)\\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}


$artifact = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_ARTIFACT'
$startAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_START_ADDR'
$spinPauseAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_SPINPAUSE_ADDR'
$interruptStateAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_STATE_ADDR'
$interruptHistoryAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_INTERRUPT_HISTORY_ADDR'
$exceptionHistoryAddr = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_EXCEPTION_HISTORY_ADDR'
$hitStart = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_HIT_START'
$hitAfter = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_HIT_AFTER_DESCRIPTOR_DISPATCH'
$ticksRaw = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE_TICKS'
if ([string]::IsNullOrWhiteSpace($ticksRaw)) { throw 'Missing TICKS in descriptor-dispatch baseline output.' }
$ticks = [int64]::Parse($ticksRaw)

if ([string]::IsNullOrWhiteSpace($artifact) -or [string]::IsNullOrWhiteSpace($startAddr) -or [string]::IsNullOrWhiteSpace($spinPauseAddr) -or [string]::IsNullOrWhiteSpace($interruptStateAddr) -or [string]::IsNullOrWhiteSpace($interruptHistoryAddr) -or [string]::IsNullOrWhiteSpace($exceptionHistoryAddr)) {
    throw 'Missing descriptor-dispatch baseline address or artifact fields.'
}
if ($hitStart -ne 'True') { throw 'Expected descriptor-dispatch HIT_START=True.' }
if ($hitAfter -ne 'True') { throw 'Expected descriptor-dispatch HIT_AFTER_DESCRIPTOR_DISPATCH=True.' }
if ($ticks -lt 8) { throw "Expected descriptor-dispatch TICKS>=8. got $ticks" }

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_BASELINE_PROBE=pass'
Write-Output "ARTIFACT=$artifact"
Write-Output "START_ADDR=$startAddr"
Write-Output "SPINPAUSE_ADDR=$spinPauseAddr"
Write-Output "INTERRUPT_STATE_ADDR=$interruptStateAddr"
Write-Output "INTERRUPT_HISTORY_ADDR=$interruptHistoryAddr"
Write-Output "EXCEPTION_HISTORY_ADDR=$exceptionHistoryAddr"
Write-Output "TICKS=$ticks"
