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
    -SkippedReceipt 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_BOOT_SEMANTICS_PROBE' `
    -FailureLabel 'mode/boot-phase history' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -InvokeArgs $invoke
$probeText = $probeState.Text

$expected = [ordered]@{
    'BOOT_SEMANTIC_LEN' = 3
    'BOOT_SEM0_PREV' = 2
    'BOOT_SEM0_NEW' = 1
    'BOOT_SEM0_REASON' = 1
    'BOOT_SEM1_PREV' = 1
    'BOOT_SEM1_NEW' = 2
    'BOOT_SEM1_REASON' = 2
    'BOOT_SEM2_PREV' = 2
    'BOOT_SEM2_NEW' = 255
    'BOOT_SEM2_REASON' = 3
}

foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $probeText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_BOOT_SEMANTICS_PROBE=pass'
Write-Output 'BOOT_SEMANTIC_LEN=3'
Write-Output 'BOOT_SEM0_PREV=2'
Write-Output 'BOOT_SEM0_NEW=1'
Write-Output 'BOOT_SEM0_REASON=1'
Write-Output 'BOOT_SEM1_PREV=1'
Write-Output 'BOOT_SEM1_NEW=2'
Write-Output 'BOOT_SEM1_REASON=2'
Write-Output 'BOOT_SEM2_PREV=2'
Write-Output 'BOOT_SEM2_NEW=255'
Write-Output 'BOOT_SEM2_REASON=3'
