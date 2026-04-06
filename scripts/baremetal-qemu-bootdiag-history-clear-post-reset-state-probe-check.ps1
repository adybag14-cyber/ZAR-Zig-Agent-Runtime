# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_POST_RESET_STATE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_POST_RESET_STATE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-bootdiag-history-clear-probe-check.ps1' `
    -FailureLabel 'Bootdiag/history-clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$phase = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_PHASE'
$bootSeq = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_BOOT_SEQ'
$lastSeq = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_LAST_SEQ'
$lastTick = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_LAST_TICK'
$observedTick = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_OBSERVED_TICK'
$stack = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_STACK'
$phaseChanges = Extract-IntValue -Text $outputText -Name 'BOOTDIAG_PHASE_CHANGES'
$statusMode = Extract-IntValue -Text $outputText -Name 'STATUS_MODE_RESET'
$bootHistoryLen = Extract-IntValue -Text $outputText -Name 'BOOT_HISTORY_LEN'

if ($phase -ne 2 -or $bootSeq -ne 1 -or $lastSeq -ne 4 -or $lastTick -ne 3 -or $observedTick -ne 4 -or $stack -ne 0 -or $phaseChanges -ne 0 -or $statusMode -ne 1 -or $bootHistoryLen -ne 3) {
    throw "Unexpected post-reset state. phase=$phase bootSeq=$bootSeq lastSeq=$lastSeq lastTick=$lastTick observedTick=$observedTick stack=$stack phaseChanges=$phaseChanges statusMode=$statusMode bootHistoryLen=$bootHistoryLen"
}

Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_POST_RESET_STATE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_POST_RESET_STATE_PROBE_SOURCE=baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
Write-Output "BOOTDIAG_PHASE=$phase"
Write-Output "BOOTDIAG_BOOT_SEQ=$bootSeq"
Write-Output "BOOTDIAG_LAST_SEQ=$lastSeq"
Write-Output "BOOTDIAG_LAST_TICK=$lastTick"
Write-Output "BOOTDIAG_OBSERVED_TICK=$observedTick"
Write-Output "BOOTDIAG_STACK=$stack"
Write-Output "BOOTDIAG_PHASE_CHANGES=$phaseChanges"
Write-Output "STATUS_MODE_RESET=$statusMode"
Write-Output "BOOT_HISTORY_LEN=$bootHistoryLen"
