# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_TELEMETRY_PRESERVE_PROBE_CHECK=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying periodic-timer probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_LAST_RESULT'
$mailboxOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_MAILBOX_OPCODE'
$mailboxSeq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_MAILBOX_SEQ'
$pendingWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_PENDING_WAKE_COUNT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER_DISPATCH_COUNT'
$taskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TASK0_STATE'
$runCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TASK0_RUN_COUNT'
$budgetRemaining = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TASK0_BUDGET_REMAINING'
if ($null -in @($ack, $lastOpcode, $lastResult, $mailboxOpcode, $mailboxSeq, $pendingWakeCount, $dispatchCount, $taskState, $runCount, $budgetRemaining)) { throw 'Missing periodic-timer telemetry fields.' }
if ($ack -ne 9) { throw "Expected ACK=9. got $ack" }
if ($lastOpcode -ne 46) { throw "Expected LAST_OPCODE=46. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($mailboxOpcode -ne 46) { throw "Expected MAILBOX_OPCODE=46. got $mailboxOpcode" }
if ($mailboxSeq -ne 9) { throw "Expected MAILBOX_SEQ=9. got $mailboxSeq" }
if ($pendingWakeCount -ne 2) { throw "Expected PENDING_WAKE_COUNT=2. got $pendingWakeCount" }
if ($dispatchCount -ne 2) { throw "Expected TIMER_DISPATCH_COUNT=2. got $dispatchCount" }
if ($taskState -ne 1) { throw "Expected TASK0_STATE=1. got $taskState" }
if ($runCount -ne 0) { throw "Expected TASK0_RUN_COUNT=0. got $runCount" }
if ($budgetRemaining -ne 8) { throw "Expected TASK0_BUDGET_REMAINING=8. got $budgetRemaining" }
Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_TELEMETRY_PRESERVE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "MAILBOX_OPCODE=$mailboxOpcode"
Write-Output "MAILBOX_SEQ=$mailboxSeq"
Write-Output "PENDING_WAKE_COUNT=$pendingWakeCount"
Write-Output "TIMER_DISPATCH_COUNT=$dispatchCount"
Write-Output "TASK0_STATE=$taskState"
Write-Output "TASK0_RUN_COUNT=$runCount"
Write-Output "TASK0_BUDGET_REMAINING=$budgetRemaining"
