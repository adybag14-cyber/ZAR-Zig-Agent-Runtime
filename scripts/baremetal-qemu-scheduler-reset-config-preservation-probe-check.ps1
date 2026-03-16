# SPDX-License-Identifier: GPL-2.0-only
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
    Write-Output "BAREMETAL_QEMU_SCHEDULER_RESET_CONFIG_PRESERVATION_PROBE=skipped"
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying scheduler-reset-mixed-state probe failed with exit code $probeExitCode"
}

$preNextTimerId = Extract-IntValue -Text $probeText -Name 'PRE_NEXT_TIMER_ID'
$preQuantum = Extract-IntValue -Text $probeText -Name 'PRE_QUANTUM'
$postNextTimerId = Extract-IntValue -Text $probeText -Name 'POST_NEXT_TIMER_ID'
$postQuantum = Extract-IntValue -Text $probeText -Name 'POST_QUANTUM'
$rearmTimerId = Extract-IntValue -Text $probeText -Name 'REARM_TIMER_ID'
$rearmNextTimerId = Extract-IntValue -Text $probeText -Name 'REARM_NEXT_TIMER_ID'

if ($null -in @($preNextTimerId, $preQuantum, $postNextTimerId, $postQuantum, $rearmTimerId, $rearmNextTimerId)) {
    throw 'Missing expected scheduler-reset config-preservation fields in probe output.'
}
if ($preQuantum -ne $postQuantum) {
    throw "Expected timer quantum to survive scheduler reset. pre=$preQuantum post=$postQuantum"
}
if ($preNextTimerId -ne $postNextTimerId) {
    throw "Expected next_timer_id to survive scheduler reset. pre=$preNextTimerId post=$postNextTimerId"
}
if ($rearmTimerId -ne $postNextTimerId) {
    throw "Expected first post-reset rearm to reuse preserved next_timer_id=$postNextTimerId. got $rearmTimerId"
}
if ($rearmNextTimerId -ne ($rearmTimerId + 1)) {
    throw "Expected next_timer_id to advance by one after post-reset rearm. timer_id=$rearmTimerId next=$rearmNextTimerId"
}

Write-Output 'BAREMETAL_QEMU_SCHEDULER_RESET_CONFIG_PRESERVATION_PROBE=pass'
Write-Output "PRE_NEXT_TIMER_ID=$preNextTimerId"
Write-Output "POST_NEXT_TIMER_ID=$postNextTimerId"
Write-Output "PRE_QUANTUM=$preQuantum"
Write-Output "POST_QUANTUM=$postQuantum"
Write-Output "REARM_TIMER_ID=$rearmTimerId"
Write-Output "REARM_NEXT_TIMER_ID=$rearmNextTimerId"
