# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-allocator-saturation-reuse-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FULL_TABLE_SHAPE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying allocator saturation-reuse probe failed with exit code $probeExitCode"
}
$preFreeAllocationCount = Extract-IntValue -Text $probeText -Name 'PRE_FREE_ALLOCATION_COUNT'
$preFreeFreePages = Extract-IntValue -Text $probeText -Name 'PRE_FREE_FREE_PAGES'
$preFreeAllocOps = Extract-IntValue -Text $probeText -Name 'PRE_FREE_ALLOC_OPS'
$preFreeBytesInUse = Extract-IntValue -Text $probeText -Name 'PRE_FREE_BYTES_IN_USE'
$preFreePeakBytes = Extract-IntValue -Text $probeText -Name 'PRE_FREE_PEAK_BYTES'
if ($null -in @($preFreeAllocationCount,$preFreeFreePages,$preFreeAllocOps,$preFreeBytesInUse,$preFreePeakBytes)) { throw 'Missing full-table allocator saturation-reuse fields.' }
if ($preFreeAllocationCount -ne 64) { throw "Expected PRE_FREE_ALLOCATION_COUNT=64. got $preFreeAllocationCount" }
if ($preFreeFreePages -ne 192) { throw "Expected PRE_FREE_FREE_PAGES=192. got $preFreeFreePages" }
if ($preFreeAllocOps -ne 64) { throw "Expected PRE_FREE_ALLOC_OPS=64. got $preFreeAllocOps" }
if ($preFreeBytesInUse -ne 262144) { throw "Expected PRE_FREE_BYTES_IN_USE=262144. got $preFreeBytesInUse" }
if ($preFreePeakBytes -ne 262144) { throw "Expected PRE_FREE_PEAK_BYTES=262144. got $preFreePeakBytes" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FULL_TABLE_SHAPE_PROBE=pass'
Write-Output "PRE_FREE_ALLOCATION_COUNT=$preFreeAllocationCount"
Write-Output "PRE_FREE_FREE_PAGES=$preFreeFreePages"
Write-Output "PRE_FREE_ALLOC_OPS=$preFreeAllocOps"
Write-Output "PRE_FREE_BYTES_IN_USE=$preFreeBytesInUse"
Write-Output "PRE_FREE_PEAK_BYTES=$preFreePeakBytes"
