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
    -SkippedReceipt 'BAREMETAL_QEMU_TIMER_PRESSURE_REUSE_NEXT_FIRE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TIMER_PRESSURE_REUSE_NEXT_FIRE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-timer-pressure-probe-check.ps1' `
    -FailureLabel 'timer-pressure'
$probeText = $probeState.Text


$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
$reuseTaskState = Extract-IntValue -Text $probeText -Name 'REUSE_TASK_STATE'
$reuseNextFire = Extract-IntValue -Text $probeText -Name 'REUSE_NEXT_FIRE'
if ($null -in @($ticks,$reuseTaskState,$reuseNextFire)) {
    throw 'Missing timer-pressure reuse-next-fire fields.'
}
if ($reuseTaskState -ne 6) { throw "Expected REUSE_TASK_STATE=6. got $reuseTaskState" }
if ($reuseNextFire -le $ticks) { throw "Expected REUSE_NEXT_FIRE>$ticks. got $reuseNextFire" }

Write-Output 'BAREMETAL_QEMU_TIMER_PRESSURE_REUSE_NEXT_FIRE_PROBE=pass'
Write-Output "TICKS=$ticks"
Write-Output "REUSE_TASK_STATE=$reuseTaskState"
Write-Output "REUSE_NEXT_FIRE=$reuseNextFire"
