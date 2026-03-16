# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-masked-interrupt-timeout-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_WAIT_PRESERVE_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying masked interrupt-timeout probe failed with exit code $probeExitCode"
}

$armedTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_ARMED_TICKS'
$armedWaitTimeout = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_ARMED_WAIT_TIMEOUT'
$preWakeTick = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_PRE_WAKE_TICK'
$task0StateAfterInterrupt = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_PROBE_TASK0_STATE_AFTER_INTERRUPT'
if ($null -in @($armedTicks, $armedWaitTimeout, $preWakeTick, $task0StateAfterInterrupt)) {
    throw 'Missing wait-preserve fields in probe output.'
}
if ($task0StateAfterInterrupt -ne 6) { throw "Expected waiting state (6) after masked interrupt. got $task0StateAfterInterrupt" }
if ($armedTicks -lt 1) { throw "Expected armed ticks to be positive. got $armedTicks" }
if ($armedWaitTimeout -ne ($armedTicks + 2)) { throw "Expected armed wait timeout to remain armedTicks+2. armed=$armedTicks timeout=$armedWaitTimeout" }
if ($preWakeTick -ge $armedWaitTimeout) { throw "Expected pre-wake tick to remain before timeout deadline. preWake=$preWakeTick timeout=$armedWaitTimeout" }

Write-Output 'BAREMETAL_QEMU_MASKED_INTERRUPT_TIMEOUT_WAIT_PRESERVE_PROBE=pass'
Write-Output "ARMED_TICKS=$armedTicks"
Write-Output "ARMED_WAIT_TIMEOUT=$armedWaitTimeout"
Write-Output "PRE_WAKE_TICK=$preWakeTick"
Write-Output "TASK0_STATE_AFTER_INTERRUPT=$task0StateAfterInterrupt"
