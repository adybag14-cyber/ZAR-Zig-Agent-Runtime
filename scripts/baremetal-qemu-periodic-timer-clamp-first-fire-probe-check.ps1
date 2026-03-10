param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-clamp-probe-check.ps1"
$maxTick = [uint64]::MaxValue

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [decimal]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_FIRST_FIRE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying periodic-timer-clamp probe failed with exit code $probeExitCode"
}

$fireTicks = Extract-IntValue -Text $probeText -Name 'FIRE_TICKS'
$fireCount = Extract-IntValue -Text $probeText -Name 'FIRE_COUNT'
$fireLastTick = Extract-IntValue -Text $probeText -Name 'FIRE_LAST_TICK'
$wake0Tick = Extract-IntValue -Text $probeText -Name 'WAKE0_TICK'

if ($null -in @($fireTicks, $fireCount, $fireLastTick, $wake0Tick)) {
    throw 'Missing expected first-fire fields in periodic-timer-clamp probe output.'
}
if ($fireTicks -ne 0) { throw "Expected FIRE_TICKS=0. got $fireTicks" }
if ($fireCount -ne 1) { throw "Expected FIRE_COUNT=1. got $fireCount" }
if ($fireLastTick -ne $maxTick) { throw "Expected FIRE_LAST_TICK=$maxTick. got $fireLastTick" }
if ($wake0Tick -ne $maxTick) { throw "Expected WAKE0_TICK=$maxTick. got $wake0Tick" }

Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_FIRST_FIRE_PROBE=pass'
Write-Output "FIRE_TICKS=$fireTicks"
Write-Output "FIRE_COUNT=$fireCount"
Write-Output "FIRE_LAST_TICK=$fireLastTick"
Write-Output "WAKE0_TICK=$wake0Tick"
