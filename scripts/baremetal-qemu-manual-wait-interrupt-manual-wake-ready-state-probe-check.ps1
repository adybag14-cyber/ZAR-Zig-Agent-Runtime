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
    -SkippedReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_READY_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_READY_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-manual-wait-interrupt-probe-check.ps1' `
    -FailureLabel 'manual-wait interrupt' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_LAST_RESULT'
$manualWakeTaskState = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_TASK_STATE'
$manualWakeTaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_TASK_COUNT'
if ($null -in @($ack, $lastOpcode, $lastResult, $manualWakeTaskState, $manualWakeTaskCount)) {
    throw 'Missing expected manual-wake ready-state fields in manual-wait interrupt probe output.'
}
if ($ack -ne 9) { throw "Expected ACK=9, got $ack" }
if ($lastOpcode -ne 45) { throw "Expected LAST_OPCODE=45, got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0, got $lastResult" }
if ($manualWakeTaskState -ne 1) { throw "Expected MANUAL_WAKE_TASK_STATE=1, got $manualWakeTaskState" }
if ($manualWakeTaskCount -ne 1) { throw "Expected MANUAL_WAKE_TASK_COUNT=1, got $manualWakeTaskCount" }

Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_READY_STATE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_MANUAL_WAKE_READY_STATE_PROBE_SOURCE=baremetal-qemu-manual-wait-interrupt-probe-check.ps1'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "MANUAL_WAKE_TASK_STATE=$manualWakeTaskState"
Write-Output "MANUAL_WAKE_TASK_COUNT=$manualWakeTaskCount"
