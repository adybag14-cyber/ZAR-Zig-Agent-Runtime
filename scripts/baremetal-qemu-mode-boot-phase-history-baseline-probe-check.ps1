# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-mode-boot-phase-history-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

function Extract-IntValue {
    param([string] $Text, [string] $Name)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=(-?\\d+)\\r?$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return [int64]::Parse($match.Groups[1].Value)
}

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
if ($GdbPort -gt 0) { $invoke.GdbPort = $GdbPort }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_BASELINE_PROBE' `
    -FailureLabel 'mode/boot-phase history' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -InvokeArgs $invoke
$probeText = $probeState.Text

$expected = [ordered]@{
    'ACK' = 71
    'LAST_OPCODE' = 4
    'LAST_RESULT' = 0
    'MODE_HISTORY_LEN' = 64
    'MODE_HISTORY_OVERFLOW' = 2
    'MODE_HISTORY_HEAD' = 2
    'BOOT_HISTORY_LEN' = 64
    'BOOT_HISTORY_OVERFLOW' = 2
    'BOOT_HISTORY_HEAD' = 2
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
if ($null -eq $ticks) { throw 'Missing output value for TICKS' }
if ($ticks -lt 66) { throw "Unexpected TICKS: got $ticks expected at least 66" }

Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_BASELINE_PROBE=pass'
Write-Output 'ACK=71'
Write-Output 'LAST_OPCODE=4'
Write-Output 'LAST_RESULT=0'
Write-Output 'MODE_HISTORY_LEN=64'
Write-Output 'MODE_HISTORY_OVERFLOW=2'
Write-Output 'MODE_HISTORY_HEAD=2'
Write-Output 'BOOT_HISTORY_LEN=64'
Write-Output 'BOOT_HISTORY_OVERFLOW=2'
Write-Output 'BOOT_HISTORY_HEAD=2'
Write-Output "TICKS=$ticks"
