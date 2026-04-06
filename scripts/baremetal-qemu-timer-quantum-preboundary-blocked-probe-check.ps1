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
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_QUANTUM_PREBOUNDARY_BLOCKED_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TIMER_QUANTUM_PREBOUNDARY_BLOCKED_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-timer-quantum-probe-check.ps1' `
    -FailureLabel 'timer-quantum'
$probeText = $probeState.Text

$expectedBoundaryTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_QUANTUM_PROBE_EXPECTED_BOUNDARY_TICK'
$preBoundaryTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_QUANTUM_PROBE_PRE_BOUNDARY_TICK'
$preBoundaryWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_QUANTUM_PROBE_PRE_BOUNDARY_WAKE_COUNT'
$preBoundaryTaskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_QUANTUM_PROBE_PRE_BOUNDARY_TASK_STATE'
$preBoundaryDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_QUANTUM_PROBE_PRE_BOUNDARY_DISPATCH_COUNT'

if ($null -in @($expectedBoundaryTick, $preBoundaryTick, $preBoundaryWakeCount, $preBoundaryTaskState, $preBoundaryDispatchCount)) {
    throw 'Missing expected pre-boundary fields in timer-quantum probe output.'
}
if ($preBoundaryTick -ne ($expectedBoundaryTick - 1)) { throw "Expected PRE_BOUNDARY_TICK=$(($expectedBoundaryTick - 1)). got $preBoundaryTick" }
if ($preBoundaryWakeCount -ne 0) { throw "Expected PRE_BOUNDARY_WAKE_COUNT=0. got $preBoundaryWakeCount" }
if ($preBoundaryTaskState -ne 6) { throw "Expected PRE_BOUNDARY_TASK_STATE=6. got $preBoundaryTaskState" }
if ($preBoundaryDispatchCount -ne 0) { throw "Expected PRE_BOUNDARY_DISPATCH_COUNT=0. got $preBoundaryDispatchCount" }

Write-Output 'BAREMETAL_QEMU_TIMER_QUANTUM_PREBOUNDARY_BLOCKED_PROBE=pass'
Write-Output "PRE_BOUNDARY_TICK=$preBoundaryTick"
Write-Output "PRE_BOUNDARY_WAKE_COUNT=$preBoundaryWakeCount"
Write-Output "PRE_BOUNDARY_TASK_STATE=$preBoundaryTaskState"
Write-Output "PRE_BOUNDARY_DISPATCH_COUNT=$preBoundaryDispatchCount"
