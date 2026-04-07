# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild,
    [int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'baremetal-qemu-wrapper-common.ps1')
$probe = Join-Path $PSScriptRoot 'baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$invoke = @{ TimeoutSeconds = $TimeoutSeconds }
$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-command-history-overflow-clear-probe-check.ps1' `
    -FailureLabel 'Command-history overflow/clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$clearLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_LEN'
$clearFirstSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_SEQ'
$clearFirstOpcode = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_OPCODE'
$clearFirstResult = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_CLEAR_FIRST_RESULT'
$healthPreserveLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_HEALTH_PRESERVE_LEN'
if ($clearLen -ne 1 -or $clearFirstSeq -ne 5 -or $clearFirstOpcode -ne 19 -or $clearFirstResult -ne 0 -or $healthPreserveLen -ne 6) {
    throw "Unexpected clear-event state. clearLen=$clearLen clearFirstSeq=$clearFirstSeq clearFirstOpcode=$clearFirstOpcode clearFirstResult=$clearFirstResult healthPreserveLen=$healthPreserveLen"
}

Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_CLEAR_EVENT_PROBE_SOURCE=baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
Write-Output "CLEAR_LEN=$clearLen"
Write-Output "CLEAR_FIRST_SEQ=$clearFirstSeq"
Write-Output "CLEAR_FIRST_OPCODE=$clearFirstOpcode"
Write-Output "CLEAR_FIRST_RESULT=$clearFirstResult"
Write-Output "HEALTH_PRESERVE_LEN=$healthPreserveLen"

