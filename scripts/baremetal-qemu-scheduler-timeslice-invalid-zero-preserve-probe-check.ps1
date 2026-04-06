# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-timeslice-update-probe-check.ps1"
$schedulerSetTimesliceOpcode = 29
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_TIMESLICE_UPDATE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_INVALID_ZERO_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_INVALID_ZERO_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-timeslice-update-probe-check.ps1' `
    -FailureLabel 'scheduler-timeslice-update'
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$timeslice = Extract-IntValue -Text $probeText -Name 'TIMESLICE'

if ($null -in @($ack, $lastOpcode, $lastResult, $timeslice)) {
    throw 'Missing expected invalid-zero preservation fields in scheduler-timeslice-update probe output.'
}
if ($ack -ne 6) { throw "Expected ACK=6. got $ack" }
if ($lastOpcode -ne $schedulerSetTimesliceOpcode) { throw "Expected LAST_OPCODE=29. got $lastOpcode" }
if ($lastResult -ne -22) { throw "Expected LAST_RESULT=-22. got $lastResult" }
if ($timeslice -ne 2) { throw "Expected TIMESLICE=2 after invalid zero. got $timeslice" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_TIMESLICE_INVALID_ZERO_PRESERVE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TIMESLICE=$timeslice"