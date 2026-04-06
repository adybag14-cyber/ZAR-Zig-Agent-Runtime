# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-health-history-overflow-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_OVERFLOW_WINDOW_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_OVERFLOW_WINDOW_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-health-history-overflow-clear-probe-check.ps1' `
    -FailureLabel 'Health-history overflow/clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$overflowCount = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_OVERFLOW_COUNT'
$firstSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_FIRST_SEQ'
$lastSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_LAST_SEQ'
if ($overflowCount -ne 7 -or $firstSeq -ne 8 -or $lastSeq -ne 71) {
    throw "Unexpected overflow window. overflowCount=$overflowCount firstSeq=$firstSeq lastSeq=$lastSeq"
}

Write-Output 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_OVERFLOW_WINDOW_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_OVERFLOW_WINDOW_PROBE_SOURCE=baremetal-qemu-health-history-overflow-clear-probe-check.ps1'
Write-Output "OVERFLOW_COUNT=$overflowCount"
Write-Output "FIRST_SEQ=$firstSeq"
Write-Output "LAST_SEQ=$lastSeq"
