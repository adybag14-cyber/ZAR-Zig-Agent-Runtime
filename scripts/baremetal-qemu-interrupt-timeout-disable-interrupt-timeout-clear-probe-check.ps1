# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$probe = Join-Path $PSScriptRoot "baremetal-qemu-interrupt-timeout-disable-interrupt-probe-check.ps1"

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
if ($probeText -match 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE=skipped') {
    Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_TIMEOUT_CLEAR_PROBE=skipped'
    exit 0
}
if ($probeExitCode -ne 0) {
    throw "Underlying interrupt-timeout disable-interrupt probe failed with exit code $probeExitCode"
}

$disabledWaitKind0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_WAIT_KIND0'
$disabledWaitVector0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_WAIT_VECTOR0'
$disabledWaitTimeout0 = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_WAIT_TIMEOUT0'
$disabledTimerEntryCount = Extract-IntValue -Text $probeText -Name 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_PROBE_DISABLED_TIMER_ENTRY_COUNT'
if ($null -in @($disabledWaitKind0, $disabledWaitVector0, $disabledWaitTimeout0, $disabledTimerEntryCount)) {
    throw 'Missing timeout-clear fields in probe output.'
}
if ($disabledWaitKind0 -ne 0) { throw "Expected wait kind none (0) after interrupt wake. got $disabledWaitKind0" }
if ($disabledWaitVector0 -ne 0) { throw "Expected cleared interrupt vector after wake. got $disabledWaitVector0" }
if ($disabledWaitTimeout0 -ne 0) { throw "Expected cleared timeout arm after wake. got $disabledWaitTimeout0" }
if ($disabledTimerEntryCount -ne 0) { throw "Expected no timer table entry after wake. got $disabledTimerEntryCount" }

Write-Output 'BAREMETAL_QEMU_INTERRUPT_TIMEOUT_DISABLE_INTERRUPT_TIMEOUT_CLEAR_PROBE=pass'
Write-Output "DISABLED_WAIT_KIND0=$disabledWaitKind0"
Write-Output "DISABLED_WAIT_VECTOR0=$disabledWaitVector0"
Write-Output "DISABLED_WAIT_TIMEOUT0=$disabledWaitTimeout0"
Write-Output "DISABLED_TIMER_ENTRY_COUNT=$disabledTimerEntryCount"
