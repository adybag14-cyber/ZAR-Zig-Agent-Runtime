# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-command-health-history-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe -ProbePath $probe -SkipBuild:$SkipBuild -SkippedPattern '(?m)^BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_PROBE=skipped\r?$' -SkippedReceipt 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_BASELINE_PROBE' -SkippedSourceReceipt 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_BASELINE_PROBE_SOURCE' -SkippedSourceValue 'baremetal-qemu-command-health-history-probe-check.ps1' -FailureLabel 'command-health history'
$probeText = $probeState.Text
ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'

if ($null -in @($ack, $lastOpcode, $lastResult, $ticks)) {
    throw 'Missing baseline command-health history fields.'
}
if ($ack -ne 35) { throw "Expected ACK=35. got $ack" }
if ($lastOpcode -ne 1) { throw "Expected LAST_OPCODE=1. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($ticks -lt 36) { throw "Expected TICKS>=36. got $ticks" }

Write-Output 'BAREMETAL_QEMU_COMMAND_HEALTH_HISTORY_BASELINE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TICKS=$ticks"
