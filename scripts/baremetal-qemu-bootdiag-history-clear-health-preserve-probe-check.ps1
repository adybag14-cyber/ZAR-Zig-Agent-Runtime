# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$output = & $probe @invoke 2>&1
$exitCode = $LASTEXITCODE
$outputText = ($output | Out-String)
if ($outputText -match '(?m)^BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PROBE=skipped\r?$') {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_HEALTH_PRESERVE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_HEALTH_PRESERVE_PROBE_SOURCE=baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
    exit 0
}
if ($exitCode -ne 0) {
    if ($outputText) { Write-Output $outputText.TrimEnd() }
    throw "Bootdiag/history-clear prerequisite probe failed with exit code $exitCode"
}

$ack3 = Extract-IntValue -Text $outputText -Name 'ACK3'
$lastOpcode3 = Extract-IntValue -Text $outputText -Name 'LAST_OPCODE3'
$lastResult3 = Extract-IntValue -Text $outputText -Name 'LAST_RESULT3'
$healthHistoryLen = Extract-IntValue -Text $outputText -Name 'HEALTH_HISTORY_LEN'
$healthHistoryHead = Extract-IntValue -Text $outputText -Name 'HEALTH_HISTORY_HEAD'
$healthHistoryOverflow = Extract-IntValue -Text $outputText -Name 'HEALTH_HISTORY_OVERFLOW'
$firstSeq = Extract-IntValue -Text $outputText -Name 'HEALTH_HISTORY_FIRST_SEQ'
$firstCode = Extract-IntValue -Text $outputText -Name 'HEALTH_HISTORY_FIRST_CODE'
$firstMode = Extract-IntValue -Text $outputText -Name 'HEALTH_HISTORY_FIRST_MODE'
$firstTick = Extract-IntValue -Text $outputText -Name 'HEALTH_HISTORY_FIRST_TICK'
$firstAck = Extract-IntValue -Text $outputText -Name 'HEALTH_HISTORY_FIRST_ACK'
$cmdHistoryLen3 = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_LEN3'
$secondSeq = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_SECOND_SEQ'
$secondOpcode = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_SECOND_OPCODE'
$secondResult = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_SECOND_RESULT'
$secondArg0 = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_SECOND_ARG0'

if ($ack3 -ne 6 -or $lastOpcode3 -ne 20 -or $lastResult3 -ne 0 -or $healthHistoryLen -ne 1 -or $healthHistoryHead -ne 1 -or $healthHistoryOverflow -ne 0 -or $firstSeq -ne 1 -or $firstCode -ne 200 -or $firstMode -ne 1 -or $firstTick -ne 6 -or $firstAck -ne 6 -or $cmdHistoryLen3 -ne 2 -or $secondSeq -ne 6 -or $secondOpcode -ne 20 -or $secondResult -ne 0 -or $secondArg0 -ne 0) {
    throw "Unexpected health-preserve state. ack3=$ack3 lastOpcode3=$lastOpcode3 lastResult3=$lastResult3 healthHistoryLen=$healthHistoryLen healthHistoryHead=$healthHistoryHead healthHistoryOverflow=$healthHistoryOverflow firstSeq=$firstSeq firstCode=$firstCode firstMode=$firstMode firstTick=$firstTick firstAck=$firstAck cmdHistoryLen3=$cmdHistoryLen3 secondSeq=$secondSeq secondOpcode=$secondOpcode secondResult=$secondResult secondArg0=$secondArg0"
}

Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_HEALTH_PRESERVE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_HEALTH_PRESERVE_PROBE_SOURCE=baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
Write-Output "ACK3=$ack3"
Write-Output "LAST_OPCODE3=$lastOpcode3"
Write-Output "LAST_RESULT3=$lastResult3"
Write-Output "HEALTH_HISTORY_LEN=$healthHistoryLen"
Write-Output "HEALTH_HISTORY_HEAD=$healthHistoryHead"
Write-Output "HEALTH_HISTORY_OVERFLOW=$healthHistoryOverflow"
Write-Output "HEALTH_HISTORY_FIRST_SEQ=$firstSeq"
Write-Output "HEALTH_HISTORY_FIRST_CODE=$firstCode"
Write-Output "HEALTH_HISTORY_FIRST_MODE=$firstMode"
Write-Output "HEALTH_HISTORY_FIRST_TICK=$firstTick"
Write-Output "HEALTH_HISTORY_FIRST_ACK=$firstAck"
Write-Output "CMD_HISTORY_LEN3=$cmdHistoryLen3"
Write-Output "CMD_HISTORY_SECOND_SEQ=$secondSeq"
Write-Output "CMD_HISTORY_SECOND_OPCODE=$secondOpcode"
Write-Output "CMD_HISTORY_SECOND_RESULT=$secondResult"
Write-Output "CMD_HISTORY_SECOND_ARG0=$secondArg0"
