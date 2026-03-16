# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-mask-control-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_UNMASK_DELIVERY_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_UNMASK_DELIVERY_PROBE_SOURCE=baremetal-qemu-interrupt-mask-control-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-mask-control probe failed with exit code $probeExitCode"
}

$task0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_UNMASKED_TASK0_STATE'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_UNMASKED_WAKE_QUEUE_COUNT'
$wake0Vector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_UNMASKED_WAKE0_VECTOR'
$wake0Reason = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_UNMASKED_WAKE0_REASON'
$task0Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_TASK0_ID'
$wake0TaskId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_WAKE0_TASK_ID'
$wake0TimerId = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_PROBE_WAKE0_TIMER_ID'
if ($null -in @($task0State, $wakeQueueCount, $wake0Vector, $wake0Reason, $task0Id, $wake0TaskId, $wake0TimerId)) {
    throw 'Missing unmask-delivery fields in interrupt-mask-control probe output.'
}
if ($task0State -ne 1) { throw "Expected UNMASKED_TASK0_STATE=1, got $task0State" }
if ($wakeQueueCount -ne 1) { throw "Expected UNMASKED_WAKE_QUEUE_COUNT=1, got $wakeQueueCount" }
if ($wake0Vector -ne 200) { throw "Expected UNMASKED_WAKE0_VECTOR=200, got $wake0Vector" }
if ($wake0Reason -ne 2) { throw "Expected UNMASKED_WAKE0_REASON=2, got $wake0Reason" }
if ($wake0TaskId -ne $task0Id) { throw "Expected WAKE0_TASK_ID=$task0Id, got $wake0TaskId" }
if ($wake0TimerId -ne 0) { throw "Expected WAKE0_TIMER_ID=0, got $wake0TimerId" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_UNMASK_DELIVERY_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MASK_CONTROL_UNMASK_DELIVERY_PROBE_SOURCE=baremetal-qemu-interrupt-mask-control-probe-check.ps1'
Write-Output "UNMASKED_TASK0_STATE=$task0State"
Write-Output "UNMASKED_WAKE_QUEUE_COUNT=$wakeQueueCount"
Write-Output "UNMASKED_WAKE0_VECTOR=$wake0Vector"
Write-Output "UNMASKED_WAKE0_REASON=$wake0Reason"
Write-Output "TASK0_ID=$task0Id"
Write-Output "WAKE0_TASK_ID=$wake0TaskId"
Write-Output "WAKE0_TIMER_ID=$wake0TimerId"
