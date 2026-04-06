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
    -SkippedReceipt 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-command-history-overflow-clear-probe-check.ps1' `
    -FailureLabel 'Command-history overflow/clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$firstArg0 = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_FIRST_ARG0'
$lastArg0 = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_PROBE_LAST_ARG0'
if ($firstArg0 -ne 103 -or $lastArg0 -ne 134) {
    throw "Unexpected overflow payloads. firstArg0=$firstArg0 lastArg0=$lastArg0"
}

Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_COMMAND_HISTORY_OVERFLOW_CLEAR_OVERFLOW_PAYLOADS_PROBE_SOURCE=baremetal-qemu-command-history-overflow-clear-probe-check.ps1'
Write-Output "FIRST_ARG0=$firstArg0"
Write-Output "LAST_ARG0=$lastArg0"
