# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-boot-phase-history-overflow-clear-probe-check.ps1'
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
if ($outputText -match '(?m)^BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_PROBE=skipped\r?$') {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_CLEAR_COLLAPSE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_CLEAR_COLLAPSE_PROBE_SOURCE=baremetal-qemu-boot-phase-history-overflow-clear-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    throw "Boot-phase-history overflow/clear prerequisite probe failed with exit code $exitCode"
}

$clearLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_LEN'
$clearHead = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_HEAD'
$clearOverflow = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_OVERFLOW'
$clearSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_SEQ'
if ($clearLen -ne 0 -or $clearHead -ne 0 -or $clearOverflow -ne 0 -or $clearSeq -ne 0) {
    throw "Unexpected clear collapse. clearLen=$clearLen clearHead=$clearHead clearOverflow=$clearOverflow clearSeq=$clearSeq"
}

Write-Output 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_CLEAR_COLLAPSE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_CLEAR_COLLAPSE_PROBE_SOURCE=baremetal-qemu-boot-phase-history-overflow-clear-probe-check.ps1'
Write-Output "CLEAR_LEN=$clearLen"
Write-Output "CLEAR_HEAD=$clearHead"
Write-Output "CLEAR_OVERFLOW=$clearOverflow"
Write-Output "CLEAR_SEQ=$clearSeq"
