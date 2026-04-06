# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 30,
    [int] $GdbPort = 0
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-mode-boot-phase-history-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
if ($GdbPort -gt 0) { $invoke.GdbPort = $GdbPort }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_PRE_SEMANTICS_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_PRE_SEMANTICS_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-mode-boot-phase-history-clear-probe-check.ps1' `
    -FailureLabel 'Mode/boot-phase history clear' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text


$expected = [ordered]@{
    'PRE_MODE_LEN' = 3
    'PRE_MODE_LAST_SEQ' = 3
    'PRE_MODE2_PREV' = 1
    'PRE_MODE2_NEW' = 255
    'PRE_MODE2_REASON' = 2
    'PRE_BOOT_LEN' = 3
    'PRE_BOOT_LAST_SEQ' = 3
    'PRE_BOOT2_PREV' = 2
    'PRE_BOOT2_NEW' = 255
    'PRE_BOOT2_REASON' = 3
}
foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $outputText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_PRE_SEMANTICS_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_PRE_SEMANTICS_PROBE_SOURCE=baremetal-qemu-mode-boot-phase-history-clear-probe-check.ps1'
foreach ($entry in $expected.GetEnumerator()) { Write-Output ("{0}={1}" -f $entry.Key, $entry.Value) }
