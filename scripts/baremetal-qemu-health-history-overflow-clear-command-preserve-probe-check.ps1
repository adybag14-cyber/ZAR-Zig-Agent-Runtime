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
    -SkippedReceipt 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_COMMAND_PRESERVE_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_COMMAND_PRESERVE_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-health-history-overflow-clear-probe-check.ps1' `
    -FailureLabel 'Health-history overflow/clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$commandPreserveLen = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_COMMAND_PRESERVE_LEN'
$commandTailOpcode = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_COMMAND_TAIL_OPCODE'
$commandTailResult = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_COMMAND_TAIL_RESULT'
$commandTailArg0 = Extract-IntValue -Text $outputText -Name 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_PROBE_COMMAND_TAIL_ARG0'
if ($commandPreserveLen -ne 2 -or $commandTailOpcode -ne 20 -or $commandTailResult -ne 0 -or $commandTailArg0 -ne 0) {
    throw "Unexpected preserved command-history tail. commandPreserveLen=$commandPreserveLen commandTailOpcode=$commandTailOpcode commandTailResult=$commandTailResult commandTailArg0=$commandTailArg0"
}

Write-Output 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_COMMAND_PRESERVE_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_HEALTH_HISTORY_OVERFLOW_CLEAR_COMMAND_PRESERVE_PROBE_SOURCE=baremetal-qemu-health-history-overflow-clear-probe-check.ps1'
Write-Output "COMMAND_PRESERVE_LEN=$commandPreserveLen"
Write-Output "COMMAND_TAIL_OPCODE=$commandTailOpcode"
Write-Output "COMMAND_TAIL_RESULT=$commandTailResult"
Write-Output "COMMAND_TAIL_ARG0=$commandTailArg0"
