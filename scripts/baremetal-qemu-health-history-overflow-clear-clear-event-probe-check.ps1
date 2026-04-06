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
    -SkippedReceipt 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-health-history-overflow-clear-probe-check.ps1' `
    -FailureLabel 'Health-history overflow/clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$clearLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_LEN'
$clearFirstSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_SEQ'
$clearFirstCode = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_CODE'
$clearFirstMode = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_MODE'
$clearFirstTick = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_TICK'
$clearFirstAck = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_ACK'
if ($clearLen -ne 1 -or $clearFirstSeq -ne 1 -or $clearFirstCode -ne 200 -or $clearFirstMode -ne 1 -or $clearFirstTick -ne 6 -or $clearFirstAck -ne 6) {
    throw "Unexpected clear-event payload. clearLen=$clearLen clearFirstSeq=$clearFirstSeq clearFirstCode=$clearFirstCode clearFirstMode=$clearFirstMode clearFirstTick=$clearFirstTick clearFirstAck=$clearFirstAck"
}

Write-Output 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE_SOURCE=baremetal-qemu-health-history-overflow-clear-probe-check.ps1'
Write-Output "CLEAR_LEN=$clearLen"
Write-Output "CLEAR_FIRST_SEQ=$clearFirstSeq"
Write-Output "CLEAR_FIRST_CODE=$clearFirstCode"
Write-Output "CLEAR_FIRST_MODE=$clearFirstMode"
Write-Output "CLEAR_FIRST_TICK=$clearFirstTick"
Write-Output "CLEAR_FIRST_ACK=$clearFirstAck"
