# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-mode-boot-phase-setter-probe-check.ps1"
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
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MODE_BOOT_PHASE_SETTER_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_MODE_BOOT_PHASE_SETTER_BOOT_HISTORY_PROBE' `
    -FailureLabel 'mode/boot-phase setter' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -InvokeArgs $invoke
$probeText = $probeState.Text

$expected = @{
    'BOOT_PHASE_CHANGES' = 1
    'BOOT_HISTORY_LEN' = 1
    'BOOT0_SEQ' = 1
    'BOOT0_PREV' = 2
    'BOOT0_NEW' = 1
    'BOOT0_REASON' = 1
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_SETTER_BOOT_HISTORY_PROBE=pass'
Write-Output 'BOOT_PHASE_CHANGES=1'
Write-Output 'BOOT_HISTORY_LEN=1'
Write-Output 'BOOT0_SEQ=1'
Write-Output 'BOOT0_PREV=2'
Write-Output 'BOOT0_NEW=1'
Write-Output 'BOOT0_REASON=1'
