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
    Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BAD_SIZE_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying allocator free-failure probe failed with exit code $probeExitCode"
}
$badSizeResult = Extract-IntValue -Text $probeText -Name 'BAD_SIZE_RESULT'
$badSizeFreePages = Extract-IntValue -Text $probeText -Name 'BAD_SIZE_FREE_PAGES'
$badSizeCount = Extract-IntValue -Text $probeText -Name 'BAD_SIZE_COUNT'
$badSizeLastFreePtr = Extract-IntValue -Text $probeText -Name 'BAD_SIZE_LAST_FREE_PTR'
$badSizeLastFreeSize = Extract-IntValue -Text $probeText -Name 'BAD_SIZE_LAST_FREE_SIZE'
if ($null -in @($badSizeResult,$badSizeFreePages,$badSizeCount,$badSizeLastFreePtr,$badSizeLastFreeSize)) { throw 'Missing bad-size allocator free-failure fields.' }
if ($badSizeResult -ne -22) { throw "Expected BAD_SIZE_RESULT=-22. got $badSizeResult" }
if ($badSizeFreePages -ne 254) { throw "Expected BAD_SIZE_FREE_PAGES=254. got $badSizeFreePages" }
if ($badSizeCount -ne 1) { throw "Expected BAD_SIZE_COUNT=1. got $badSizeCount" }
if ($badSizeLastFreePtr -ne 0) { throw "Expected BAD_SIZE_LAST_FREE_PTR=0. got $badSizeLastFreePtr" }
if ($badSizeLastFreeSize -ne 0) { throw "Expected BAD_SIZE_LAST_FREE_SIZE=0. got $badSizeLastFreeSize" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BAD_SIZE_PRESERVE_PROBE=pass'
Write-Output "BAD_SIZE_RESULT=$badSizeResult"
Write-Output "BAD_SIZE_FREE_PAGES=$badSizeFreePages"
Write-Output "BAD_SIZE_COUNT=$badSizeCount"
Write-Output "BAD_SIZE_LAST_FREE_PTR=$badSizeLastFreePtr"
Write-Output "BAD_SIZE_LAST_FREE_SIZE=$badSizeLastFreeSize"

