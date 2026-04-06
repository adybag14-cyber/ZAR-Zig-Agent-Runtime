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
    -SkippedReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_PAYLOAD_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_PAYLOAD_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-manual-wait-interrupt-probe-check.ps1' `
    -FailureLabel 'manual-wait interrupt' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_TASK_ID'
$taskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_TASK_STATE'
$taskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_TASK_COUNT'
$queueLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_QUEUE_LEN'
$reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_REASON'
$wakeTaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_TASK_ID'
$wakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_TICK'
if ($null -in @($taskId, $taskState, $taskCount, $queueLen, $reason, $wakeTaskId, $wakeTick)) { throw 'Missing manual-wake fields in manual-wait-interrupt probe output.' }
if ($taskState -ne 1) { throw "Expected MANUAL_WAKE_TASK_STATE=1, got $taskState" }
if ($taskCount -ne 1) { throw "Expected MANUAL_WAKE_TASK_COUNT=1, got $taskCount" }
if ($queueLen -ne 1) { throw "Expected MANUAL_WAKE_QUEUE_LEN=1, got $queueLen" }
if ($reason -ne 3) { throw "Expected MANUAL_WAKE_REASON=3, got $reason" }
if ($wakeTaskId -ne $taskId) { throw "Expected MANUAL_WAKE_TASK_ID=$taskId, got $wakeTaskId" }
if ($wakeTick -le 0) { throw "Expected MANUAL_WAKE_TICK > 0, got $wakeTick" }
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_PAYLOAD_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_PAYLOAD_PROBE_SOURCE=baremetal-qemu-manual-wait-interrupt-probe-check.ps1'
Write-Output 'MANUAL_WAKE_TASK_STATE=1'
Write-Output 'MANUAL_WAKE_TASK_COUNT=1'
Write-Output 'MANUAL_WAKE_QUEUE_LEN=1'
Write-Output 'MANUAL_WAKE_REASON=3'
Write-Output "MANUAL_WAKE_TASK_ID=$wakeTaskId"
Write-Output "MANUAL_WAKE_TICK=$wakeTick"
