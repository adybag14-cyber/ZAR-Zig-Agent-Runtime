# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 45,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-syscall-saturation-reset-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$output = & $probe @invoke 2>&1
$exitCode = $LASTEXITCODE
$text = ($output | Out-String)
if ($text -match '(?m)^BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_PROBE=skipped\r?$') {
    if ($text) { Write-Output $text.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_PRE_RESET_SHAPE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_PRE_RESET_SHAPE_PROBE_SOURCE=baremetal-qemu-syscall-saturation-reset-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($text) { Write-Output $text.TrimEnd() }
    throw "Syscall saturation-reset prerequisite probe failed with exit code $exitCode"
}

$expected = @{
    'PRE_RESET_ENTRY_COUNT' = 64
    'PRE_RESET_DISPATCH_COUNT' = 1
    'PRE_RESET_LAST_ID' = 7
    'POST_RESET_ENABLED' = 1
}
foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $text -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_PRE_RESET_SHAPE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_SATURATION_RESET_PRE_RESET_SHAPE_PROBE_SOURCE=baremetal-qemu-syscall-saturation-reset-probe-check.ps1'
Write-Output 'PRE_RESET_ENTRY_COUNT=64'
Write-Output 'PRE_RESET_DISPATCH_COUNT=1'
Write-Output 'PRE_RESET_LAST_ID=7'
Write-Output 'POST_RESET_ENABLED=1'
