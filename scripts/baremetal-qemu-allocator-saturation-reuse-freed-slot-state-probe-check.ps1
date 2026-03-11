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
    Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FREED_SLOT_STATE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying allocator saturation-reuse probe failed with exit code $probeExitCode"
}
$postFreeAllocationCount = Extract-IntValue -Text $probeText -Name 'POST_FREE_ALLOCATION_COUNT'
$postFreeFreePages = Extract-IntValue -Text $probeText -Name 'POST_FREE_FREE_PAGES'
$postFreeFreeOps = Extract-IntValue -Text $probeText -Name 'POST_FREE_FREE_OPS'
$postFreeLastFreePtr = Extract-IntValue -Text $probeText -Name 'POST_FREE_LAST_FREE_PTR'
$postFreeLastFreeSize = Extract-IntValue -Text $probeText -Name 'POST_FREE_LAST_FREE_SIZE'
$postFreeReuseRecordState = Extract-IntValue -Text $probeText -Name 'POST_FREE_REUSE_RECORD_STATE'
$postFreeBitmapReuseSlot = Extract-IntValue -Text $probeText -Name 'POST_FREE_BITMAP_REUSE_SLOT'
if ($null -in @($postFreeAllocationCount,$postFreeFreePages,$postFreeFreeOps,$postFreeLastFreePtr,$postFreeLastFreeSize,$postFreeReuseRecordState,$postFreeBitmapReuseSlot)) { throw 'Missing freed-slot allocator saturation-reuse fields.' }
if ($postFreeAllocationCount -ne 63) { throw "Expected POST_FREE_ALLOCATION_COUNT=63. got $postFreeAllocationCount" }
if ($postFreeFreePages -ne 193) { throw "Expected POST_FREE_FREE_PAGES=193. got $postFreeFreePages" }
if ($postFreeFreeOps -ne 1) { throw "Expected POST_FREE_FREE_OPS=1. got $postFreeFreeOps" }
if ($postFreeLastFreePtr -ne 1069056) { throw "Expected POST_FREE_LAST_FREE_PTR=1069056. got $postFreeLastFreePtr" }
if ($postFreeLastFreeSize -ne 4096) { throw "Expected POST_FREE_LAST_FREE_SIZE=4096. got $postFreeLastFreeSize" }
if ($postFreeReuseRecordState -ne 0) { throw "Expected POST_FREE_REUSE_RECORD_STATE=0. got $postFreeReuseRecordState" }
if ($postFreeBitmapReuseSlot -ne 0) { throw "Expected POST_FREE_BITMAP_REUSE_SLOT=0. got $postFreeBitmapReuseSlot" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_FREED_SLOT_STATE_PROBE=pass'
Write-Output "POST_FREE_ALLOCATION_COUNT=$postFreeAllocationCount"
Write-Output "POST_FREE_FREE_PAGES=$postFreeFreePages"
Write-Output "POST_FREE_FREE_OPS=$postFreeFreeOps"
Write-Output "POST_FREE_LAST_FREE_PTR=$postFreeLastFreePtr"
Write-Output "POST_FREE_LAST_FREE_SIZE=$postFreeLastFreeSize"
Write-Output "POST_FREE_REUSE_RECORD_STATE=$postFreeReuseRecordState"
Write-Output "POST_FREE_BITMAP_REUSE_SLOT=$postFreeBitmapReuseSlot"
