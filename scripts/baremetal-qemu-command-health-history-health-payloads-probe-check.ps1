# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-command-health-history-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_HEALTH_PAYLOADS_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying command-health history probe failed with exit code $probeExitCode"
}

$firstSeq = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_FIRST_SEQ'
$firstCode = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_FIRST_CODE'
$firstAck = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_FIRST_ACK'
$prevLastSeq = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_PREV_LAST_SEQ'
$prevLastCode = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_PREV_LAST_CODE'
$prevLastAck = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_PREV_LAST_ACK'
$lastSeq = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_LAST_SEQ'
$lastCode = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_LAST_CODE'
$lastAck = Extract-IntValue -Text $probeText -Name 'HEALTH_HISTORY_LAST_ACK'

if ($null -in @($firstSeq, $firstCode, $firstAck, $prevLastSeq, $prevLastCode, $prevLastAck, $lastSeq, $lastCode, $lastAck)) {
    throw 'Missing health-history payload fields.'
}
if ($firstSeq -ne 8) { throw "Expected HEALTH_HISTORY_FIRST_SEQ=8. got $firstSeq" }
if ($firstCode -ne 103) { throw "Expected HEALTH_HISTORY_FIRST_CODE=103. got $firstCode" }
if ($firstAck -ne 3) { throw "Expected HEALTH_HISTORY_FIRST_ACK=3. got $firstAck" }
if ($prevLastSeq -ne 70) { throw "Expected HEALTH_HISTORY_PREV_LAST_SEQ=70. got $prevLastSeq" }
if ($prevLastCode -ne 134) { throw "Expected HEALTH_HISTORY_PREV_LAST_CODE=134. got $prevLastCode" }
if ($prevLastAck -ne 34) { throw "Expected HEALTH_HISTORY_PREV_LAST_ACK=34. got $prevLastAck" }
if ($lastSeq -ne 71) { throw "Expected HEALTH_HISTORY_LAST_SEQ=71. got $lastSeq" }
if ($lastCode -ne 200) { throw "Expected HEALTH_HISTORY_LAST_CODE=200. got $lastCode" }
if ($lastAck -ne 35) { throw "Expected HEALTH_HISTORY_LAST_ACK=35. got $lastAck" }

Write-Output 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_HEALTH_PAYLOADS_PROBE=pass'
Write-Output "HEALTH_HISTORY_FIRST_SEQ=$firstSeq"
Write-Output "HEALTH_HISTORY_FIRST_CODE=$firstCode"
Write-Output "HEALTH_HISTORY_FIRST_ACK=$firstAck"
Write-Output "HEALTH_HISTORY_PREV_LAST_SEQ=$prevLastSeq"
Write-Output "HEALTH_HISTORY_PREV_LAST_CODE=$prevLastCode"
Write-Output "HEALTH_HISTORY_PREV_LAST_ACK=$prevLastAck"
Write-Output "HEALTH_HISTORY_LAST_SEQ=$lastSeq"
Write-Output "HEALTH_HISTORY_LAST_CODE=$lastCode"
Write-Output "HEALTH_HISTORY_LAST_ACK=$lastAck"
