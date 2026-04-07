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
    -SkippedReceipt 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_NO_WAKE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_NO_WAKE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-masked-interrupt-timeout-probe-check.ps1' `
    -FailureLabel 'masked-interrupt-timeout'
$probeText = $probeState.Text


$task0StateAfterInterrupt = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_TASK0_STATE_AFTER_INTERRUPT'
$wakeQueueCountAfterInterrupt = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_WAKE_QUEUE_COUNT_AFTER_INTERRUPT'
$interruptCountAfterInterrupt = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_INTERRUPT_COUNT_AFTER_INTERRUPT'
if ($null -in @($task0StateAfterInterrupt, $wakeQueueCountAfterInterrupt, $interruptCountAfterInterrupt)) {
    throw 'Missing no-wake fields in probe output.'
}
if ($task0StateAfterInterrupt -ne 6) { throw "Expected waiting state (6) after masked interrupt. got $task0StateAfterInterrupt" }
if ($wakeQueueCountAfterInterrupt -ne 0) { throw "Expected no queued wake after masked interrupt. got $wakeQueueCountAfterInterrupt" }
if ($interruptCountAfterInterrupt -ne 0) { throw "Expected zero delivered interrupts after masked interrupt. got $interruptCountAfterInterrupt" }

Write-Output 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_NO_WAKE_PROBE=pass'
Write-Output "TASK0_STATE_AFTER_INTERRUPT=$task0StateAfterInterrupt"
Write-Output "WAKE_QUEUE_COUNT_AFTER_INTERRUPT=$wakeQueueCountAfterInterrupt"
Write-Output "INTERRUPT_COUNT_AFTER_INTERRUPT=$interruptCountAfterInterrupt"
