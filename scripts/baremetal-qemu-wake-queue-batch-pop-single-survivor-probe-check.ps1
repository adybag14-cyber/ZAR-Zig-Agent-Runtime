param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-batch-pop-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_SINGLE_SURVIVOR_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-batch-pop probe failed with exit code $probeExitCode"
}

$afterSingleCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_SINGLE_COUNT'
$afterSingleTail = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_SINGLE_TAIL'
$afterSingleSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_SINGLE_SEQ'

if ($null -in @($afterSingleCount, $afterSingleTail, $afterSingleSeq)) {
    throw 'Missing expected single-survivor fields in wake-queue-batch-pop probe output.'
}
if ($afterSingleCount -ne 1) { throw "Expected AFTER_SINGLE_COUNT=1. got $afterSingleCount" }
if ($afterSingleTail -ne 1) { throw "Expected AFTER_SINGLE_TAIL=1. got $afterSingleTail" }
if ($afterSingleSeq -ne 66) { throw "Expected AFTER_SINGLE_SEQ=66. got $afterSingleSeq" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_SINGLE_SURVIVOR_PROBE=pass'
Write-Output "AFTER_SINGLE_COUNT=$afterSingleCount"
Write-Output "AFTER_SINGLE_TAIL=$afterSingleTail"
Write-Output "AFTER_SINGLE_SEQ=$afterSingleSeq"
