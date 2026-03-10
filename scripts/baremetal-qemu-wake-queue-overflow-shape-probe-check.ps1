param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-overflow-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild -TimeoutSeconds 90 2>&1 } else { & $probe -TimeoutSeconds 90 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_SHAPE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-overflow probe failed with exit code $probeExitCode"
}

$count = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_COUNT'
$head = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_HEAD'
$tail = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_TAIL'
$overflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_OVERFLOW'

if ($null -in @($count, $head, $tail, $overflow)) {
    throw 'Missing expected shape fields in wake-queue-overflow probe output.'
}
if ($count -ne 64) { throw "Expected COUNT=64. got $count" }
if ($head -ne 2) { throw "Expected HEAD=2. got $head" }
if ($tail -ne 2) { throw "Expected TAIL=2. got $tail" }
if ($overflow -ne 2) { throw "Expected OVERFLOW=2. got $overflow" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_OVERFLOW_SHAPE_PROBE=pass'
Write-Output "COUNT=$count"
Write-Output "HEAD=$head"
Write-Output "TAIL=$tail"
Write-Output "OVERFLOW=$overflow"
