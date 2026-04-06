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
    -SkippedReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_BLOCKED_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_BLOCKED_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-manual-wait-interrupt-probe-check.ps1' `
    -FailureLabel 'manual-wait interrupt' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$afterInterruptTaskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_TASK_STATE'
$afterInterruptTaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_TASK_COUNT'
$afterInterruptWaitKind = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_WAIT_KIND'
$afterInterruptWakeQueueLen = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_WAKE_QUEUE_LEN'
if ($null -in @($afterInterruptTaskState, $afterInterruptTaskCount, $afterInterruptWaitKind, $afterInterruptWakeQueueLen)) {
    throw 'Missing expected after-interrupt blocked fields in manual-wait interrupt probe output.'
}
if ($afterInterruptTaskState -ne 6) { throw "Expected AFTER_INTERRUPT_TASK_STATE=6, got $afterInterruptTaskState" }
if ($afterInterruptTaskCount -ne 0) { throw "Expected AFTER_INTERRUPT_TASK_COUNT=0, got $afterInterruptTaskCount" }
if ($afterInterruptWaitKind -ne 1) { throw "Expected AFTER_INTERRUPT_WAIT_KIND=1, got $afterInterruptWaitKind" }
if ($afterInterruptWakeQueueLen -ne 0) { throw "Expected AFTER_INTERRUPT_WAKE_QUEUE_LEN=0, got $afterInterruptWakeQueueLen" }

Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_BLOCKED_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_AFTER_INTERRUPT_BLOCKED_PROBE_SOURCE=baremetal-qemu-manual-wait-interrupt-probe-check.ps1'
Write-Output "AFTER_INTERRUPT_TASK_STATE=$afterInterruptTaskState"
Write-Output "AFTER_INTERRUPT_TASK_COUNT=$afterInterruptTaskCount"
Write-Output "AFTER_INTERRUPT_WAIT_KIND=$afterInterruptWaitKind"
Write-Output "AFTER_INTERRUPT_WAKE_QUEUE_LEN=$afterInterruptWakeQueueLen"
