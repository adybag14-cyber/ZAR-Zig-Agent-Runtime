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
    -SkippedReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_BASELINE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_BASELINE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-manual-wait-interrupt-probe-check.ps1' `
    -FailureLabel 'manual-wait interrupt' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true
$probeText = $probeState.Text

$taskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_TASK_ID'
$taskPriority = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_TASK_PRIORITY'
$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_TICKS'
if ($null -in @($taskId, $taskPriority, $ack, $lastOpcode, $lastResult, $ticks)) { throw 'Missing baseline fields in manual-wait-interrupt probe output.' }
if ($taskId -le 0) { throw "Expected TASK_ID > 0, got $taskId" }
if ($taskPriority -ne 0) { throw "Expected TASK_PRIORITY=0, got $taskPriority" }
if ($ack -ne 9) { throw "Expected ACK=9, got $ack" }
if ($lastOpcode -ne 45) { throw "Expected LAST_OPCODE=45, got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0, got $lastResult" }
if ($ticks -lt 9) { throw "Expected TICKS >= 9, got $ticks" }
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_BASELINE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MANUAL_WAIT_INTERRUPT_BASELINE_PROBE_SOURCE=baremetal-qemu-manual-wait-interrupt-probe-check.ps1'
Write-Output "TASK_ID=$taskId"
Write-Output 'TASK_PRIORITY=0'
Write-Output 'ACK=9'
Write-Output 'LAST_OPCODE=45'
Write-Output 'LAST_RESULT=0'
Write-Output "TICKS=$ticks"
