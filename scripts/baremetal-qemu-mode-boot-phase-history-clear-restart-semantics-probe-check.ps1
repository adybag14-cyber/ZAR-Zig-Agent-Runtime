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
    -SkippedReceipt 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_RESTART_SEMANTICS_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_RESTART_SEMANTICS_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-mode-boot-phase-history-clear-probe-check.ps1' `
    -FailureLabel 'Mode/boot-phase history clear' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text


$expected = [ordered]@{
    'RESET_BOOT0_SEQ' = 1
    'RESET_BOOT0_PREV' = 2
    'RESET_BOOT0_NEW' = 1
    'RESET_BOOT0_REASON' = 1
    'ACK' = 7
    'LAST_OPCODE' = 4
    'LAST_RESULT' = 0
    'RESET_MODE_LEN' = 2
    'RESET_MODE_HEAD' = 2
    'RESET_MODE_OVERFLOW' = 0
    'RESET_MODE_SEQ' = 2
    'RESET_MODE0_SEQ' = 1
    'RESET_MODE0_PREV' = 1
    'RESET_MODE0_NEW' = 0
    'RESET_MODE0_REASON' = 1
    'RESET_MODE1_SEQ' = 2
    'RESET_MODE1_PREV' = 0
    'RESET_MODE1_NEW' = 1
    'RESET_MODE1_REASON' = 3
    'RESET_BOOT_LEN' = 2
    'RESET_BOOT_HEAD' = 2
    'RESET_BOOT_OVERFLOW' = 0
    'RESET_BOOT_SEQ' = 2
    'RESET_BOOT1_SEQ' = 2
    'RESET_BOOT1_PREV' = 1
    'RESET_BOOT1_NEW' = 2
    'RESET_BOOT1_REASON' = 2
}
foreach ($entry in $expected.GetEnumerator()) {
    $actual = Extract-IntValue -Text $outputText -Name $entry.Key
    if ($null -eq $actual) { throw "Missing output value for $($entry.Key)" }
    if ($actual -ne $entry.Value) { throw "Unexpected $($entry.Key): got $actual expected $($entry.Value)" }
}
$ticks = Extract-IntValue -Text $outputText -Name 'TICKS'
if ($null -eq $ticks) { throw 'Missing output value for TICKS' }
if ($ticks -lt 7) { throw "Unexpected TICKS: got $ticks expected at least 7" }

Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_RESTART_SEMANTICS_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MODE_BOOT_PHASE_HISTORY_CLEAR_RESTART_SEMANTICS_PROBE_SOURCE=baremetal-qemu-mode-boot-phase-history-clear-probe-check.ps1'
foreach ($entry in $expected.GetEnumerator()) { Write-Output ("{0}={1}" -f $entry.Key, $entry.Value) }
Write-Output ("TICKS={0}" -f $ticks)
