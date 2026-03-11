param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-cancel-task-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_SECOND_CANCEL_NOTFOUND_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-cancel-task probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_LAST_RESULT'
$mailboxOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_MAILBOX_OPCODE'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_MAILBOX_SEQ'

if ($null -in @($ack, $lastOpcode, $lastResult, $mailboxOpcode, $mailboxSeq)) {
    throw 'Missing second-cancel timer-cancel-task fields.'
}
if ($ack -ne 9) { throw "Expected ACK=9. got $ack" }
if ($lastOpcode -ne 52) { throw "Expected LAST_OPCODE=52. got $lastOpcode" }
if ($lastResult -ne -2) { throw "Expected LAST_RESULT=-2. got $lastResult" }
if ($mailboxOpcode -ne 52) { throw "Expected MAILBOX_OPCODE=52. got $mailboxOpcode" }
if ($mailboxSeq -ne 9) { throw "Expected MAILBOX_SEQ=9. got $mailboxSeq" }

Write-Output 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_SECOND_CANCEL_NOTFOUND_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "MAILBOX_OPCODE=$mailboxOpcode"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
