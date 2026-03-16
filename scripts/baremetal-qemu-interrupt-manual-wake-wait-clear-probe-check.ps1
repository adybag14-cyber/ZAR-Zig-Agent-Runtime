# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-manual-wake-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Name) + '=(-?\d+)\r?$')
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$probeOutput = if ($SkipBuild) { & $probe -SkipBuild 2>&1 } else { & $probe 2>&1 }
$probeExitCode = $LASTEXITCODE
$probeText = ($probeOutput | Out-String)
if ($probeText -match '(?m)^BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE=skipped\r?$') {
    if ($probeText) { Write-Output $probeText.TrimEnd() }
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_WAIT_CLEAR_PROBE=skipped'
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_WAIT_CLEAR_PROBE_SOURCE=baremetal-qemu-interrupt-manual-wake-probe-check.ps1'
    exit 0
}
if ($probeExitCode -ne 0) {
    if ($probeText) { Write-Output $probeText.TrimEnd() }
    throw "Underlying interrupt-manual-wake probe failed with exit code $probeExitCode"
}
$waitKind0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_WAIT_KIND0'
$waitVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_WAIT_VECTOR0'
$waitTimeout0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_WAIT_TIMEOUT0'
$timerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_PROBE_TIMER_ENTRY_COUNT'
if ($null -in @($waitKind0,$waitVector0,$waitTimeout0,$timerEntryCount)) {
    throw 'Missing expected interrupt-manual-wake wait-clear fields in probe output.'
}
if ($waitKind0 -ne 0) { throw "Expected WAIT_KIND0=0. got $waitKind0" }
if ($waitVector0 -ne 0) { throw "Expected WAIT_VECTOR0=0. got $waitVector0" }
if ($waitTimeout0 -ne 0) { throw "Expected WAIT_TIMEOUT0=0. got $waitTimeout0" }
if ($timerEntryCount -ne 0) { throw "Expected TIMER_ENTRY_COUNT=0. got $timerEntryCount" }
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_WAIT_CLEAR_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_INTERRUPT_MANUAL_WAKE_WAIT_CLEAR_PROBE_SOURCE=baremetal-qemu-interrupt-manual-wake-probe-check.ps1'
Write-Output "WAIT_KIND0=$waitKind0"
Write-Output "WAIT_VECTOR0=$waitVector0"
Write-Output "WAIT_TIMEOUT0=$waitTimeout0"
Write-Output "TIMER_ENTRY_COUNT=$timerEntryCount"
