# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 45,
    [int] $GdbPort = 1287
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-syscall-control-probe-check.ps1'
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
if ($text -match '(?m)^BAREMETAL_QEMU_SYSCALL_CONTROL_PROBE=skipped\r?$') {
    if ($text) { Write-Output $text.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_BASELINE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_BASELINE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($text) { Write-Output $text.TrimEnd() }
    throw "Syscall-control prerequisite probe failed with exit code $exitCode"
}

$expected = @{
    'ACK' = 13
    'LAST_OPCODE' = 35
    'LAST_RESULT' = -2
    'STATUS_MODE' = 1
}
foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $text -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_BASELINE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_SYSCALL_CONTROL_BASELINE_PROBE_SOURCE=baremetal-qemu-syscall-control-probe-check.ps1'
Write-Output 'ACK=13'
Write-Output 'LAST_OPCODE=35'
Write-Output 'LAST_RESULT=-2'
Write-Output 'STATUS_MODE=1'
