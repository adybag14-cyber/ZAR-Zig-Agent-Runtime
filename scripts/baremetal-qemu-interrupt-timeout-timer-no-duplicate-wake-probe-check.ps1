# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-timer-probe-check.ps1"
$postWakeSlackTicks = 4

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
if ($probeText -match '(?m)^BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_NO_DUPLICATE_WAKE_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_NO_DUPLICATE_WAKE_PROBE_SOURCE=baremetal-qemu-interrupt-timeout-timer-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout timer probe failed with exit code $probeExitCode"
}

$ticks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_PROBE_TICKS'
$postWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_PROBE_POST_WAKE_TICK'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_PROBE_WAKE_QUEUE_COUNT'
$wake0Seq = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_PROBE_WAKE0_SEQ'
$timerPendingWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_PROBE_TIMER_PENDING_WAKE_COUNT'
$timerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_PROBE_TIMER_ENTRY_COUNT'

if ($null -in @($ticks, $postWakeTick, $wakeQueueCount, $wake0Seq, $timerPendingWakeCount, $timerEntryCount)) {
    throw 'Missing expected interrupt-timeout timer no-duplicate-wake fields in probe output.'
}
if ($ticks -lt ($postWakeTick + $postWakeSlackTicks)) { throw "Expected TICKS >= POST_WAKE_TICK + $postWakeSlackTicks. ticks=$ticks post=$postWakeTick" }
if ($wakeQueueCount -ne 1) { throw "Expected WAKE_QUEUE_COUNT=1 after slack, got $wakeQueueCount" }
if ($wake0Seq -ne 1) { throw "Expected WAKE0_SEQ=1, got $wake0Seq" }
if ($timerPendingWakeCount -ne 1) { throw "Expected TIMER_PENDING_WAKE_COUNT=1, got $timerPendingWakeCount" }
if ($timerEntryCount -ne 0) { throw "Expected TIMER_ENTRY_COUNT=0, got $timerEntryCount" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_NO_DUPLICATE_WAKE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_NO_DUPLICATE_WAKE_PROBE_SOURCE=baremetal-qemu-interrupt-timeout-timer-probe-check.ps1'
Write-Output "TICKS=$ticks"
Write-Output "POST_WAKE_TICK=$postWakeTick"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
Write-Output "WAKE0_SEQ=$wake0Seq"
Write-Output "TIMER_PENDING_WAKE_COUNT=$timerPendingWakeCount"
Write-Output "TIMER_ENTRY_COUNT=$timerEntryCount"
