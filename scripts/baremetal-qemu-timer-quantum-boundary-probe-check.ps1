# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-quantum-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TIMER_QUANTUM_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_QUANTUM_BOUNDARY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TIMER_QUANTUM_BOUNDARY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-timer-quantum-probe-check.ps1' `
    -FailureLabel 'timer-quantum'
$probeText = $probeState.Text

$armedTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_QUANTUM_PROBE_ARMED_TICKS'
$armedNextFireTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_QUANTUM_PROBE_ARMED_NEXT_FIRE_TICK'
$timerQuantum = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_QUANTUM_PROBE_TIMER_QUANTUM'
$expectedBoundaryTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_QUANTUM_PROBE_EXPECTED_BOUNDARY_TICK'
$preBoundaryTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_QUANTUM_PROBE_PRE_BOUNDARY_TICK'
$postWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_QUANTUM_PROBE_POST_WAKE_TICK'

if ($null -in @($armedTicks, $armedNextFireTick, $timerQuantum, $expectedBoundaryTick, $preBoundaryTick, $postWakeTick)) {
    throw 'Missing expected boundary fields in timer-quantum probe output.'
}
$recomputedBoundary = (([int64]([math]::Floor($armedTicks / $timerQuantum))) + 1) * $timerQuantum
if ($expectedBoundaryTick -ne $recomputedBoundary) { throw "Expected recomputed boundary $recomputedBoundary. got $expectedBoundaryTick" }
if ($expectedBoundaryTick -le $armedNextFireTick) { throw "Expected EXPECTED_BOUNDARY_TICK > ARMED_NEXT_FIRE_TICK. got $expectedBoundaryTick <= $armedNextFireTick" }
if ($preBoundaryTick -ne ($expectedBoundaryTick - 1)) { throw "Expected PRE_BOUNDARY_TICK=$(($expectedBoundaryTick - 1)). got $preBoundaryTick" }
if ($postWakeTick -ne ($expectedBoundaryTick + 1)) { throw "Expected POST_WAKE_TICK=$(($expectedBoundaryTick + 1)). got $postWakeTick" }

Write-Output 'BAREMETAL_QEMU_TIMER_QUANTUM_BOUNDARY_PROBE=pass'
Write-Output "ARMED_TICKS=$armedTicks"
Write-Output "ARMED_NEXT_FIRE_TICK=$armedNextFireTick"
Write-Output "EXPECTED_BOUNDARY_TICK=$expectedBoundaryTick"
Write-Output "PRE_BOUNDARY_TICK=$preBoundaryTick"
Write-Output "POST_WAKE_TICK=$postWakeTick"
