# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-mode-history-overflow-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-mode-history-overflow-clear-probe-check.ps1' `
    -FailureLabel 'Mode-history overflow/clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$restartLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_LEN'
$restartHead = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_HEAD'
$restartOverflow = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_OVERFLOW'
$restartSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_SEQ'
$restartFirstSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_FIRST_SEQ'
$restartFirstPrev = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_FIRST_PREV'
$restartFirstNew = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_FIRST_NEW'
$restartFirstReason = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_FIRST_REASON'
$restartSecondSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_SECOND_SEQ'
$restartSecondPrev = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_SECOND_PREV'
$restartSecondNew = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_SECOND_NEW'
$restartSecondReason = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_SECOND_REASON'
if (
    $restartLen -ne 2 -or $restartHead -ne 2 -or $restartOverflow -ne 0 -or $restartSeq -ne 2 -or
    $restartFirstSeq -ne 1 -or $restartFirstPrev -ne 1 -or $restartFirstNew -ne 0 -or $restartFirstReason -ne 1 -or
    $restartSecondSeq -ne 2 -or $restartSecondPrev -ne 0 -or $restartSecondNew -ne 1 -or $restartSecondReason -ne 3
) {
    throw "Unexpected restart event state. restartLen=$restartLen restartHead=$restartHead restartOverflow=$restartOverflow restartSeq=$restartSeq first=$restartFirstSeq/$restartFirstPrev->$($restartFirstNew):$restartFirstReason second=$restartSecondSeq/$restartSecondPrev->$($restartSecondNew):$restartSecondReason"
}

Write-Output 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_MODE_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE_SOURCE=baremetal-qemu-mode-history-overflow-clear-probe-check.ps1'
Write-Output "RESTART_LEN=$restartLen"
Write-Output "RESTART_HEAD=$restartHead"
Write-Output "RESTART_OVERFLOW=$restartOverflow"
Write-Output "RESTART_SEQ=$restartSeq"
Write-Output "RESTART_FIRST_SEQ=$restartFirstSeq"
Write-Output "RESTART_FIRST_PAYLOAD=$restartFirstPrev->$($restartFirstNew):$restartFirstReason"
Write-Output "RESTART_SECOND_SEQ=$restartSecondSeq"
Write-Output "RESTART_SECOND_PAYLOAD=$restartSecondPrev->$($restartSecondNew):$restartSecondReason"
