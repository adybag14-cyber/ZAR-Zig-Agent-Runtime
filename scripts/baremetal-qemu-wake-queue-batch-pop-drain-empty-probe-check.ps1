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
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_DRAIN_EMPTY_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-batch-pop probe failed with exit code $probeExitCode"
}

$afterDrainCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_DRAIN_COUNT'
$afterDrainHead = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_DRAIN_HEAD'
$afterDrainTail = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_DRAIN_TAIL'
$afterDrainOverflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_DRAIN_OVERFLOW'

if ($null -in @($afterDrainCount, $afterDrainHead, $afterDrainTail, $afterDrainOverflow)) {
    throw 'Missing expected drain-empty fields in wake-queue-batch-pop probe output.'
}
if ($afterDrainCount -ne 0) { throw "Expected AFTER_DRAIN_COUNT=0. got $afterDrainCount" }
if ($afterDrainHead -ne 2 -or $afterDrainTail -ne 2) { throw "Expected AFTER_DRAIN head/tail = 2/2. got $afterDrainHead/$afterDrainTail" }
if ($afterDrainOverflow -ne 2) { throw "Expected AFTER_DRAIN_OVERFLOW=2. got $afterDrainOverflow" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_DRAIN_EMPTY_PROBE=pass'
Write-Output "AFTER_DRAIN_COUNT=$afterDrainCount"
Write-Output "AFTER_DRAIN_HEAD=$afterDrainHead"
Write-Output "AFTER_DRAIN_TAIL=$afterDrainTail"
Write-Output "AFTER_DRAIN_OVERFLOW=$afterDrainOverflow"
