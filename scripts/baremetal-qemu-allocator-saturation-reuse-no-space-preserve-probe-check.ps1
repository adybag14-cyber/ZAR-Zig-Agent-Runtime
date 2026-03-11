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
    Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_NO_SPACE_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying allocator saturation-reuse probe failed with exit code $probeExitCode"
}
$preFreeLastAllocPtr = Extract-IntValue -Text $probeText -Name 'PRE_FREE_LAST_ALLOC_PTR'
$preFreeReuseRecordPtr = Extract-IntValue -Text $probeText -Name 'PRE_FREE_REUSE_RECORD_PTR'
$preFreeReuseRecordPageStart = Extract-IntValue -Text $probeText -Name 'PRE_FREE_REUSE_RECORD_PAGE_START'
$preFreeLastRecordPtr = Extract-IntValue -Text $probeText -Name 'PRE_FREE_LAST_RECORD_PTR'
$preFreeLastRecordPageStart = Extract-IntValue -Text $probeText -Name 'PRE_FREE_LAST_RECORD_PAGE_START'
if ($null -in @($preFreeLastAllocPtr,$preFreeReuseRecordPtr,$preFreeReuseRecordPageStart,$preFreeLastRecordPtr,$preFreeLastRecordPageStart)) { throw 'Missing no-space preservation allocator saturation-reuse fields.' }
if ($preFreeLastAllocPtr -ne 1306624) { throw "Expected PRE_FREE_LAST_ALLOC_PTR=1306624. got $preFreeLastAllocPtr" }
if ($preFreeReuseRecordPtr -ne 1069056) { throw "Expected PRE_FREE_REUSE_RECORD_PTR=1069056. got $preFreeReuseRecordPtr" }
if ($preFreeReuseRecordPageStart -ne 5) { throw "Expected PRE_FREE_REUSE_RECORD_PAGE_START=5. got $preFreeReuseRecordPageStart" }
if ($preFreeLastRecordPtr -ne 1306624) { throw "Expected PRE_FREE_LAST_RECORD_PTR=1306624. got $preFreeLastRecordPtr" }
if ($preFreeLastRecordPageStart -ne 63) { throw "Expected PRE_FREE_LAST_RECORD_PAGE_START=63. got $preFreeLastRecordPageStart" }
Write-Output 'BAREMETAL_QEMU_ALLOCATOR_SATURATION_REUSE_NO_SPACE_PRESERVE_PROBE=pass'
Write-Output "PRE_FREE_LAST_ALLOC_PTR=$preFreeLastAllocPtr"
Write-Output "PRE_FREE_REUSE_RECORD_PTR=$preFreeReuseRecordPtr"
Write-Output "PRE_FREE_REUSE_RECORD_PAGE_START=$preFreeReuseRecordPageStart"
Write-Output "PRE_FREE_LAST_RECORD_PTR=$preFreeLastRecordPtr"
Write-Output "PRE_FREE_LAST_RECORD_PAGE_START=$preFreeLastRecordPageStart"
