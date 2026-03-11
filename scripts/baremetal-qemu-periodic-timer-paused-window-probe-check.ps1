param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_PAUSED_WINDOW_PROBE_CHECK=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying periodic-timer probe failed with exit code $probeExitCode"
}

$pausedFireCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_PAUSED_FIRE_COUNT'
$pausedDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_PAUSED_DISPATCH_COUNT'
$pausedWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_PAUSED_WAKE_COUNT'
$pausedTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_PAUSED_TICK'
$firstFireCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_FIRST_FIRE_COUNT'
$firstDispatchCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_FIRST_DISPATCH_COUNT'
$firstWakeCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_FIRST_WAKE_COUNT'
$firstLastFireTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_PERIODIC_TIMER_PROBE_FIRST_LAST_FIRE_TICK'
if ($null -in @($pausedFireCount, $pausedDispatchCount, $pausedWakeCount, $pausedTick, $firstFireCount, $firstDispatchCount, $firstWakeCount, $firstLastFireTick)) { throw 'Missing periodic-timer paused-window fields.' }
if ($pausedFireCount -ne $firstFireCount) { throw "Expected PAUSED_FIRE_COUNT to stay at $firstFireCount. got $pausedFireCount" }
if ($pausedDispatchCount -ne $firstDispatchCount) { throw "Expected PAUSED_DISPATCH_COUNT to stay at $firstDispatchCount. got $pausedDispatchCount" }
if ($pausedWakeCount -ne $firstWakeCount) { throw "Expected PAUSED_WAKE_COUNT to stay at $firstWakeCount. got $pausedWakeCount" }
if ($pausedTick -le $firstLastFireTick) { throw "Expected PAUSED_TICK>$firstLastFireTick. got $pausedTick" }
Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_PAUSED_WINDOW_PROBE=pass'
Write-Output "PAUSED_FIRE_COUNT=$pausedFireCount"
Write-Output "PAUSED_DISPATCH_COUNT=$pausedDispatchCount"
Write-Output "PAUSED_WAKE_COUNT=$pausedWakeCount"
Write-Output "PAUSED_TICK=$pausedTick"
Write-Output "FIRST_LAST_FIRE_TICK=$firstLastFireTick"
