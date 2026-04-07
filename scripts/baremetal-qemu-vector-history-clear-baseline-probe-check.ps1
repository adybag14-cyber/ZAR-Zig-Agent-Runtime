# SPDX-License-Identifier: GPL-2.0-only
param(
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "baremetal-qemu-wrapper-common.ps1")
$probe = Join-Path $PSScriptRoot "baremetal-qemu-vector-history-clear-probe-check.ps1"
if (-not (Test-Path $probe)) { throw "Prerequisite probe not found: $probe" }

$probeState = Invoke-WrapperProbe `
    -ProbePath $probe `
    -SkipBuild:$SkipBuild `
    -SkippedPattern '(?m)^BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PROBE=skipped\\r?$' `
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_BASELINE_PROBE' `
    -FailureLabel 'vector-history-clear' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$ack = Extract-IntValue -Text $probeText -Name 'ACK'
$lastOpcode = Extract-IntValue -Text $probeText -Name 'LAST_OPCODE'
$lastResult = Extract-IntValue -Text $probeText -Name 'LAST_RESULT'
$ticks = Extract-IntValue -Text $probeText -Name 'TICKS'
$finalInterruptCount = Extract-IntValue -Text $probeText -Name 'FINAL_INTERRUPT_COUNT'
$finalExceptionCount = Extract-IntValue -Text $probeText -Name 'FINAL_EXCEPTION_COUNT'

if ($null -in @($ack, $lastOpcode, $lastResult, $ticks, $finalInterruptCount, $finalExceptionCount)) {
    throw 'Missing vector-history-clear baseline fields in probe output.'
}
if ($ack -ne 10) { throw "Expected ACK=10. got $ack" }
if ($lastOpcode -ne 13) { throw "Expected LAST_OPCODE=13. got $lastOpcode" }
if ($lastResult -ne 0) { throw "Expected LAST_RESULT=0. got $lastResult" }
if ($ticks -lt 10) { throw "Expected TICKS>=10. got $ticks" }
if ($finalInterruptCount -ne 0) { throw "Expected FINAL_INTERRUPT_COUNT=0. got $finalInterruptCount" }
if ($finalExceptionCount -ne 0) { throw "Expected FINAL_EXCEPTION_COUNT=0. got $finalExceptionCount" }

Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_BASELINE_PROBE=pass'
Write-Output "ACK=$ack"
Write-Output "LAST_OPCODE=$lastOpcode"
Write-Output "LAST_RESULT=$lastResult"
Write-Output "FINAL_INTERRUPT_COUNT=$finalInterruptCount"
Write-Output "FINAL_EXCEPTION_COUNT=$finalExceptionCount"
