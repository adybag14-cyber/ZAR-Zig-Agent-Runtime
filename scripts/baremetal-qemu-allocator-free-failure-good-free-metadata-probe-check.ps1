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
    Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_GOOD_FREE_METADATA_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying allocator free-failure probe failed with exit code $probeExitCode"
}
$allocPtr = Extract-IntValue -Text $probeText -Name 'ALLOC_PTR'
$goodFreeResult = Extract-IntValue -Text $probeText -Name 'GOOD_FREE_RESULT'
$goodFreeFreePages = Extract-IntValue -Text $probeText -Name 'GOOD_FREE_FREE_PAGES'
$goodFreeCount = Extract-IntValue -Text $probeText -Name 'GOOD_FREE_COUNT'
$goodFreeLastFreePtr = Extract-IntValue -Text $probeText -Name 'GOOD_FREE_LAST_FREE_PTR'
$goodFreeLastFreeSize = Extract-IntValue -Text $probeText -Name 'GOOD_FREE_LAST_FREE_SIZE'
if ($null -in @($allocPtr,$goodFreeResult,$goodFreeFreePages,$goodFreeCount,$goodFreeLastFreePtr,$goodFreeLastFreeSize)) { throw 'Missing good-free allocator free-failure fields.' }
if ($goodFreeResult -ne 0) { throw "Expected GOOD_FREE_RESULT=0. got $goodFreeResult" }
if ($goodFreeFreePages -ne 256) { throw "Expected GOOD_FREE_FREE_PAGES=256. got $goodFreeFreePages" }
if ($goodFreeCount -ne 0) { throw "Expected GOOD_FREE_COUNT=0. got $goodFreeCount" }
if ($goodFreeLastFreePtr -ne $allocPtr) { throw "Expected GOOD_FREE_LAST_FREE_PTR=$allocPtr. got $goodFreeLastFreePtr" }
if ($goodFreeLastFreeSize -ne 8192) { throw "Expected GOOD_FREE_LAST_FREE_SIZE=8192. got $goodFreeLastFreeSize" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_FREE_FAILURE_GOOD_FREE_METADATA_PROBE=pass'
Write-Output "GOOD_FREE_RESULT=$goodFreeResult"
Write-Output "GOOD_FREE_FREE_PAGES=$goodFreeFreePages"
Write-Output "GOOD_FREE_COUNT=$goodFreeCount"
Write-Output "GOOD_FREE_LAST_FREE_PTR=$goodFreeLastFreePtr"
Write-Output "GOOD_FREE_LAST_FREE_SIZE=$goodFreeLastFreeSize"

