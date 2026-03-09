param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-scheduler-reset-mixed-state-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_SCHEDULER_RESET_MIXED_STATE_PROBE=skipped') {
    Write-Output "BAREMETAL_QEMU_SCHEDULER_RESET_WAKE_CLEAR_PROBE=skipped"
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying scheduler-reset-mixed-state probe failed with exit code $probeExitCode"
}

$preWakeCount = Extract-IntValue -Text $probeText -Name 'PRE_WAKE_COUNT'
$postWakeCount = Extract-IntValue -Text $probeText -Name 'POST_WAKE_COUNT'
$afterIdleWakeCount = Extract-IntValue -Text $probeText -Name 'AFTER_IDLE_WAKE_COUNT'

if ($null -in @($preWakeCount, $postWakeCount, $afterIdleWakeCount)) {
    throw 'Missing expected scheduler-reset wake-clear fields in probe output.'
}
if ($preWakeCount -le 0) {
    throw "Expected stale queued wakes before scheduler reset. got $preWakeCount"
}
if ($postWakeCount -ne 0) {
    throw "Expected scheduler reset to clear queued wakes immediately. got $postWakeCount"
}
if ($afterIdleWakeCount -ne 0) {
    throw "Expected no stale wakes to reappear after idle ticks post-reset. got $afterIdleWakeCount"
}

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_WAKE_CLEAR_PROBE=pass'
Write-Output "PRE_WAKE_COUNT=$preWakeCount"
Write-Output "POST_WAKE_COUNT=$postWakeCount"
Write-Output "AFTER_IDLE_WAKE_COUNT=$afterIdleWakeCount"
