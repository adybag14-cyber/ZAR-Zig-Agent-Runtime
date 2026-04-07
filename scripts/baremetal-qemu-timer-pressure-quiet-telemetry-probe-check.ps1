# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-pressure-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TIMER_PRESSURE_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_PRESSURE_QUIET_TELEMETRY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TIMER_PRESSURE_QUIET_TELEMETRY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-timer-pressure-probe-check.ps1' `
    -FailureLabel 'timer-pressure'
$probeText = $probeState.Text


$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$wakeCount = Extract-IntValue -Text $probeText -Name 'WAKE_COUNT'
$dispatchCount = Extract-IntValue -Text $probeText -Name 'DISPATCH_COUNT'
if ($null -in @($ack,$lastOpcode,$lastResult,$wakeCount,$dispatchCount)) {
    throw 'Missing timer-pressure quiet-telemetry fields.'
}
if ($ack -ne 38) { throw "Expected ACK=38. got $ack" }
if ($lastOpcode -ne 42) { throw "Expected LAST_OPCODE=42. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($wakeCount -ne 0) { throw "Expected WAKE_COUNT=0. got $wakeCount" }
if ($dispatchCount -ne 0) { throw "Expected DISPATCH_COUNT=0. got $dispatchCount" }

Write-Output 'BAREMETAL_QEMU_TIMER_PRESSURE_QUIET_TELEMETRY_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "WAKE_COUNT=$wakeCount"
Write-Output "DISPATCH_COUNT=$dispatchCount"
