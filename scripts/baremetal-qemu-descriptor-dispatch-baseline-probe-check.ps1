# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-dispatch-probe-check.ps1"

function Extract-Value {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(.+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_DISPATCH_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying descriptor-dispatch probe failed with exit code $probeExitCode"
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
