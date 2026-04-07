# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-probe-check.ps1' `
    -FailureLabel 'scheduler'
$probeText = $probeState.Text

$hitStart = Extract-BoolValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_HIT_START'
$hitAfter = Extract-BoolValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_HIT_AFTER_SCHEDULER'
$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_TICKS'

if ($null -in @($hitStart, $hitAfter, $ack, $lastOpcode, $lastResult, $ticks)) {
    throw 'Missing expected baseline scheduler fields in probe output.'
}
if (-not $hitStart) { throw 'Expected scheduler probe to hit _start.' }
if (-not $hitAfter) { throw 'Expected scheduler probe to reach post-scheduler stage.' }
if ($ack -ne 5) { throw "Expected ACK=5. got $ack" }
if ($lastOpcode -ne 24) { throw "Expected LAST_OPCODE=24. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($ticks -lt 1) { throw "Expected TICKS>=1. got $ticks" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_BASELINE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "TICKS=$ticks"
