# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-descriptor-table-content-probe-check.ps1"

function Extract-Value {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(.+?)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

function Extract-Field {
    param([string] $BroadText, [string] $RawText, [string] $Name)
    $value = Extract-IntValue -Text $BroadText -Name $Name
    if ($null -ne $value) { return $value }
    return Extract-IntValue -Text $RawText -Name $Name
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_GDT_ENTRY_FIELDS_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying descriptor-table-content probe failed with exit code $probeExitCode"
}

$gdbStdout = Extract-Value -Text $probeText -Name 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_PROBE_GDB_STDOUT'
if ([string]::IsNullOrWhiteSpace($gdbStdout) -or -not (Test-Path $gdbStdout)) {
    throw 'Missing descriptor-table-content GDB stdout log path.'
}
$rawText = Get-Content -Raw $gdbStdout

$gdt1LimitLow = Extract-Field -BroadText $probeText -RawText $rawText -Name 'GDT1_LIMIT_LOW'
$gdt1Access = Extract-Field -BroadText $probeText -RawText $rawText -Name 'GDT1_ACCESS'
$gdt1Granularity = Extract-Field -BroadText $probeText -RawText $rawText -Name 'GDT1_GRANULARITY'
$gdt2LimitLow = Extract-Field -BroadText $probeText -RawText $rawText -Name 'GDT2_LIMIT_LOW'
$gdt2Access = Extract-Field -BroadText $probeText -RawText $rawText -Name 'GDT2_ACCESS'
$gdt2Granularity = Extract-Field -BroadText $probeText -RawText $rawText -Name 'GDT2_GRANULARITY'

if ($null -in @($gdt1LimitLow, $gdt1Access, $gdt1Granularity, $gdt2LimitLow, $gdt2Access, $gdt2Granularity)) {
    throw 'Missing GDT entry fields.'
}
if ($gdt1LimitLow -ne 65535 -or $gdt1Access -ne 154 -or $gdt1Granularity -ne 175) {
    throw 'Unexpected GDT code entry fields.'
}
if ($gdt2LimitLow -ne 65535 -or $gdt2Access -ne 146 -or $gdt2Granularity -ne 175) {
    throw 'Unexpected GDT data entry fields.'
}

Write-Output 'BAREMETAL_QEMU_DESCRIPTOR_TABLE_CONTENT_GDT_ENTRY_FIELDS_PROBE=pass'
Write-Output "GDT1_ACCESS=$gdt1Access"
Write-Output "GDT2_ACCESS=$gdt2Access"
Write-Output "GDT1_GRANULARITY=$gdt1Granularity"
Write-Output "GDT2_GRANULARITY=$gdt2Granularity"
