# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-clamp-probe-check.ps1"
$wakeReasonTimer = 1
$expectedAck = 7
$expectedOpcode = 49
$taskStateReady = 1

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [decimal]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_TELEMETRY_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying periodic-timer-clamp probe failed with exit code $probeExitCode"
}

$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$wakeCount = Extract-IntValue -Text $probeText -Name 'WAKE_COUNT'
$wake0Seq = Extract-IntValue -Text $probeText -Name 'WAKE0_SEQ'
$wake0TaskId = Extract-IntValue -Text $probeText -Name 'WAKE0_TASK_ID'
$wake0TimerId = Extract-IntValue -Text $probeText -Name 'WAKE0_TIMER_ID'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'WAKE0_REASON'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'WAKE0_VECTOR'
$holdTaskState = Extract-IntValue -Text $probeText -Name 'HOLD_TASK_STATE'

if ($null -in @($ack, $lastOpcode, $lastResult, $wakeCount, $wake0Seq, $wake0TaskId, $wake0TimerId, $wake0Reason, $wake0Vector, $holdTaskState)) {
    throw 'Missing expected telemetry fields in periodic-timer-clamp probe output.'
}
if ($ack -ne $expectedAck) { throw "Expected ACK=$expectedAck. got $ack" }
if ($lastOpcode -ne $expectedOpcode -or $lastResult -ne 0) { throw "Expected final receipt $expectedOpcode/0. got $lastOpcode/$lastResult" }
if ($wakeCount -ne 1) { throw "Expected WAKE_COUNT=1. got $wakeCount" }
if ($wake0Seq -ne 1) { throw "Expected WAKE0_SEQ=1. got $wake0Seq" }
if ($wake0TaskId -ne 1 -or $wake0TimerId -ne 1) { throw "Expected WAKE0_TASK_ID/WAKE0_TIMER_ID=1/1. got $wake0TaskId/$wake0TimerId" }
if ($wake0Reason -ne $wakeReasonTimer) { throw "Expected WAKE0_REASON=$wakeReasonTimer. got $wake0Reason" }
if ($wake0Vector -ne 0) { throw "Expected WAKE0_VECTOR=0. got $wake0Vector" }
if ($holdTaskState -ne $taskStateReady) { throw "Expected HOLD_TASK_STATE=$taskStateReady. got $holdTaskState" }

Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_TELEMETRY_PRESERVE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "WAKE_COUNT=$wakeCount"
Write-Output "WAKE0_SEQ=$wake0Seq"
Write-Output "WAKE0_TASK_ID=$wake0TaskId"
Write-Output "WAKE0_TIMER_ID=$wake0TimerId"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
Write-Output "HOLD_TASK_STATE=$holdTaskState"
