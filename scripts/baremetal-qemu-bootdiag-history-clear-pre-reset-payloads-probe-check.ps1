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
    -SkippedReceipt 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PRE_RESET_PAYLOADS_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PRE_RESET_PAYLOADS_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-bootdiag-history-clear-probe-check.ps1' `
    -FailureLabel 'Bootdiag/history-clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$phase = Extract-IntValue -Text $outputText -Name 'PRE_RESET_PHASE'
$lastSeq = Extract-IntValue -Text $outputText -Name 'PRE_RESET_LAST_SEQ'
$lastTick = Extract-IntValue -Text $outputText -Name 'PRE_RESET_LAST_TICK'
$observedTick = Extract-IntValue -Text $outputText -Name 'PRE_RESET_OBSERVED_TICK'
$stack = Extract-IntValue -Text $outputText -Name 'PRE_RESET_STACK'
$phaseChanges = Extract-IntValue -Text $outputText -Name 'PRE_RESET_PHASE_CHANGES'

if ($phase -ne 1 -or $lastSeq -ne 3 -or $lastTick -ne 2 -or $observedTick -ne 3 -or $phaseChanges -ne 1 -or $stack -le 0) {
    throw "Unexpected pre-reset payloads. phase=$phase lastSeq=$lastSeq lastTick=$lastTick observedTick=$observedTick stack=$stack phaseChanges=$phaseChanges"
}

Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PRE_RESET_PAYLOADS_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_PRE_RESET_PAYLOADS_PROBE_SOURCE=baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
Write-Output "PRE_RESET_PHASE=$phase"
Write-Output "PRE_RESET_LAST_SEQ=$lastSeq"
Write-Output "PRE_RESET_LAST_TICK=$lastTick"
Write-Output "PRE_RESET_OBSERVED_TICK=$observedTick"
Write-Output "PRE_RESET_STACK=$stack"
Write-Output "PRE_RESET_PHASE_CHANGES=$phaseChanges"
