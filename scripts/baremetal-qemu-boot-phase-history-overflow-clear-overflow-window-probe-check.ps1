# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-boot-phase-history-overflow-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_OVERFLOW_WINDOW_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_OVERFLOW_WINDOW_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-boot-phase-history-overflow-clear-probe-check.ps1' `
    -FailureLabel 'Boot-phase-history overflow/clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$overflowCount = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_PROBE_OVERFLOW_COUNT'
$overflowHead = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_PROBE_OVERFLOW_HEAD'
$firstSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_PROBE_FIRST_SEQ'
$lastSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_PROBE_LAST_SEQ'
if ($overflowCount -ne 2 -or $overflowHead -ne 2 -or $firstSeq -ne 3 -or $lastSeq -ne 66) {
    throw "Unexpected overflow window. overflow=$overflowCount head=$overflowHead first=$firstSeq last=$lastSeq"
}

Write-Output 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_OVERFLOW_WINDOW_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_BOOT_PHASE_HISTORY_OVERFLOW_CLEAR_OVERFLOW_WINDOW_PROBE_SOURCE=baremetal-qemu-boot-phase-history-overflow-clear-probe-check.ps1'
Write-Output "OVERFLOW_COUNT=$overflowCount"
Write-Output "OVERFLOW_HEAD=$overflowHead"
Write-Output "FIRST_SEQ=$firstSeq"
Write-Output "LAST_SEQ=$lastSeq"
