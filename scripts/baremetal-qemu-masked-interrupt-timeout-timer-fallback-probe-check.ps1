# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-masked-interrupt-timeout-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_TIMER_FALLBACK_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_TIMER_FALLBACK_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-masked-interrupt-timeout-probe-check.ps1' `
    -FailureLabel 'masked-interrupt-timeout'
$probeText = $probeState.Text


$wake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_WAKE0_REASON'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_WAKE0_VECTOR'
$wake0Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_WAKE0_TICK'
$armedWaitTimeout = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_ARMED_WAIT_TIMEOUT'
$timerLastWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_TIMER_LAST_WAKE_TICK'
$postWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_POST_WAKE_TICK'
if ($null -in @($wake0Reason, $wake0Vector, $wake0Tick, $armedWaitTimeout, $timerLastWakeTick, $postWakeTick)) {
    throw 'Missing timer-fallback fields in probe output.'
}
if ($wake0Reason -ne 1) { throw "Expected timer wake reason (1). got $wake0Reason" }
if ($wake0Vector -ne 0) { throw "Expected timer fallback vector 0. got $wake0Vector" }
if ($wake0Tick -ne $armedWaitTimeout) { throw "Expected wake tick to match armed timeout. wake=$wake0Tick timeout=$armedWaitTimeout" }
if ($timerLastWakeTick -ne $wake0Tick) { throw "Expected timer last wake tick to match queued wake tick. lastWake=$timerLastWakeTick wake=$wake0Tick" }
if ($postWakeTick -ne ($wake0Tick + 1)) { throw "Expected post-wake tick to be wake tick + 1. postWake=$postWakeTick wake=$wake0Tick" }

Write-Output 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_TIMER_FALLBACK_PROBE=pass'
Write-Output "WAKE0_REASON=$wake0Reason"
Write-Output "WAKE0_VECTOR=$wake0Vector"
Write-Output "WAKE0_TICK=$wake0Tick"
Write-Output "ARMED_WAIT_TIMEOUT=$armedWaitTimeout"
Write-Output "TIMER_LAST_WAKE_TICK=$timerLastWakeTick"
Write-Output "POST_WAKE_TICK=$postWakeTick"
