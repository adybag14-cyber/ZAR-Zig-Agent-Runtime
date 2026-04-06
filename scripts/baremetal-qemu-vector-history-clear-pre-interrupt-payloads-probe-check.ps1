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
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PRE_INTERRUPT_PAYLOADS_PROBE' `
    -FailureLabel 'vector-history-clear' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$preInterruptCount = Extract-IntValue -Text $probeText -Name 'PRE_INTERRUPT_COUNT'
$preInterruptHistoryLen = Extract-IntValue -Text $probeText -Name 'PRE_INTERRUPT_HISTORY_LEN'
$preInterrupt0Seq = Extract-IntValue -Text $probeText -Name 'PRE_INTERRUPT0_SEQ'
$preInterrupt0Vector = Extract-IntValue -Text $probeText -Name 'PRE_INTERRUPT0_VECTOR'
$preInterrupt0IsException = Extract-IntValue -Text $probeText -Name 'PRE_INTERRUPT0_IS_EXCEPTION'
$preInterrupt0Code = Extract-IntValue -Text $probeText -Name 'PRE_INTERRUPT0_CODE'
$preInterrupt1Seq = Extract-IntValue -Text $probeText -Name 'PRE_INTERRUPT1_SEQ'
$preInterrupt1Vector = Extract-IntValue -Text $probeText -Name 'PRE_INTERRUPT1_VECTOR'
$preInterrupt1IsException = Extract-IntValue -Text $probeText -Name 'PRE_INTERRUPT1_IS_EXCEPTION'
$preInterrupt1Code = Extract-IntValue -Text $probeText -Name 'PRE_INTERRUPT1_CODE'

if ($null -in @($preInterruptCount, $preInterruptHistoryLen, $preInterrupt0Seq, $preInterrupt0Vector, $preInterrupt0IsException, $preInterrupt0Code, $preInterrupt1Seq, $preInterrupt1Vector, $preInterrupt1IsException, $preInterrupt1Code)) {
    throw 'Missing pre-interrupt payload fields in probe output.'
}
if ($preInterruptCount -ne 2) { throw "Expected PRE_INTERRUPT_COUNT=2. got $preInterruptCount" }
if ($preInterruptHistoryLen -ne 2) { throw "Expected PRE_INTERRUPT_HISTORY_LEN=2. got $preInterruptHistoryLen" }
if ($preInterrupt0Seq -ne 1 -or $preInterrupt0Vector -ne 200 -or $preInterrupt0IsException -ne 0 -or $preInterrupt0Code -ne 0) {
    throw "Unexpected first interrupt payload: seq=$preInterrupt0Seq vector=$preInterrupt0Vector is_exception=$preInterrupt0IsException code=$preInterrupt0Code"
}
if ($preInterrupt1Seq -ne 2 -or $preInterrupt1Vector -ne 13 -or $preInterrupt1IsException -ne 1 -or $preInterrupt1Code -ne 51966) {
    throw "Unexpected second interrupt payload: seq=$preInterrupt1Seq vector=$preInterrupt1Vector is_exception=$preInterrupt1IsException code=$preInterrupt1Code"
}

Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PRE_INTERRUPT_PAYLOADS_PROBE=pass'
Write-Output "PRE_INTERRUPT0_SEQ=$preInterrupt0Seq"
Write-Output "PRE_INTERRUPT0_VECTOR=$preInterrupt0Vector"
Write-Output "PRE_INTERRUPT1_SEQ=$preInterrupt1Seq"
Write-Output "PRE_INTERRUPT1_VECTOR=$preInterrupt1Vector"
