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
    -SkippedReceipt 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-command-history-overflow-clear-probe-check.ps1' `
    -FailureLabel 'Command-history overflow/clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$restartLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_LEN'
$restartSeq = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_SEQ'
$restartOpcode = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_OPCODE'
$restartResult = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_RESULT'
$restartArg0 = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_RESTART_ARG0'
if ($restartLen -ne 2 -or $restartSeq -ne 6 -or $restartOpcode -ne 20 -or $restartResult -ne 0 -or $restartArg0 -ne 0) {
    throw "Unexpected restart-event state. restartLen=$restartLen restartSeq=$restartSeq restartOpcode=$restartOpcode restartResult=$restartResult restartArg0=$restartArg0"
}

Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_RESTART_EVENT_PROBE_SOURCE=baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
Write-Output "RESTART_LEN=$restartLen"
Write-Output "RESTART_SEQ=$restartSeq"
Write-Output "RESTART_OPCODE=$restartOpcode"
Write-Output "RESTART_RESULT=$restartResult"
Write-Output "RESTART_ARG0=$restartArg0"
