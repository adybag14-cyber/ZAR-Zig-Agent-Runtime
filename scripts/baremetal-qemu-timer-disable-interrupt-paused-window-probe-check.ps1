param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 40,
    [int] $GdbPort = 1440
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-disable-interrupt-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds; GdbPort = $GdbPort }
if ($SkipBuild) { $invoke.SkipBuild = $true }

$probeOutput = & $probe @invoke 2>&1
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_PAUSED_WINDOW_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_PAUSED_WINDOW_PROBE_SOURCE=baremetal-qemu-timer-disable-interrupt-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-disable interrupt probe failed with exit code $probeExitCode"
}

$afterInterruptTick = Extract-IntValue -Text $probeText -Name 'AFTER_INTERRUPT_TICK'
$pausedTick = Extract-IntValue -Text $probeText -Name 'PAUSED_TICK'
$pausedPendingWakeCount = Extract-IntValue -Text $probeText -Name 'PAUSED_PENDING_WAKE_COUNT'
$pausedWakeQueueCount = Extract-IntValue -Text $probeText -Name 'PAUSED_WAKE_QUEUE_COUNT'
$pausedTimerEntryCount = Extract-IntValue -Text $probeText -Name 'PAUSED_TIMER_ENTRY_COUNT'
$pausedTimerDispatchCount = Extract-IntValue -Text $probeText -Name 'PAUSED_TIMER_DISPATCH_COUNT'
$pausedInterruptTaskState = Extract-IntValue -Text $probeText -Name 'PAUSED_INTERRUPT_TASK_STATE'
$pausedTimerTaskState = Extract-IntValue -Text $probeText -Name 'PAUSED_TIMER_TASK_STATE'

if ($null -in @($afterInterruptTick, $pausedTick, $pausedPendingWakeCount, $pausedWakeQueueCount, $pausedTimerEntryCount, $pausedTimerDispatchCount, $pausedInterruptTaskState, $pausedTimerTaskState)) {
    throw 'Missing expected timer-disable paused-window fields in probe output.'
}
if ($afterInterruptTick -le 0) { throw "Expected AFTER_INTERRUPT_TICK > 0, got $afterInterruptTick" }
if ($pausedTick -le $afterInterruptTick) { throw "Expected PAUSED_TICK > AFTER_INTERRUPT_TICK. got PAUSED_TICK=$pausedTick AFTER_INTERRUPT_TICK=$afterInterruptTick" }
if ($pausedPendingWakeCount -ne 1) { throw "Expected PAUSED_PENDING_WAKE_COUNT=1, got $pausedPendingWakeCount" }
if ($pausedWakeQueueCount -ne 1) { throw "Expected PAUSED_WAKE_QUEUE_COUNT=1, got $pausedWakeQueueCount" }
if ($pausedTimerEntryCount -ne 1) { throw "Expected PAUSED_TIMER_ENTRY_COUNT=1, got $pausedTimerEntryCount" }
if ($pausedTimerDispatchCount -ne 0) { throw "Expected PAUSED_TIMER_DISPATCH_COUNT=0, got $pausedTimerDispatchCount" }
if ($pausedInterruptTaskState -ne 1) { throw "Expected PAUSED_INTERRUPT_TASK_STATE=1, got $pausedInterruptTaskState" }
if ($pausedTimerTaskState -ne 6) { throw "Expected PAUSED_TIMER_TASK_STATE=6, got $pausedTimerTaskState" }

Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_PAUSED_WINDOW_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_TIMER_DISABLE_INTERRUPT_PAUSED_WINDOW_PROBE_SOURCE=baremetal-qemu-timer-disable-interrupt-probe-check.ps1'
Write-Output "AFTER_INTERRUPT_TICK=$afterInterruptTick"
Write-Output "PAUSED_TICK=$pausedTick"
Write-Output "PAUSED_PENDING_WAKE_COUNT=$pausedPendingWakeCount"
Write-Output "PAUSED_WAKE_QUEUE_COUNT=$pausedWakeQueueCount"
Write-Output "PAUSED_TIMER_ENTRY_COUNT=$pausedTimerEntryCount"
Write-Output "PAUSED_TIMER_DISPATCH_COUNT=$pausedTimerDispatchCount"
