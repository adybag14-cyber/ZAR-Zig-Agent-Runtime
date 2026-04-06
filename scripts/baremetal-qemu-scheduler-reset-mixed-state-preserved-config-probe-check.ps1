# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_PRESERVED_CONFIG_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_PRESERVED_CONFIG_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1' `
    -FailureLabel 'scheduler-reset mixed-state' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true
$probeText = $probeState.Text

$postNextTimerId = Extract-IntValue -Text $probeText -Name 'POST_NEXT_TIMER_ID'
$postQuantum = Extract-IntValue -Text $probeText -Name 'POST_QUANTUM'

if ($null -in @($postNextTimerId, $postQuantum)) {
    throw 'Missing expected scheduler-reset mixed-state preserved-config fields in probe output.'
}
if ($postNextTimerId -ne 2) { throw "Expected POST_NEXT_TIMER_ID=2. got $postNextTimerId" }
if ($postQuantum -ne 5) { throw "Expected POST_QUANTUM=5. got $postQuantum" }

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_PRESERVED_CONFIG_PROBE=pass'
Write-Output "POST_NEXT_TIMER_ID=$postNextTimerId"
Write-Output "POST_QUANTUM=$postQuantum"
