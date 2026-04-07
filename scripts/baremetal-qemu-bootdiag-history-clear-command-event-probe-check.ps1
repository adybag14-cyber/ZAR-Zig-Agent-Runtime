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
    -SkippedReceipt 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_COMMAND_EVENT_PROBE' `
    -SkippedSourceReceipt 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_COMMAND_EVENT_PROBE_SOURCE' `
    -SkippedSourceValue 'baremetal-qemu-bootdiag-history-clear-probe-check.ps1' `
    -FailureLabel 'Bootdiag/history-clear' `
    -EchoOnSuccess:$false `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true `
    -TrimEchoText:$true `
    -EmitSkippedSourceReceipt:$true `
    -InvokeArgs $invoke
$outputText = $probeState.Text

$ack2 = Extract-IntValue -Text $outputText -Name 'ACK2'
$lastOpcode2 = Extract-IntValue -Text $outputText -Name 'LAST_OPCODE2'
$lastResult2 = Extract-IntValue -Text $outputText -Name 'LAST_RESULT2'
$cmdHistoryLen2 = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_LEN2'
$cmdHistoryHead2 = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_HEAD2'
$cmdHistoryOverflow2 = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_OVERFLOW2'
$firstSeq = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_FIRST_SEQ'
$firstOpcode = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_FIRST_OPCODE'
$firstResult = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_FIRST_RESULT'
$firstTick = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_FIRST_TICK'
$firstArg0 = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_FIRST_ARG0'
$firstArg1 = Extract-IntValue -Text $outputText -Name 'CMD_HISTORY_FIRST_ARG1'
$healthHistoryLen2 = Extract-IntValue -Text $outputText -Name 'HEALTH_HISTORY_LEN2'

if ($ack2 -ne 5 -or $lastOpcode2 -ne 19 -or $lastResult2 -ne 0 -or $cmdHistoryLen2 -ne 1 -or $cmdHistoryHead2 -ne 1 -or $cmdHistoryOverflow2 -ne 0 -or $firstSeq -ne 5 -or $firstOpcode -ne 19 -or $firstResult -ne 0 -or $firstTick -ne 4 -or $firstArg0 -ne 0 -or $firstArg1 -ne 0 -or $healthHistoryLen2 -ne 6) {
    throw "Unexpected command-event state. ack2=$ack2 lastOpcode2=$lastOpcode2 lastResult2=$lastResult2 cmdHistoryLen2=$cmdHistoryLen2 cmdHistoryHead2=$cmdHistoryHead2 cmdHistoryOverflow2=$cmdHistoryOverflow2 firstSeq=$firstSeq firstOpcode=$firstOpcode firstResult=$firstResult firstTick=$firstTick firstArg0=$firstArg0 firstArg1=$firstArg1 healthHistoryLen2=$healthHistoryLen2"
}

Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_COMMAND_EVENT_PROBE=pass'
Write-Output 'BAREMETAL_QEMU_BOOTDIAG_HISTORY_CLEAR_COMMAND_EVENT_PROBE_SOURCE=baremetal-qemu-bootdiag-history-clear-probe-check.ps1'
Write-Output "ACK2=$ack2"
Write-Output "LAST_OPCODE2=$lastOpcode2"
Write-Output "LAST_RESULT2=$lastResult2"
Write-Output "CMD_HISTORY_LEN2=$cmdHistoryLen2"
Write-Output "CMD_HISTORY_HEAD2=$cmdHistoryHead2"
Write-Output "CMD_HISTORY_OVERFLOW2=$cmdHistoryOverflow2"
Write-Output "CMD_HISTORY_FIRST_SEQ=$firstSeq"
Write-Output "CMD_HISTORY_FIRST_OPCODE=$firstOpcode"
Write-Output "CMD_HISTORY_FIRST_RESULT=$firstResult"
Write-Output "CMD_HISTORY_FIRST_TICK=$firstTick"
Write-Output "CMD_HISTORY_FIRST_ARG0=$firstArg0"
Write-Output "CMD_HISTORY_FIRST_ARG1=$firstArg1"
Write-Output "HEALTH_HISTORY_LEN2=$healthHistoryLen2"
