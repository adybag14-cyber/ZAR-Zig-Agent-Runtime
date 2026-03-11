param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-cancel-task-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_CANCEL_COLLAPSE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-cancel-task probe failed with exit code $probeExitCode"
}

$cancelTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_CANCEL_TICKS'
$cancelEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_CANCEL_ENTRY_COUNT'
$timerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_TIMER_ENTRY_COUNT'
$pendingWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_PENDING_WAKE_COUNT'
$wakeQueueCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_PROBE_WAKE_QUEUE_COUNT'

if ($null -in @($cancelTicks, $cancelEntryCount, $timerEntryCount, $pendingWakeCount, $wakeQueueCount)) {
    throw 'Missing collapse timer-cancel-task fields.'
}
if ($cancelTicks -le 0) { throw "Expected CANCEL_TICKS>0. got $cancelTicks" }
if ($cancelEntryCount -ne 0) { throw "Expected CANCEL_ENTRY_COUNT=0. got $cancelEntryCount" }
if ($timerEntryCount -ne 0) { throw "Expected TIMER_ENTRY_COUNT=0. got $timerEntryCount" }
if ($pendingWakeCount -ne 0) { throw "Expected PENDING_WAKE_COUNT=0. got $pendingWakeCount" }
if ($wakeQueueCount -ne 0) { throw "Expected WAKE_QUEUE_COUNT=0. got $wakeQueueCount" }

Write-Output 'BAREMETAL_QEMU_TIMER_CANCEL_TASK_CANCEL_COLLAPSE_PROBE=pass'
Write-Output "CANCEL_TICKS=$cancelTicks"
Write-Output "CANCEL_ENTRY_COUNT=$cancelEntryCount"
Write-Output "TIMER_ENTRY_COUNT=$timerEntryCount"
Write-Output "PENDING_WAKE_COUNT=$pendingWakeCount"
Write-Output "WAKE_QUEUE_COUNT=$wakeQueueCount"
