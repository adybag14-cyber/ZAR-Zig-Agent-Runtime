# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-bootdiag-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_INVALID_PHASE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying descriptor-bootdiag probe failed with exit code $probeExitCode"
}

$invalidResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_INVALID_RESULT'
$phaseAfterInvalid = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_AFTER_INVALID'
$phaseChangesAfterInvalid = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_CHANGES_AFTER_INVALID'

if ($null -in @($invalidResult, $phaseAfterInvalid, $phaseChangesAfterInvalid)) {
    throw 'Missing expected invalid-phase fields in descriptor-bootdiag probe output.'
}
if ($invalidResult -ne -22) { throw "Expected INVALID_RESULT=-22. got $invalidResult" }
if ($phaseAfterInvalid -ne 1) { throw "Expected PHASE_AFTER_INVALID=1. got $phaseAfterInvalid" }
if ($phaseChangesAfterInvalid -ne 1) { throw "Expected PHASE_CHANGES_AFTER_INVALID=1. got $phaseChangesAfterInvalid" }

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_INVALID_PHASE_PROBE=pass'
Write-Output "INVALID_RESULT=$invalidResult"
Write-Output "PHASE_AFTER_INVALID=$phaseAfterInvalid"
Write-Output "PHASE_CHANGES_AFTER_INVALID=$phaseChangesAfterInvalid"
