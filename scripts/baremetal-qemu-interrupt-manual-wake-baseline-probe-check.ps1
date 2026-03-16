# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-manual-wake-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
if ($probeText -match '(?m)^BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE=skipped\r?$') {
    if ($probeText) { Write-Output $probeText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_BASELINE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_BASELINE_PROBE_SOURCE=baremetal-qemu-interrupt-manual-wake-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    if ($probeText) { Write-Output $probeText.TrimEnd() }
    throw "Underlying interrupt-manual-wake probe failed with exit code $probeExitCode"
}
$ack = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_LAST_RESULT'
$schedTaskCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_SCHED_TASK_COUNT'
$task0Id = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TASK0_ID'
$task0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TASK0_STATE'
$task0Priority = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TASK0_PRIORITY'
$task0RunCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TASK0_RUN_COUNT'
$task0Budget = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TASK0_BUDGET'
$task0BudgetRemaining = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TASK0_BUDGET_REMAINING'
if ($null -in @($ack,$lastOpcode,$lastResult,$schedTaskCount,$task0Id,$task0State,$task0Priority,$task0RunCount,$task0Budget,$task0BudgetRemaining)) {
    throw 'Missing expected interrupt-manual-wake baseline fields in probe output.'
}
if ($ack -ne 8) { throw "Expected ACK=8. got $ack" }
if ($lastOpcode -ne 7) { throw "Expected LAST_OPCODE=7. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($schedTaskCount -ne 1) { throw "Expected SCHED_TASK_COUNT=1. got $schedTaskCount" }
if ($task0Id -ne 1) { throw "Expected TASK0_ID=1. got $task0Id" }
if ($task0State -ne 1) { throw "Expected TASK0_STATE=1. got $task0State" }
if ($task0Priority -ne 0) { throw "Expected TASK0_PRIORITY=0. got $task0Priority" }
if ($task0RunCount -ne 0) { throw "Expected TASK0_RUN_COUNT=0. got $task0RunCount" }
if ($task0Budget -ne 5) { throw "Expected TASK0_BUDGET=5. got $task0Budget" }
if ($task0BudgetRemaining -ne 5) { throw "Expected TASK0_BUDGET_REMAINING=5. got $task0BudgetRemaining" }
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_BASELINE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_BASELINE_PROBE_SOURCE=baremetal-qemu-interrupt-manual-wake-probe-check.ps1'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "SCHED_TASK_COUNT=$schedTaskCount"
Write-Output "TASK0_ID=$task0Id"
Write-Output "TASK0_STATE=$task0State"
Write-Output "TASK0_PRIORITY=$task0Priority"
Write-Output "TASK0_RUN_COUNT=$task0RunCount"
Write-Output "TASK0_BUDGET=$task0Budget"
Write-Output "TASK0_BUDGET_REMAINING=$task0BudgetRemaining"
