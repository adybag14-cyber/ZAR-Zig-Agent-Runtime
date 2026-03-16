# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$output = & $probe @invoke 2>&1
$exitCode = $LASTEXITCODE
$outputText = ($output | Out-String)
if ($outputText -match '(?m)^BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PROBE=skipped\r?$') {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PRE_RESET_PAYLOADS_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PRE_RESET_PAYLOADS_PROBE_SOURCE=baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    throw "Bootdiag/history-clear prerequisite probe failed with exit code $exitCode"
}

$phase = Extract-IntValue -Text $outputText -Name 'PRE_RESET_PHASE'
$lastSeq = Extract-IntValue -Text $outputText -Name 'PRE_RESET_LAST_SEQ'
$lastTick = Extract-IntValue -Text $outputText -Name 'PRE_RESET_LAST_TICK'
$observedTick = Extract-IntValue -Text $outputText -Name 'PRE_RESET_OBSERVED_TICK'
$stack = Extract-IntValue -Text $outputText -Name 'PRE_RESET_STACK'
$phaseChanges = Extract-IntValue -Text $outputText -Name 'PRE_RESET_PHASE_CHANGES'

if ($phase -ne 1 -or $lastSeq -ne 3 -or $lastTick -ne 2 -or $observedTick -ne 3 -or $phaseChanges -ne 1 -or $stack -le 0) {
    throw "Unexpected pre-reset payloads. phase=$phase lastSeq=$lastSeq lastTick=$lastTick observedTick=$observedTick stack=$stack phaseChanges=$phaseChanges"
}

Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PRE_RESET_PAYLOADS_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PRE_RESET_PAYLOADS_PROBE_SOURCE=baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
Write-Output "PRE_RESET_PHASE=$phase"
Write-Output "PRE_RESET_LAST_SEQ=$lastSeq"
Write-Output "PRE_RESET_LAST_TICK=$lastTick"
Write-Output "PRE_RESET_OBSERVED_TICK=$observedTick"
Write-Output "PRE_RESET_STACK=$stack"
Write-Output "PRE_RESET_PHASE_CHANGES=$phaseChanges"
