# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-probe-check.ps1"
$waitConditionInterruptAny = 3
$taskStateWaiting = 6

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
if ($probeText -match '(?m)^BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_ARM_PRESERVATION_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_ARM_PRESERVATION_PROBE_SOURCE=baremetal-qemu-interrupt-timeout-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout probe failed with exit code $probeExitCode"
}

$beforeInterruptTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_BEFORE_INTERRUPT_TICK'
$beforeInterruptTask0State = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_BEFORE_INTERRUPT_TASK0_STATE'
$beforeInterruptWaitKind0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_BEFORE_INTERRUPT_WAIT_KIND0'
$beforeInterruptWaitVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_BEFORE_INTERRUPT_WAIT_VECTOR0'
$beforeInterruptWaitTimeout0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_BEFORE_INTERRUPT_WAIT_TIMEOUT0'
$beforeInterruptWakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_PROBE_BEFORE_INTERRUPT_WAKE_QUEUE_COUNT'

if ($null -in @($beforeInterruptTick, $beforeInterruptTask0State, $beforeInterruptWaitKind0, $beforeInterruptWaitVector0, $beforeInterruptWaitTimeout0, $beforeInterruptWakeQueueCount)) {
    throw 'Missing expected interrupt-timeout arm-preservation fields in probe output.'
}
if ($beforeInterruptTick -lt 0) { throw "Expected BEFORE_INTERRUPT_TICK >= 0, got $beforeInterruptTick" }
if ($beforeInterruptTask0State -ne $taskStateWaiting) { throw "Expected BEFORE_INTERRUPT_TASK0_STATE=6, got $beforeInterruptTask0State" }
if ($beforeInterruptWaitKind0 -ne $waitConditionInterruptAny) { throw "Expected BEFORE_INTERRUPT_WAIT_KIND0=3, got $beforeInterruptWaitKind0" }
if ($beforeInterruptWaitVector0 -ne 0) { throw "Expected BEFORE_INTERRUPT_WAIT_VECTOR0=0, got $beforeInterruptWaitVector0" }
if ($beforeInterruptWaitTimeout0 -le $beforeInterruptTick) { throw "Expected BEFORE_INTERRUPT_WAIT_TIMEOUT0 > BEFORE_INTERRUPT_TICK. timeout=$beforeInterruptWaitTimeout0 tick=$beforeInterruptTick" }
if ($beforeInterruptWakeQueueCount -ne 0) { throw "Expected BEFORE_INTERRUPT_WAKE_QUEUE_COUNT=0, got $beforeInterruptWakeQueueCount" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_ARM_PRESERVATION_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_ARM_PRESERVATION_PROBE_SOURCE=baremetal-qemu-interrupt-timeout-probe-check.ps1'
Write-Output "BEFORE_INTERRUPT_TICK=$beforeInterruptTick"
Write-Output "BEFORE_INTERRUPT_TASK0_STATE=$beforeInterruptTask0State"
Write-Output "BEFORE_INTERRUPT_WAIT_KIND0=$beforeInterruptWaitKind0"
Write-Output "BEFORE_INTERRUPT_WAIT_VECTOR0=$beforeInterruptWaitVector0"
Write-Output "BEFORE_INTERRUPT_WAIT_TIMEOUT0=$beforeInterruptWaitTimeout0"
Write-Output "BEFORE_INTERRUPT_WAKE_QUEUE_COUNT=$beforeInterruptWakeQueueCount"
