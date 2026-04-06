# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_PERIODIC_TIMER_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_PERIODIC_TIMER_RESUMED_CADENCE_PROBE_CHECK' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_PERIODIC_TIMER_RESUMED_CADENCE_PROBE_CHECK_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-periodic-timer-probe-check.ps1' `
    -FailureLabel 'periodic-timer'
$probeText = $probeState.Text

$timerFireCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER0_FIRE_COUNT'
$timerLastFireTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER0_LAST_FIRE_TICK'
$timerNextFireTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER0_NEXT_FIRE_TICK'
$timerLastWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER_LAST_WAKE_TICK'
$periodTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_TIMER0_PERIOD_TICKS'
$wake1Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE1_SEQ'
$wake1TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE1_TASK_ID'
$wake1TimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE1_TIMER_ID'
$wake1Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE1_REASON'
$wake1Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE1_VECTOR'
$wake1Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_WAKE1_TICK'
if ($null -in @($timerFireCount, $timerLastFireTick, $timerNextFireTick, $timerLastWakeTick, $periodTicks, $wake1Seq, $wake1TaskId, $wake1TimerId, $wake1Reason, $wake1Vector, $wake1Tick)) { throw 'Missing periodic-timer resumed-cadence fields.' }
if ($timerFireCount -ne 2) { throw "Expected TIMER0_FIRE_COUNT=2. got $timerFireCount" }
if ($timerLastFireTick -ne 14) { throw "Expected TIMER0_LAST_FIRE_TICK=14. got $timerLastFireTick" }
if ($timerNextFireTick -ne ($timerLastFireTick + $periodTicks)) { throw "Expected TIMER0_NEXT_FIRE_TICK=$($timerLastFireTick + $periodTicks). got $timerNextFireTick" }
if ($timerLastWakeTick -ne $timerLastFireTick) { throw "Expected TIMER_LAST_WAKE_TICK=$timerLastFireTick. got $timerLastWakeTick" }
if ($wake1Seq -ne 2) { throw "Expected WAKE1_SEQ=2. got $wake1Seq" }
if ($wake1TaskId -ne 1) { throw "Expected WAKE1_TASK_ID=1. got $wake1TaskId" }
if ($wake1TimerId -ne 1) { throw "Expected WAKE1_TIMER_ID=1. got $wake1TimerId" }
if ($wake1Reason -ne 1) { throw "Expected WAKE1_REASON=1. got $wake1Reason" }
if ($wake1Vector -ne 0) { throw "Expected WAKE1_VECTOR=0. got $wake1Vector" }
if ($wake1Tick -ne $timerLastFireTick) { throw "Expected WAKE1_TICK=$timerLastFireTick. got $wake1Tick" }
Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_RESUMED_CADENCE_PROBE=pass'
Write-Output "TIMER0_FIRE_COUNT=$timerFireCount"
Write-Output "TIMER0_LAST_FIRE_TICK=$timerLastFireTick"
Write-Output "TIMER0_NEXT_FIRE_TICK=$timerNextFireTick"
Write-Output "TIMER_LAST_WAKE_TICK=$timerLastWakeTick"
Write-Output "TIMER0_PERIOD_TICKS=$periodTicks"
Write-Output "WAKE1_SEQ=$wake1Seq"
Write-Output "WAKE1_TASK_ID=$wake1TaskId"
Write-Output "WAKE1_TIMER_ID=$wake1TimerId"
Write-Output "WAKE1_REASON=$wake1Reason"
Write-Output "WAKE1_VECTOR=$wake1Vector"
Write-Output "WAKE1_TICK=$wake1Tick"
