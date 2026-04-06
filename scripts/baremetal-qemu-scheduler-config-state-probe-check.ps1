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
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_CONFIG_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_CONFIG_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-probe-check.ps1' `
    -FailureLabel 'scheduler'
$probeText = $probeState.Text

$enabled = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_ENABLED'
$taskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_TASK_COUNT'
$runningSlot = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_RUNNING_SLOT'
$timeslice = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_TIMESLICE'
$policy = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_SCHEDULER_PROBE_POLICY'

if ($null -in @($enabled, $taskCount, $runningSlot, $timeslice, $policy)) {
    throw 'Missing expected scheduler config fields in probe output.'
}
if ($enabled -ne 1) { throw "Expected ENABLED=1. got $enabled" }
if ($taskCount -ne 1) { throw "Expected TASK_COUNT=1. got $taskCount" }
if ($runningSlot -ne 0) { throw "Expected RUNNING_SLOT=0. got $runningSlot" }
if ($timeslice -ne 3) { throw "Expected TIMESLICE=3. got $timeslice" }
if ($policy -ne 1) { throw "Expected POLICY=1. got $policy" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_CONFIG_STATE_PROBE=pass'
Write-Output "ENABLED=$enabled"
Write-Output "TASK_COUNT=$taskCount"
Write-Output "RUNNING_SLOT=$runningSlot"
Write-Output "TIMESLICE=$timeslice"
Write-Output "POLICY=$policy"
