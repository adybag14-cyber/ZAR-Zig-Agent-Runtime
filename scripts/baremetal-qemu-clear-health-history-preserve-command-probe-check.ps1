# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-bootdiag-history-clear-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^\{0}=(-?\d+)$' -f $Name
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_CLEAR_HEALTH_HISTORY_PRESERVE_COMMAND_PROBE' `
    -FailureLabel 'bootdiag/history-clear' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text
$ack3 = Extract-IntValue -Text $probeText -Name "ACK3"
$healthHistoryLen = Extract-IntValue -Text $probeText -Name "HEALTH_HISTORY_LEN"
$cmdHistoryLen3 = Extract-IntValue -Text $probeText -Name "CMD_HISTORY_LEN3"
$healthHistoryFirstCode = Extract-IntValue -Text $probeText -Name "HEALTH_HISTORY_FIRST_CODE"

if ($null -eq $ack3 -or
    $null -eq $healthHistoryLen -or
    $null -eq $cmdHistoryLen3 -or
    $null -eq $healthHistoryFirstCode) {
    throw "Missing expected clear-health-history preservation fields in probe output."
}
if ($ack3 -ne 6) {
    throw "Expected ACK3=6 after command_clear_health_history. got $ack3"
}
if ($healthHistoryLen -ne 1) {
    throw "Expected health history to collapse to a single reset receipt. got len=$healthHistoryLen"
}
if ($cmdHistoryLen3 -ne 2) {
    throw "Expected command history to remain intact after command_clear_health_history. got len=$cmdHistoryLen3"
}
if ($healthHistoryFirstCode -ne 200) {
    throw "Expected health history to restart with code 200. got $healthHistoryFirstCode"
}

Write-Output "BAREMETAL_QEMU_CLEAR_HEALTH_HISTORY_PRESERVE_COMMAND_PROBE=pass"
Write-Output "ACK3=$ack3"
Write-Output "HEALTH_HISTORY_LEN=$healthHistoryLen"
Write-Output "CMD_HISTORY_LEN3=$cmdHistoryLen3"
Write-Output "HEALTH_HISTORY_FIRST_CODE=$healthHistoryFirstCode"
