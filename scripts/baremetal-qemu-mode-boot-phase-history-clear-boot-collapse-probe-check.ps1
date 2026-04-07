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
    -SkippedReceipt 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_BOOT_COLLAPSE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_BOOT_COLLAPSE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-mode-boot-phase-history-clear-probe-check.ps1' `
    -FailureLabel 'Mode/boot-phase history clear' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text


$expected = [ordered]@{
    'POST_CLEAR_BOOT_LEN' = 0
    'POST_CLEAR_BOOT_HEAD' = 0
    'POST_CLEAR_BOOT_OVERFLOW' = 0
    'POST_CLEAR_BOOT_SEQ' = 0
}
foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $outputText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}

Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_BOOT_COLLAPSE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_BOOT_COLLAPSE_PROBE_SOURCE=baremetal-qemu-mode-boot-phase-history-clear-probe-check.ps1'
foreach ($entry in $expected.GetEnumerator()) { Write-Output ("{0}={1}" -f $entry.Key, $entry.Value) }
