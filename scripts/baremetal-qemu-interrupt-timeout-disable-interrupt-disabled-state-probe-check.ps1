param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-disable-interrupt-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_DISABLED_STATE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout disable-interrupt probe failed with exit code $probeExitCode"
}

$disabledTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_TICK'
$disabledTimerEnabled = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_TIMER_ENABLED'
$disabledTimerDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_TIMER_DISPATCH_COUNT'
$disabledTimerPendingWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_TIMER_PENDING_WAKE_COUNT'
$pausedTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_PAUSED_TICK'
if ($null -in @($disabledTick, $disabledTimerEnabled, $disabledTimerDispatchCount, $disabledTimerPendingWakeCount, $pausedTick)) {
    throw 'Missing disabled-state fields in probe output.'
}
if ($disabledTimerEnabled -ne 0) { throw "Expected timers to remain disabled after interrupt wake. got $disabledTimerEnabled" }
if ($disabledTimerDispatchCount -ne 0) { throw "Expected zero timer dispatch while disabled. got $disabledTimerDispatchCount" }
if ($disabledTimerPendingWakeCount -ne 1) { throw "Expected one pending wake tracked while disabled. got $disabledTimerPendingWakeCount" }
if ($disabledTick -lt $pausedTick) { throw "Expected disabled wake tick to be at or after the paused tick. paused=$pausedTick disabled=$disabledTick" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_DISABLED_STATE_PROBE=pass'
Write-Output "DISABLED_TICK=$disabledTick"
Write-Output "PAUSED_TICK=$pausedTick"
Write-Output "DISABLED_TIMER_ENABLED=$disabledTimerEnabled"
Write-Output "DISABLED_TIMER_DISPATCH_COUNT=$disabledTimerDispatchCount"
Write-Output "DISABLED_TIMER_PENDING_WAKE_COUNT=$disabledTimerPendingWakeCount"
