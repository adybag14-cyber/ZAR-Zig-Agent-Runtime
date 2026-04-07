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
    -SkippedReceipt 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PRE_EXCEPTION_PAYLOAD_PROBE' `
    -FailureLabel 'vector-history-clear' `
    -EchoOnSuccess:$true `
    -EchoOnSkip:$true `
    -EchoOnFailure:$true
$probeText = $probeState.Text

$preExceptionCount = Extract-IntValue -Text $probeText -Name 'PRE_EXCEPTION_COUNT'
$preExceptionHistoryLen = Extract-IntValue -Text $probeText -Name 'PRE_EXCEPTION_HISTORY_LEN'
$preException0Seq = Extract-IntValue -Text $probeText -Name 'PRE_EXCEPTION0_SEQ'
$preException0Vector = Extract-IntValue -Text $probeText -Name 'PRE_EXCEPTION0_VECTOR'
$preException0Code = Extract-IntValue -Text $probeText -Name 'PRE_EXCEPTION0_CODE'

if ($null -in @($preExceptionCount, $preExceptionHistoryLen, $preException0Seq, $preException0Vector, $preException0Code)) {
    throw 'Missing pre-exception payload fields in probe output.'
}
if ($preExceptionCount -ne 1) { throw "Expected PRE_EXCEPTION_COUNT=1. got $preExceptionCount" }
if ($preExceptionHistoryLen -ne 1) { throw "Expected PRE_EXCEPTION_HISTORY_LEN=1. got $preExceptionHistoryLen" }
if ($preException0Seq -ne 1 -or $preException0Vector -ne 13 -or $preException0Code -ne 51966) {
    throw "Unexpected exception payload: seq=$preException0Seq vector=$preException0Vector code=$preException0Code"
}

Write-Output 'BAREMETAL_QEMU_VECTOR_HISTORY_CLEAR_PRE_EXCEPTION_PAYLOAD_PROBE=pass'
Write-Output "PRE_EXCEPTION0_SEQ=$preException0Seq"
Write-Output "PRE_EXCEPTION0_VECTOR=$preException0Vector"
Write-Output "PRE_EXCEPTION0_CODE=$preException0Code"
