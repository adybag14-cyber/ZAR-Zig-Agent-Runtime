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
    Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_RESET_CAPTURE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying descriptor-bootdiag probe failed with exit code $probeExitCode"
}

$bootSeqBefore = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_BOOT_SEQ_BEFORE'
$bootSeqAfterReset = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_BOOT_SEQ_AFTER_RESET'
$phaseAfterReset = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_AFTER_RESET'
$lastCommandSeqAfterReset = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LAST_COMMAND_SEQ_AFTER_RESET'
$phaseChangesAfterReset = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_PHASE_CHANGES_AFTER_RESET'
$stackSnapshotAfterCapture = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_STACK_SNAPSHOT_AFTER_CAPTURE'
$lastCommandSeqAfterCapture = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_PROBE_LAST_COMMAND_SEQ_AFTER_CAPTURE'

if ($null -in @($bootSeqBefore, $bootSeqAfterReset, $phaseAfterReset, $lastCommandSeqAfterReset, $phaseChangesAfterReset, $stackSnapshotAfterCapture, $lastCommandSeqAfterCapture)) {
    throw 'Missing expected reset/capture fields in descriptor-bootdiag probe output.'
}
if ($bootSeqAfterReset -ne ($bootSeqBefore + 1)) { throw "Expected BOOT_SEQ_AFTER_RESET=BOOT_SEQ_BEFORE+1. got $bootSeqAfterReset vs $bootSeqBefore" }
if ($phaseAfterReset -ne 2) { throw "Expected PHASE_AFTER_RESET=2. got $phaseAfterReset" }
if ($lastCommandSeqAfterReset -ne 1) { throw "Expected LAST_COMMAND_SEQ_AFTER_RESET=1. got $lastCommandSeqAfterReset" }
if ($phaseChangesAfterReset -ne 0) { throw "Expected PHASE_CHANGES_AFTER_RESET=0. got $phaseChangesAfterReset" }
if ($stackSnapshotAfterCapture -le 0) { throw "Expected STACK_SNAPSHOT_AFTER_CAPTURE>0. got $stackSnapshotAfterCapture" }
if ($lastCommandSeqAfterCapture -ne 2) { throw "Expected LAST_COMMAND_SEQ_AFTER_CAPTURE=2. got $lastCommandSeqAfterCapture" }

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_BOOTDIAG_RESET_CAPTURE_PROBE=pass'
Write-Output "BOOT_SEQ_BEFORE=$bootSeqBefore"
Write-Output "BOOT_SEQ_AFTER_RESET=$bootSeqAfterReset"
Write-Output "PHASE_AFTER_RESET=$phaseAfterReset"
Write-Output "LAST_COMMAND_SEQ_AFTER_RESET=$lastCommandSeqAfterReset"
Write-Output "PHASE_CHANGES_AFTER_RESET=$phaseChangesAfterReset"
Write-Output "STACK_SNAPSHOT_AFTER_CAPTURE=$stackSnapshotAfterCapture"
Write-Output "LAST_COMMAND_SEQ_AFTER_CAPTURE=$lastCommandSeqAfterCapture"
