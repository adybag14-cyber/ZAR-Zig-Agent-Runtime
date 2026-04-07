# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-task-lifecycle-probe-check.ps1"
$taskStateWaiting = 6
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TASK_LIFECYCLE_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT2_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT2_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-lifecycle-probe-check.ps1' `
    -FailureLabel 'task-lifecycle'
$probeText = $probeState.Text


$wait2State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT2_STATE'
$wait2TaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT2_TASK_COUNT'

if ($null -in @($wait2State, $wait2TaskCount)) {
    throw 'Missing expected wait2 baseline fields in task-lifecycle probe output.'
}
if ($wait2State -ne $taskStateWaiting) { throw "Expected WAIT2_STATE=$taskStateWaiting. got $wait2State" }
if ($wait2TaskCount -ne 0) { throw "Expected WAIT2_TASK_COUNT=0. got $wait2TaskCount" }

Write-Output 'BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT2_BASELINE_PROBE=pass'
Write-Output "BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT2_STATE=$wait2State"
Write-Output "BAREMETAL_QEMU_TASK_LIFECYCLE_WAIT2_TASK_COUNT=$wait2TaskCount"
