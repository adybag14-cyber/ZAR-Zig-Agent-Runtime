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
    Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FRESH_RESTART_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying allocator saturation-reuse probe failed with exit code $probeExitCode"
}
$postReusePtr = Extract-IntValue -Text $probeText -Name 'POST_REUSE_PTR'
$postReusePageStart = Extract-IntValue -Text $probeText -Name 'POST_REUSE_PAGE_START'
$postReusePageLen = Extract-IntValue -Text $probeText -Name 'POST_REUSE_PAGE_LEN'
$postReuseAllocationCount = Extract-IntValue -Text $probeText -Name 'POST_REUSE_ALLOCATION_COUNT'
$postReuseFreePages = Extract-IntValue -Text $probeText -Name 'POST_REUSE_FREE_PAGES'
$postReuseAllocOps = Extract-IntValue -Text $probeText -Name 'POST_REUSE_ALLOC_OPS'
$postReuseBytesInUse = Extract-IntValue -Text $probeText -Name 'POST_REUSE_BYTES_IN_USE'
$postReusePeakBytes = Extract-IntValue -Text $probeText -Name 'POST_REUSE_PEAK_BYTES'
$postReuseLastAllocPtr = Extract-IntValue -Text $probeText -Name 'POST_REUSE_LAST_ALLOC_PTR'
$postReuseLastAllocSize = Extract-IntValue -Text $probeText -Name 'POST_REUSE_LAST_ALLOC_SIZE'
$postReuseNeighborState = Extract-IntValue -Text $probeText -Name 'POST_REUSE_NEIGHBOR_STATE'
$postReuseBitmap64 = Extract-IntValue -Text $probeText -Name 'POST_REUSE_BITMAP64'
$postReuseBitmap65 = Extract-IntValue -Text $probeText -Name 'POST_REUSE_BITMAP65'
if ($null -in @($postReusePtr,$postReusePageStart,$postReusePageLen,$postReuseAllocationCount,$postReuseFreePages,$postReuseAllocOps,$postReuseBytesInUse,$postReusePeakBytes,$postReuseLastAllocPtr,$postReuseLastAllocSize,$postReuseNeighborState,$postReuseBitmap64,$postReuseBitmap65)) { throw 'Missing fresh-restart allocator saturation-reuse fields.' }
if ($postReusePtr -ne 1310720) { throw "Expected POST_REUSE_PTR=1310720. got $postReusePtr" }
if ($postReusePageStart -ne 64) { throw "Expected POST_REUSE_PAGE_START=64. got $postReusePageStart" }
if ($postReusePageLen -ne 2) { throw "Expected POST_REUSE_PAGE_LEN=2. got $postReusePageLen" }
if ($postReuseAllocationCount -ne 64) { throw "Expected POST_REUSE_ALLOCATION_COUNT=64. got $postReuseAllocationCount" }
if ($postReuseFreePages -ne 191) { throw "Expected POST_REUSE_FREE_PAGES=191. got $postReuseFreePages" }
if ($postReuseAllocOps -ne 65) { throw "Expected POST_REUSE_ALLOC_OPS=65. got $postReuseAllocOps" }
if ($postReuseBytesInUse -ne 266240) { throw "Expected POST_REUSE_BYTES_IN_USE=266240. got $postReuseBytesInUse" }
if ($postReusePeakBytes -ne 266240) { throw "Expected POST_REUSE_PEAK_BYTES=266240. got $postReusePeakBytes" }
if ($postReuseLastAllocPtr -ne 1310720) { throw "Expected POST_REUSE_LAST_ALLOC_PTR=1310720. got $postReuseLastAllocPtr" }
if ($postReuseLastAllocSize -ne 8192) { throw "Expected POST_REUSE_LAST_ALLOC_SIZE=8192. got $postReuseLastAllocSize" }
if ($postReuseNeighborState -ne 1) { throw "Expected POST_REUSE_NEIGHBOR_STATE=1. got $postReuseNeighborState" }
if ($postReuseBitmap64 -ne 1 -or $postReuseBitmap65 -ne 1) { throw "Expected POST_REUSE_BITMAP64/65=1/1. got $postReuseBitmap64/$postReuseBitmap65" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FRESH_RESTART_PROBE=pass'
Write-Output "POST_REUSE_PTR=$postReusePtr"
Write-Output "POST_REUSE_PAGE_START=$postReusePageStart"
Write-Output "POST_REUSE_PAGE_LEN=$postReusePageLen"
Write-Output "POST_REUSE_ALLOCATION_COUNT=$postReuseAllocationCount"
Write-Output "POST_REUSE_FREE_PAGES=$postReuseFreePages"
Write-Output "POST_REUSE_ALLOC_OPS=$postReuseAllocOps"
Write-Output "POST_REUSE_BYTES_IN_USE=$postReuseBytesInUse"
Write-Output "POST_REUSE_PEAK_BYTES=$postReusePeakBytes"
Write-Output "POST_REUSE_LAST_ALLOC_PTR=$postReuseLastAllocPtr"
Write-Output "POST_REUSE_LAST_ALLOC_SIZE=$postReuseLastAllocSize"
Write-Output "POST_REUSE_NEIGHBOR_STATE=$postReuseNeighborState"
Write-Output "POST_REUSE_BITMAP64=$postReuseBitmap64"
Write-Output "POST_REUSE_BITMAP65=$postReuseBitmap65"
