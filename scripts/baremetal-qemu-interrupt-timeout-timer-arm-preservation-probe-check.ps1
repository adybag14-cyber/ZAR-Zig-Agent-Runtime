param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-timer-probe-check.ps1"

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
$probeOutput | Write-Output
if ($probeText -match '(?m)^BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_PROBE=skipped\r?$') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_ARM_PRESERVATION_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_ARM_PRESERVATION_PROBE_SOURCE=baremetal-qemu-interrupt-timeout-timer-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout timer probe failed with exit code $probeExitCode"
}

$armedTicks = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_PROBE_ARMED_TICKS'
$armedWaitTimeout = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_PROBE_ARMED_WAIT_TIMEOUT'

if ($null -in @($armedTicks, $armedWaitTimeout)) {
    throw 'Missing expected interrupt-timeout timer arm-preservation fields in probe output.'
}
if ($armedTicks -lt 1) { throw "Expected ARMED_TICKS >= 1, got $armedTicks" }
if ($armedWaitTimeout -ne ($armedTicks + 1)) { throw "Expected ARMED_WAIT_TIMEOUT = ARMED_TICKS + 1. timeout=$armedWaitTimeout ticks=$armedTicks" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_ARM_PRESERVATION_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_TIMER_ARM_PRESERVATION_PROBE_SOURCE=baremetal-qemu-interrupt-timeout-timer-probe-check.ps1'
Write-Output "ARMED_TICKS=$armedTicks"
Write-Output "ARMED_WAIT_TIMEOUT=$armedWaitTimeout"
