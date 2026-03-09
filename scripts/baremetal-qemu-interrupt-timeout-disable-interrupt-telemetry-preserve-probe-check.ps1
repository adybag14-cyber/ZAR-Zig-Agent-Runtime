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
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_TELEMETRY_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout disable-interrupt probe failed with exit code $probeExitCode"
}

$disabledTimerLastInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_TIMER_LAST_INTERRUPT_COUNT'
$disabledLastInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_LAST_INTERRUPT_VECTOR'
$finalTimerLastInterruptCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_FINAL_TIMER_LAST_INTERRUPT_COUNT'
$finalLastInterruptVector = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_FINAL_LAST_INTERRUPT_VECTOR'
$finalTimerLastWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_FINAL_TIMER_LAST_WAKE_TICK'
$finalWake0Tick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_FINAL_WAKE0_TICK'
if ($null -in @($disabledTimerLastInterruptCount, $disabledLastInterruptVector, $finalTimerLastInterruptCount, $finalLastInterruptVector, $finalTimerLastWakeTick, $finalWake0Tick)) {
    throw 'Missing telemetry-preserve fields in probe output.'
}
if ($disabledTimerLastInterruptCount -ne 1) { throw "Expected disabled-stage last interrupt count to be 1. got $disabledTimerLastInterruptCount" }
if ($disabledLastInterruptVector -ne 31) { throw "Expected disabled-stage last interrupt vector 31. got $disabledLastInterruptVector" }
if ($finalTimerLastInterruptCount -ne 1) { throw "Expected final last interrupt count to remain 1. got $finalTimerLastInterruptCount" }
if ($finalLastInterruptVector -ne 31) { throw "Expected final last interrupt vector to remain 31. got $finalLastInterruptVector" }
if ($finalTimerLastWakeTick -ne $finalWake0Tick) { throw "Expected last wake tick to match the retained interrupt wake tick. lastWake=$finalTimerLastWakeTick wake0=$finalWake0Tick" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_TELEMETRY_PRESERVE_PROBE=pass'
Write-Output "DISABLED_TIMER_LAST_INTERRUPT_COUNT=$disabledTimerLastInterruptCount"
Write-Output "DISABLED_LAST_INTERRUPT_VECTOR=$disabledLastInterruptVector"
Write-Output "FINAL_TIMER_LAST_INTERRUPT_COUNT=$finalTimerLastInterruptCount"
Write-Output "FINAL_LAST_INTERRUPT_VECTOR=$finalLastInterruptVector"
Write-Output "FINAL_TIMER_LAST_WAKE_TICK=$finalTimerLastWakeTick"
Write-Output "FINAL_WAKE0_TICK=$finalWake0Tick"
