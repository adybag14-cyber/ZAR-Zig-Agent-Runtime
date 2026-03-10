param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-timer-pressure-probe-check.ps1"
$skipToken = 'BAREMETAL_QEMU_TIMER_PRESSURE_REUSE_NEXT_FIRE_PROBE=skipped'

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
if ($probeText -match 'BAREMETAL_QEMU_TIMER_PRESSURE_PROBE=skipped') {
    Write-Output $skipToken
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying timer-pressure probe failed with exit code $probeExitCode"
}

$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
$reuseTaskState = Extract-IntValue -Text $probeText -Name 'REUSE_TASK_STATE'
$reuseNextFire = Extract-IntValue -Text $probeText -Name 'REUSE_NEXT_FIRE'
if ($null -in @($ticks,$reuseTaskState,$reuseNextFire)) {
    throw 'Missing timer-pressure reuse-next-fire fields.'
}
if ($reuseTaskState -ne 6) { throw "Expected REUSE_TASK_STATE=6. got $reuseTaskState" }
if ($reuseNextFire -le $ticks) { throw "Expected REUSE_NEXT_FIRE>$ticks. got $reuseNextFire" }

Write-Output 'BAREMETAL_QEMU_TIMER_PRESSURE_REUSE_NEXT_FIRE_PROBE=pass'
Write-Output "TICKS=$ticks"
Write-Output "REUSE_TASK_STATE=$reuseTaskState"
Write-Output "REUSE_NEXT_FIRE=$reuseNextFire"
