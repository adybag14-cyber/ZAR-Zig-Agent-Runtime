param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-fifo-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_NOTFOUND_PRESERVE_PROBE=skipped'

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
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE=skipped') {
    Write-Output $skipToken
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue FIFO probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_LAST_RESULT'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_MAILBOX_SEQ'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_PROBE_WAKE_QUEUE_COUNT'
if ($null -in @($ack,$lastOpcode,$lastResult,$mailboxSeq,$wakeQueueCount)) {
    throw 'Missing expected notfound-preserve fields in wake-queue FIFO probe output.'
}
if ($ack -ne 11 -or $mailboxSeq -ne 11) { throw "Expected final ack/seq at 11. got ack=$ack seq=$mailboxSeq" }
if ($lastOpcode -ne 54 -or $lastResult -ne -2) { throw "Expected final notfound receipt 54/-2. got $lastOpcode/$lastResult" }
if ($wakeQueueCount -ne 0) { throw "Expected queue to remain empty after rejected pop. got $wakeQueueCount" }

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_FIFO_NOTFOUND_PRESERVE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
