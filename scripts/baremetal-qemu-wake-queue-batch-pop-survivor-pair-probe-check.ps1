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
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_SURVIVOR_PAIR_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue-batch-pop probe failed with exit code $probeExitCode"
}

$afterBatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_BATCH_COUNT'
$afterBatchHead = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_BATCH_HEAD'
$afterBatchTail = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_BATCH_TAIL'
$afterBatchOverflow = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_BATCH_OVERFLOW'
$afterBatchFirstSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_BATCH_FIRST_SEQ'
$afterBatchSecondSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_AFTER_BATCH_SECOND_SEQ'

if ($null -in @($afterBatchCount, $afterBatchHead, $afterBatchTail, $afterBatchOverflow, $afterBatchFirstSeq, $afterBatchSecondSeq)) {
    throw 'Missing expected survivor-pair fields in wake-queue-batch-pop probe output.'
}
if ($afterBatchCount -ne 2) { throw "Expected AFTER_BATCH_COUNT=2. got $afterBatchCount" }
if ($afterBatchHead -ne 2 -or $afterBatchTail -ne 0) { throw "Expected AFTER_BATCH head/tail = 2/0. got $afterBatchHead/$afterBatchTail" }
if ($afterBatchOverflow -ne 2) { throw "Expected AFTER_BATCH_OVERFLOW=2. got $afterBatchOverflow" }
if ($afterBatchFirstSeq -ne 65 -or $afterBatchSecondSeq -ne 66) {
    throw "Expected survivor seqs 65/66. got $afterBatchFirstSeq/$afterBatchSecondSeq"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_BATCH_POP_SURVIVOR_PAIR_PROBE=pass'
Write-Output "AFTER_BATCH_COUNT=$afterBatchCount"
Write-Output "AFTER_BATCH_HEAD=$afterBatchHead"
Write-Output "AFTER_BATCH_TAIL=$afterBatchTail"
Write-Output "AFTER_BATCH_OVERFLOW=$afterBatchOverflow"
Write-Output "AFTER_BATCH_FIRST_SEQ=$afterBatchFirstSeq"
Write-Output "AFTER_BATCH_SECOND_SEQ=$afterBatchSecondSeq"
