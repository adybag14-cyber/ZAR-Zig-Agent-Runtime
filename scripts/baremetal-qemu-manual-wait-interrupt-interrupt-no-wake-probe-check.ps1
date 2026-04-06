# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-manual-wait-interrupt-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\\d+)\\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_INTERRUPT_NO_WAKE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_INTERRUPT_NO_WAKE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-manual-wait-interrupt-probe-check.ps1' `
    -FailureLabel 'manual-wait interrupt' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$taskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_TASK_STATE'
$taskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_TASK_COUNT'
$waitKind = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_WAIT_KIND'
$wakeQueueLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_WAKE_QUEUE_LEN'
$interruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_INTERRUPT_COUNT'
$lastVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_LAST_VECTOR'
if ($null -in @($taskState, $taskCount, $waitKind, $wakeQueueLen, $interruptCount, $lastVector)) { throw 'Missing interrupt-no-wake fields in manual-wait-interrupt probe output.' }
if ($taskState -ne 6) { throw "Expected AFTER_INTERRUPT_TASK_STATE=6, got $taskState" }
if ($taskCount -ne 0) { throw "Expected AFTER_INTERRUPT_TASK_COUNT=0, got $taskCount" }
if ($waitKind -ne 1) { throw "Expected AFTER_INTERRUPT_WAIT_KIND=1, got $waitKind" }
if ($wakeQueueLen -ne 0) { throw "Expected AFTER_INTERRUPT_WAKE_QUEUE_LEN=0, got $wakeQueueLen" }
if ($interruptCount -lt 1) { throw "Expected AFTER_INTERRUPT_INTERRUPT_COUNT >= 1, got $interruptCount" }
if ($lastVector -ne 44) { throw "Expected AFTER_INTERRUPT_LAST_VECTOR=44, got $lastVector" }
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_INTERRUPT_NO_WAKE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_INTERRUPT_NO_WAKE_PROBE_SOURCE=baremetal-qemu-manual-wait-interrupt-probe-check.ps1'
Write-Output 'AFTER_INTERRUPT_TASK_STATE=6'
Write-Output 'AFTER_INTERRUPT_TASK_COUNT=0'
Write-Output 'AFTER_INTERRUPT_WAIT_KIND=1'
Write-Output 'AFTER_INTERRUPT_WAKE_QUEUE_LEN=0'
Write-Output "AFTER_INTERRUPT_INTERRUPT_COUNT=$interruptCount"
Write-Output 'AFTER_INTERRUPT_LAST_VECTOR=44'
