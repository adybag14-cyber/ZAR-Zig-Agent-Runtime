# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-task-terminate-interrupt-timeout-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_INTERRUPT_TELEMETRY_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_INTERRUPT_TELEMETRY_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-task-terminate-interrupt-timeout-probe-check.ps1' `
    -FailureLabel 'task-terminate interrupt-timeout' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_INTERRUPT_COUNT'
$lastInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_LAST_INTERRUPT_VECTOR'
$timerLastInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_TIMER_LAST_INTERRUPT_COUNT'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_PROBE_WAKE_QUEUE_COUNT'

if ($null -in @($interruptCount, $lastInterruptVector, $timerLastInterruptCount, $wakeQueueCount)) {
    throw 'Missing expected interrupt telemetry fields in task-terminate interrupt-timeout probe output.'
}
if ($interruptCount -ne 1) { throw "Expected INTERRUPT_COUNT=1. got $interruptCount" }
if ($lastInterruptVector -ne 200) { throw "Expected LAST_INTERRUPT_VECTOR=200. got $lastInterruptVector" }
if ($timerLastInterruptCount -ne 1) { throw "Expected TIMER_LAST_INTERRUPT_COUNT=1. got $timerLastInterruptCount" }
if ($wakeQueueCount -ne 0) { throw "Expected WAKE_QUEUE_COUNT=0 after interrupt. got $wakeQueueCount" }

Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_INTERRUPT_TELEMETRY_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TASK_TERMINATE_INTERRUPT_TIMEOUT_INTERRUPT_TELEMETRY_PROBE_SOURCE=baremetal-qemu-task-terminate-interrupt-timeout-probe-check.ps1'
Write-Output "INTERRUPT_COUNT=$interruptCount"
Write-Output "LAST_INTERRUPT_VECTOR=$lastInterruptVector"
Write-Output "TIMER_LAST_INTERRUPT_COUNT=$timerLastInterruptCount"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
