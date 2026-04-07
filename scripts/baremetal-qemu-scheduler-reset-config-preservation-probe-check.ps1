# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_PROBE=skipped\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_CONFIG_PRESERVATION_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_SCHEDULER_RESET_CONFIG_PRESERVATION_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1' `
    -FailureLabel 'scheduler-reset mixed-state'
$probeText = $probeState.Text

$preNextTimerId = Extract-IntValue -Text $probeText -Name 'PRE_NEXT_TIMER_ID'
$preQuantum = Extract-IntValue -Text $probeText -Name 'PRE_QUANTUM'
$postNextTimerId = Extract-IntValue -Text $probeText -Name 'POST_NEXT_TIMER_ID'
$postQuantum = Extract-IntValue -Text $probeText -Name 'POST_QUANTUM'
$rearmTimerId = Extract-IntValue -Text $probeText -Name 'REARM_TIMER_ID'
$rearmNextTimerId = Extract-IntValue -Text $probeText -Name 'REARM_NEXT_TIMER_ID'

if ($null -in @($preNextTimerId, $preQuantum, $postNextTimerId, $postQuantum, $rearmTimerId, $rearmNextTimerId)) {
    throw 'Missing expected scheduler-reset config-preservation fields in probe output.'
}
if ($preQuantum -ne $postQuantum) {
    throw "Expected timer quantum to survive scheduler reset. pre=$preQuantum post=$postQuantum"
}
if ($preNextTimerId -ne $postNextTimerId) {
    throw "Expected next_timer_id to survive scheduler reset. pre=$preNextTimerId post=$postNextTimerId"
}
if ($rearmTimerId -ne $postNextTimerId) {
    throw "Expected first post-reset rearm to reuse preserved next_timer_id=$postNextTimerId. got $rearmTimerId"
}
if ($rearmNextTimerId -ne ($rearmTimerId + 1)) {
    throw "Expected next_timer_id to advance by one after post-reset rearm. timer_id=$rearmTimerId next=$rearmNextTimerId"
}

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_CONFIG_PRESERVATION_PROBE=pass'
Write-Output "PRE_NEXT_TIMER_ID=$preNextTimerId"
Write-Output "POST_NEXT_TIMER_ID=$postNextTimerId"
Write-Output "PRE_QUANTUM=$preQuantum"
Write-Output "POST_QUANTUM=$postQuantum"
Write-Output "REARM_TIMER_ID=$rearmTimerId"
Write-Output "REARM_NEXT_TIMER_ID=$rearmNextTimerId"
