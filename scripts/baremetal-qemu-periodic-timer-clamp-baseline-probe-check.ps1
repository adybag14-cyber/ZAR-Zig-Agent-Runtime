param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-periodic-timer-clamp-probe-check.ps1"
$nearMaxTick = [uint64]::MaxValue - 1
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
    Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_BASELINE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying periodic-timer-clamp probe failed with exit code $probeExitCode"
}

$taskId = Extract-IntValue -Text $probeText -Name 'TASK_ID'
$preScheduleTicks = Extract-IntValue -Text $probeText -Name 'PRE_SCHEDULE_TICKS'
$armTicks = Extract-IntValue -Text $probeText -Name 'ARM_TICKS'
$armTimerId = Extract-IntValue -Text $probeText -Name 'ARM_TIMER_ID'

if ($null -in @($taskId, $preScheduleTicks, $armTicks, $armTimerId)) {
    throw 'Missing expected baseline fields in periodic-timer-clamp probe output.'
}
if ($taskId -ne 1) { throw "Expected TASK_ID=1. got $taskId" }
if ($preScheduleTicks -ne $nearMaxTick) { throw "Expected PRE_SCHEDULE_TICKS=$nearMaxTick. got $preScheduleTicks" }
if ($armTicks -ne $maxTick) { throw "Expected ARM_TICKS=$maxTick. got $armTicks" }
if ($armTimerId -ne 1) { throw "Expected ARM_TIMER_ID=1. got $armTimerId" }

Write-Output 'BAREMETAL_QEMU_PERIODIC_TIMER_CLAMP_BASELINE_PROBE=pass'
Write-Output "TASK_ID=$taskId"
Write-Output "PRE_SCHEDULE_TICKS=$preScheduleTicks"
Write-Output "ARM_TICKS=$armTicks"
Write-Output "ARM_TIMER_ID=$armTimerId"
