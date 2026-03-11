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
    Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BAD_POINTER_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying allocator free-failure probe failed with exit code $probeExitCode"
}
$badPtrResult = Extract-IntValue -Text $probeText -Name 'BAD_PTR_RESULT'
$badPtrFreePages = Extract-IntValue -Text $probeText -Name 'BAD_PTR_FREE_PAGES'
$badPtrCount = Extract-IntValue -Text $probeText -Name 'BAD_PTR_COUNT'
$badPtrLastFreePtr = Extract-IntValue -Text $probeText -Name 'BAD_PTR_LAST_FREE_PTR'
$badPtrLastFreeSize = Extract-IntValue -Text $probeText -Name 'BAD_PTR_LAST_FREE_SIZE'
if ($null -in @($badPtrResult,$badPtrFreePages,$badPtrCount,$badPtrLastFreePtr,$badPtrLastFreeSize)) { throw 'Missing bad-pointer allocator free-failure fields.' }
if ($badPtrResult -ne -2) { throw "Expected BAD_PTR_RESULT=-2. got $badPtrResult" }
if ($badPtrFreePages -ne 254) { throw "Expected BAD_PTR_FREE_PAGES=254. got $badPtrFreePages" }
if ($badPtrCount -ne 1) { throw "Expected BAD_PTR_COUNT=1. got $badPtrCount" }
if ($badPtrLastFreePtr -ne 0) { throw "Expected BAD_PTR_LAST_FREE_PTR=0. got $badPtrLastFreePtr" }
if ($badPtrLastFreeSize -ne 0) { throw "Expected BAD_PTR_LAST_FREE_SIZE=0. got $badPtrLastFreeSize" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_BAD_POINTER_PRESERVE_PROBE=pass'
Write-Output "BAD_PTR_RESULT=$badPtrResult"
Write-Output "BAD_PTR_FREE_PAGES=$badPtrFreePages"
Write-Output "BAD_PTR_COUNT=$badPtrCount"
Write-Output "BAD_PTR_LAST_FREE_PTR=$badPtrLastFreePtr"
Write-Output "BAD_PTR_LAST_FREE_SIZE=$badPtrLastFreeSize"

