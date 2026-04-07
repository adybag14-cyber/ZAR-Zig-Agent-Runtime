# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-interrupt-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe -ProbePath $probe -SkipBuild:$SkipBuild -SkippedPattern '(?m)^BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE=skipped\r?$' -SkippedReceipt 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PERIODIC_CADENCE_PROBE' -SkippedSourceReceipt 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PERIODIC_CADENCE_PROBE_SOURCE' -SkippedSourceValue 'baremetal-qemu-periodic-interrupt-probe-check.ps1' -FailureLabel 'periodic-interrupt' -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text
$secondFireCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_SECOND_FIRE_COUNT'
$secondDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_SECOND_DISPATCH_COUNT'
$secondWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_SECOND_WAKE_COUNT'
$secondLastFireTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_SECOND_LAST_FIRE_TICK'
$secondNextFireTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_SECOND_NEXT_FIRE_TICK'
$timer0FireCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_TIMER0_FIRE_COUNT'
$timer0LastFireTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_TIMER0_LAST_FIRE_TICK'
$wake1Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE1_TICK'
$wake2TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE2_TASK_ID'
$wake2TimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE2_TIMER_ID'
$wake2Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE2_REASON'
$wake2Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE2_VECTOR'
$wake2Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PROBE_WAKE2_TICK'

if ($null -in @($secondFireCount, $secondDispatchCount, $secondWakeCount, $secondLastFireTick, $secondNextFireTick, $timer0FireCount, $timer0LastFireTick, $wake1Tick, $wake2TaskId, $wake2TimerId, $wake2Reason, $wake2Vector, $wake2Tick)) {
    throw 'Missing expected periodic-interrupt cadence fields in probe output.'
}
if ($secondFireCount -ne 2) { throw "Expected SECOND_FIRE_COUNT=2, got $secondFireCount" }
if ($secondDispatchCount -ne 2) { throw "Expected SECOND_DISPATCH_COUNT=2, got $secondDispatchCount" }
if ($secondWakeCount -ne 3) { throw "Expected SECOND_WAKE_COUNT=3, got $secondWakeCount" }
if ($timer0FireCount -ne 2) { throw "Expected TIMER0_FIRE_COUNT=2, got $timer0FireCount" }
if ($wake2TaskId -ne 1) { throw "Expected WAKE2_TASK_ID=1, got $wake2TaskId" }
if ($wake2TimerId -ne 1) { throw "Expected WAKE2_TIMER_ID=1, got $wake2TimerId" }
if ($wake2Reason -ne $wakeReasonTimer) { throw "Expected WAKE2_REASON=1, got $wake2Reason" }
if ($wake2Vector -ne 0) { throw "Expected WAKE2_VECTOR=0, got $wake2Vector" }
if ($secondLastFireTick -ne $wake2Tick) { throw "Expected SECOND_LAST_FIRE_TICK=$wake2Tick, got $secondLastFireTick" }
if ($timer0LastFireTick -ne $wake2Tick) { throw "Expected TIMER0_LAST_FIRE_TICK=$wake2Tick, got $timer0LastFireTick" }
if ($wake2Tick -le $wake1Tick) { throw "Expected WAKE2_TICK > WAKE1_TICK. got wake1=$wake1Tick wake2=$wake2Tick" }
if ($secondNextFireTick -le $secondLastFireTick) { throw "Expected SECOND_NEXT_FIRE_TICK > SECOND_LAST_FIRE_TICK. next=$secondNextFireTick last=$secondLastFireTick" }

Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PERIODIC_CADENCE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_PERIODIC_INTERRUPT_PERIODIC_CADENCE_PROBE_SOURCE=baremetal-qemu-periodic-interrupt-probe-check.ps1'
Write-Output "SECOND_FIRE_COUNT=$secondFireCount"
Write-Output "SECOND_DISPATCH_COUNT=$secondDispatchCount"
Write-Output "SECOND_WAKE_COUNT=$secondWakeCount"
Write-Output "SECOND_LAST_FIRE_TICK=$secondLastFireTick"
Write-Output "SECOND_NEXT_FIRE_TICK=$secondNextFireTick"
Write-Output "TIMER0_FIRE_COUNT=$timer0FireCount"
Write-Output "TIMER0_LAST_FIRE_TICK=$timer0LastFireTick"
Write-Output "WAKE1_TICK=$wake1Tick"
Write-Output "WAKE2_TASK_ID=$wake2TaskId"
Write-Output "WAKE2_TIMER_ID=$wake2TimerId"
Write-Output "WAKE2_REASON=$wake2Reason"
Write-Output "WAKE2_VECTOR=$wake2Vector"
Write-Output "WAKE2_TICK=$wake2Tick"
