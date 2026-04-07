# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-health-history-overflow-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-health-history-overflow-clear-probe-check.ps1' `
    -FailureLabel 'Health-history overflow/clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$firstCode = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_FIRST_CODE'
$firstAck = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_FIRST_ACK'
$prevLastSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_PREV_LAST_SEQ'
$prevLastCode = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_PREV_LAST_CODE'
$prevLastAck = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_PREV_LAST_ACK'
$lastCode = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_LAST_CODE'
$lastAck = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_LAST_ACK'
if ($firstCode -ne 103 -or $firstAck -ne 3 -or $prevLastSeq -ne 70 -or $prevLastCode -ne 134 -or $prevLastAck -ne 34 -or $lastCode -ne 200 -or $lastAck -ne 35) {
    throw "Unexpected overflow payloads. firstCode=$firstCode firstAck=$firstAck prevLastSeq=$prevLastSeq prevLastCode=$prevLastCode prevLastAck=$prevLastAck lastCode=$lastCode lastAck=$lastAck"
}

Write-Output 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE_SOURCE=baremetal-qemu-health-history-overflow-clear-probe-check.ps1'
Write-Output "FIRST_CODE=$firstCode"
Write-Output "FIRST_ACK=$firstAck"
Write-Output "PREV_LAST_SEQ=$prevLastSeq"
Write-Output "PREV_LAST_CODE=$prevLastCode"
Write-Output "PREV_LAST_ACK=$prevLastAck"
Write-Output "LAST_CODE=$lastCode"
Write-Output "LAST_ACK=$lastAck"
