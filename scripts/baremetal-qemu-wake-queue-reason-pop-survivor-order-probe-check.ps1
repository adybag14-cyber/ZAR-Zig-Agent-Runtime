# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-wake-queue-reason-pop-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_SURVIVOR_ORDER_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying wake-queue reason-pop probe failed with exit code $probeExitCode"
}

$postCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_POST_COUNT'
$postTask0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_POST_TASK0'
$postTask1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_POST_TASK1'
$postVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_POST_VECTOR0'
$postVector1 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_POST_VECTOR1'

if ($null -in @($postCount, $postTask0, $postTask1, $postVector0, $postVector1)) {
    throw 'Missing expected survivor-order fields in wake-queue reason-pop probe output.'
}
if ($postCount -ne 1) { throw "Expected POST_COUNT=1. got $postCount" }
if ($postTask0 -ne 1 -or $postTask1 -ne 0) {
    throw "Unexpected post-survivor task state: $postTask0,$postTask1"
}
if ($postVector0 -ne 0 -or $postVector1 -ne 0) {
    throw "Unexpected post-survivor vectors: $postVector0,$postVector1"
}

Write-Output 'BAREMETAL_QEMU_WAKE_QUEUE_REASON_POP_SURVIVOR_ORDER_PROBE=pass'
Write-Output "POST_COUNT=$postCount"
Write-Output "POST_TASK0=$postTask0"
Write-Output "POST_TASK1=$postTask1"
Write-Output "POST_VECTOR0=$postVector0"
Write-Output "POST_VECTOR1=$postVector1"
