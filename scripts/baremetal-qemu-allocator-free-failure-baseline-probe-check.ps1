# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-free-failure-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying allocator free-failure probe failed with exit code $probeExitCode"
}
$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$allocPtr = Extract-IntValue -Text $probeText -Name 'ALLOC_PTR'
$allocFreePages = Extract-IntValue -Text $probeText -Name 'ALLOC_FREE_PAGES'
$allocCount = Extract-IntValue -Text $probeText -Name 'ALLOC_COUNT'
if ($null -in @($ack,$lastOpcode,$lastResult,$allocPtr,$allocFreePages,$allocCount)) { throw 'Missing baseline allocator free-failure fields.' }
if ($ack -ne 7) { throw "Expected ACK=7. got $ack" }
if ($lastOpcode -ne 32) { throw "Expected LAST_OPCODE=32. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($allocPtr -ne 1048576) { throw "Expected ALLOC_PTR=1048576. got $allocPtr" }
if ($allocFreePages -ne 254) { throw "Expected ALLOC_FREE_PAGES=254. got $allocFreePages" }
if ($allocCount -ne 1) { throw "Expected ALLOC_COUNT=1. got $allocCount" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BASELINE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "ALLOC_PTR=$allocPtr"
Write-Output "ALLOC_FREE_PAGES=$allocFreePages"
Write-Output "ALLOC_COUNT=$allocCount"

