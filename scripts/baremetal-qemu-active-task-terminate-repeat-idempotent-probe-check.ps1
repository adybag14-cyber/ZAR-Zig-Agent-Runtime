# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-active-task-terminate-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_REPEAT_IDEMPOTENT_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_REPEAT_IDEMPOTENT_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-active-task-terminate-probe-check.ps1' `
    -FailureLabel 'active-task terminate'
$probeText = $probeState.Text

$repeatResult = Extract-IntValue -Text $probeText -Name 'REPEAT_TERMINATE_RESULT'
if ($null -eq $repeatResult) {
    throw 'Missing REPEAT_TERMINATE_RESULT in active-task terminate probe output.'
}
if ($repeatResult -ne 0) { throw "Expected REPEAT_TERMINATE_RESULT=0. got $repeatResult" }

Write-Output 'BAREMETAL_QEMU_ACTIVE_TASK_TERMINATE_REPEAT_IDEMPOTENT_PROBE=pass'
Write-Output "REPEAT_TERMINATE_RESULT=$repeatResult"
