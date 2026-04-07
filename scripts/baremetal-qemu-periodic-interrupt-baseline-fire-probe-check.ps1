# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-interrupt-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe -ProbePath $probe -SkipBuild:$SkipBuild -SkippedPattern '(?m)^BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE=skipped\r?$' -SkippedReceipt 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_BASELINE_FIRE_PROBE' -SkippedSourceReceipt 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_BASELINE_FIRE_PROBE_SOURCE' -SkippedSourceValue 'baremetal-qemu-periodic-interrupt-probe-check.ps1' -FailureLabel 'periodic-interrupt' -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text
$firstFireCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_FIRST_FIRE_COUNT'
$firstWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_FIRST_WAKE_COUNT'
$firstLastFireTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_FIRST_LAST_FIRE_TICK'
$wake0Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE0_SEQ'
$wake0TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE0_TASK_ID'
$wake0TimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE0_TIMER_ID'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE0_REASON'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE0_VECTOR'
$wake0Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE0_TICK'
$wake1Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE1_TICK'

if ($null -in @($firstFireCount, $firstWakeCount, $firstLastFireTick, $wake0Seq, $wake0TaskId, $wake0TimerId, $wake0Reason, $wake0Vector, $wake0Tick, $wake1Tick)) {
    throw 'Missing expected periodic-interrupt baseline-fire fields in probe output.'
}
if ($firstFireCount -ne 1) { throw "Expected FIRST_FIRE_COUNT=1, got $firstFireCount" }
if ($firstWakeCount -ne 1) { throw "Expected FIRST_WAKE_COUNT=1, got $firstWakeCount" }
if ($wake0Seq -ne 1) { throw "Expected WAKE0_SEQ=1, got $wake0Seq" }
if ($wake0TaskId -ne 1) { throw "Expected WAKE0_TASK_ID=1, got $wake0TaskId" }
if ($wake0TimerId -ne 1) { throw "Expected WAKE0_TIMER_ID=1, got $wake0TimerId" }
if ($wake0Reason -ne $wakeReasonTimer) { throw "Expected WAKE0_REASON=1, got $wake0Reason" }
if ($wake0Vector -ne 0) { throw "Expected WAKE0_VECTOR=0, got $wake0Vector" }
if ($firstLastFireTick -ne $wake0Tick) { throw "Expected FIRST_LAST_FIRE_TICK=$wake0Tick, got $firstLastFireTick" }
if ($wake0Tick -ge $wake1Tick) { throw "Expected WAKE0_TICK < WAKE1_TICK. got wake0=$wake0Tick wake1=$wake1Tick" }

Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_BASELINE_FIRE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_BASELINE_FIRE_PROBE_SOURCE=baremetal-qemu-periodic-interrupt-probe-check.ps1'
Write-Output "FIRST_FIRE_COUNT=$firstFireCount"
Write-Output "FIRST_WAKE_COUNT=$firstWakeCount"
Write-Output "FIRST_LAST_FIRE_TICK=$firstLastFireTick"
Write-Output "WAKE0_SEQ=$wake0Seq"
Write-Output "WAKE0_TASK_ID=$wake0TaskId"
Write-Output "WAKE0_TIMER_ID=$wake0TimerId"
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
Write-Output "WAKE0_TICK=$wake0Tick"
Write-Output "WAKE1_TICK=$wake1Tick"
