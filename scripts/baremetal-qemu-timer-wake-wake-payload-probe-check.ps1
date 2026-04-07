# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-wake-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TIMER_WAKE_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_WAKE_WAKE_PAYLOAD_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TIMER_WAKE_WAKE_PAYLOAD_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-timer-wake-probe-check.ps1' `
    -FailureLabel 'timer-wake'
$probeText = $probeState.Text

$wake0Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_WAKE0_SEQ'
$wake0TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_WAKE0_TASK_ID'
$wake0TimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_WAKE0_TIMER_ID'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_WAKE0_REASON'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_WAKE0_VECTOR'
$wake0Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_WAKE0_TICK'
$timer0LastFireTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_WAKE_PROBE_TIMER0_LAST_FIRE_TICK'

if ($null -in @($wake0Seq, $wake0TaskId, $wake0TimerId, $wake0Reason, $wake0Vector, $wake0Tick, $timer0LastFireTick)) {
    throw 'Missing expected wake payload fields in timer-wake probe output.'
}
if ($wake0Seq -ne 1) { throw "Expected WAKE0_SEQ=1. got $wake0Seq" }
if ($wake0TaskId -ne 1) { throw "Expected WAKE0_TASK_ID=1. got $wake0TaskId" }
if ($wake0TimerId -ne 1) { throw "Expected WAKE0_TIMER_ID=1. got $wake0TimerId" }
if ($wake0Reason -ne 1) { throw "Expected WAKE0_REASON=1. got $wake0Reason" }
if ($wake0Vector -ne 0) { throw "Expected WAKE0_VECTOR=0. got $wake0Vector" }
if ($wake0Tick -ne $timer0LastFireTick) { throw "Expected WAKE0_TICK to equal TIMER0_LAST_FIRE_TICK. got $wake0Tick vs $timer0LastFireTick" }

Write-Output 'BAREMETAL_QEMU_TIMER_WAKE_WAKE_PAYLOAD_PROBE=pass'
Write-Output "WAKE0_SEQ=$wake0Seq"
Write-Output "WAKE0_TASK_ID=$wake0TaskId"
Write-Output "WAKE0_TIMER_ID=$wake0TimerId"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
Write-Output "WAKE0_TICK=$wake0Tick"
